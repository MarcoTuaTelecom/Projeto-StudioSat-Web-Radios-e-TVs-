#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V32-FINALIZE-${TS}"
mkdir -p "$BK"

CORE='studiosat-radioprincipal-v32-core.service'
ICE='studiosat-radioprincipal-v31-icecast.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
WARM='studiosat-radioprincipal-v32-hls-warmer.service'
HEALTH='studiosat-radioprincipal-v32-health.service'

WARM_BIN='/opt/studiosat/radio-principal-v32/hls-warmer.sh'
HEALTH_BIN='/opt/studiosat/radio-principal-v32/health-server.py'

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe_rtmp(){
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

say "=============================================================="
say " STUDIO SAT RADIO PRINCIPAL V3.2 - PRODUCTION FINALIZE"
say "=============================================================="
say "BACKUP=$BK"

say "1/8 REQUIRE V3.2 LIVE"
systemctl is-active --quiet "$CORE" || fail "V32_CORE_NOT_ACTIVE"
systemctl is-active --quiet "$ICE" || fail "ICECAST_NOT_ACTIVE"
systemctl is-active --quiet "$SHADOW" || fail "SHADOW_NOT_ACTIVE"
probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal' || fail "PUBLIC_RTMP_NOT_READY"

python3 - <<'PY' || exit 21
import json,sys,time
p='/run/studiosat/radioprincipal-v32-state.json'
a=json.load(open(p))
if a.get('selected_source')!='live':
    print('FATAL=PUBLIC_SOURCE_NOT_LIVE')
    sys.exit(1)
b1=int(a.get('live_bytes') or 0)
time.sleep(3)
b=json.load(open(p))
b2=int(b.get('live_bytes') or 0)
age=b.get('live_age_sec')
print(f"LIVE_BYTES_BEFORE={b1}")
print(f"LIVE_BYTES_AFTER={b2}")
print(f"LIVE_AGE_SEC={age}")
print(f"METADATA={b.get('metadata_title')}")
if b.get('selected_source')!='live' or b2 <= b1 or not isinstance(age,(int,float)) or age >= 1.0:
    print('FATAL=RADIOBOSS_PCM_NOT_CONTINUOUS')
    sys.exit(2)
print('RADIOBOSS_PCM=CONTINUOUS')
PY

say "2/8 INSTALL HLS WARMER + HEALTH"
install -d -m 0755 /opt/studiosat/radio-principal-v32

curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v3/radioprincipal-v32-hls-warmer.sh' \
-o "$WARM_BIN"
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v3/radioprincipal-v32-health.py' \
-o "$HEALTH_BIN"

chmod 0755 "$WARM_BIN" "$HEALTH_BIN"
python3 -m py_compile "$HEALTH_BIN"

cat >/etc/systemd/system/$WARM <<EOF
[Unit]
Description=Studio Sat Radio Principal V3.2 HLS warmer
After=network-online.target tps-mediamtx.service $CORE
Requires=tps-mediamtx.service $CORE

[Service]
Type=simple
User=root
Group=root
ExecStart=$WARM_BIN
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/run/studiosat

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/$HEALTH <<EOF
[Unit]
Description=Studio Sat Radio Principal V3.2 health endpoint
After=network-online.target $CORE $WARM
Requires=$CORE

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/python3 $HEALTH_BIN
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$WARM" "$HEALTH"

say "3/8 WARM HLS"
HLS_LOCAL=0
for i in $(seq 1 30); do
  if curl -LfsS --max-time 8 \
      http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null |
      grep -q '^#EXTM3U'; then
    HLS_LOCAL=1
    say "LOCAL_HLS=READY AFTER=${i}s"
    break
  fi
  sleep 2
done

if [ "$HLS_LOCAL" -ne 1 ]; then
  say "LOCAL_HLS_STILL_COLD_TRYING_MEDIAMTX_ALWAYS_REMUX"
  curl -fsS -X PATCH \
    -H 'Content-Type: application/json' \
    -d '{"hlsAlwaysRemux":true}' \
    http://127.0.0.1:9997/v3/config/global/patch \
    >"$BK/mediamtx-hls-patch.out" 2>"$BK/mediamtx-hls-patch.err" || true

  for i in $(seq 1 30); do
    if curl -LfsS --max-time 8 \
        http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null |
        grep -q '^#EXTM3U'; then
      HLS_LOCAL=1
      say "LOCAL_HLS=READY_AFTER_ALWAYS_REMUX AFTER=${i}s"
      break
    fi
    sleep 2
  done
fi
[ "$HLS_LOCAL" -eq 1 ] || fail "LOCAL_HLS_NOT_READY"

say "4/8 REQUIRE PUBLIC HTTPS HLS"
PUBLIC_HLS=0
for i in $(seq 1 30); do
  if curl -LfsS --max-time 10 \
      https://radio.studiosatweb.com.br/radioprincipal/index.m3u8 2>/dev/null |
      grep -q '^#EXTM3U'; then
    PUBLIC_HLS=1
    say "PUBLIC_HTTPS_HLS=READY AFTER=${i}s"
    break
  fi
  sleep 2
done
[ "$PUBLIC_HLS" -eq 1 ] || fail "PUBLIC_HTTPS_HLS_NOT_READY"

say "5/8 LOCK BOOT BASELINE"
for u in \
  studiosat-radioprincipal-selector.service \
  studiosat-radioprincipal-emergency-direct.service \
  studiosat-radioprincipal-v3-core.service \
  studiosat-radioprincipal-v3-icecast.service \
  studiosat-radioprincipal-v31-core.service
do
  systemctl disable --now "$u" 2>/dev/null || true
done

systemctl enable "$CORE" "$ICE" "$SHADOW" "$WARM" "$HEALTH" >/dev/null

say "6/8 HEALTH ENDPOINT"
HEALTH_OK=0
for i in $(seq 1 15); do
  if curl -fsS --max-time 5 http://127.0.0.1:8812/readyz \
      >"$BK/health.json"; then
    HEALTH_OK=1
    cat "$BK/health.json"
    break
  fi
  sleep 1
done
[ "$HEALTH_OK" -eq 1 ] || fail "HEALTH_NOT_READY"

say "7/8 FINAL ACCEPTANCE"
probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal' || fail "PUBLIC_RTMP_LOST"

python3 - <<'PY' || exit 31
import json,sys,time
p='/run/studiosat/radioprincipal-v32-state.json'
a=json.load(open(p))
b1=int(a.get('live_bytes') or 0)
time.sleep(5)
b=json.load(open(p))
b2=int(b.get('live_bytes') or 0)
print(f"FINAL_SOURCE={b.get('selected_source')}")
print(f"FINAL_METADATA={b.get('metadata_title')}")
print(f"FINAL_LIVE_AGE={b.get('live_age_sec')}")
print(f"FINAL_LIVE_BYTES_DELTA={b2-b1}")
if b.get('selected_source')!='live' or b2<=b1 or (b.get('live_age_sec') or 99)>=1:
    sys.exit(1)
PY

say "8/8 RESULT"
echo "V32_CORE=$(systemctl is-active "$CORE")"
echo "ICECAST=$(systemctl is-active "$ICE")"
echo "SHADOW=$(systemctl is-active "$SHADOW")"
echo "HLS_WARMER=$(systemctl is-active "$WARM")"
echo "HEALTH=$(systemctl is-active "$HEALTH")"
echo "PUBLIC_RTMP=READY"
echo "LOCAL_HLS=READY"
echo "PUBLIC_HTTPS_HLS=READY"
echo "PUBLIC_SOURCE=RADIOBOSS_LIVE_PCM"
echo "HEALTH_URL=http://127.0.0.1:8812/readyz"
echo "RESULTADO=RADIOPRINCIPAL_V32_PRODUCTION_FINALIZED"
