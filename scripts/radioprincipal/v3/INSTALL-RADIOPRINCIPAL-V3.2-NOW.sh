#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V32-CUTOVER-${TS}"

ICECAST_SVC="studiosat-radioprincipal-v31-icecast.service"
V31_CORE="studiosat-radioprincipal-v31-core.service"
V32_CORE="studiosat-radioprincipal-v32-core.service"
SHADOW="studiosat-radioprincipal-shadow-ns1.service"
SELECTOR="studiosat-radioprincipal-selector.service"

CORE_DIR="/opt/studiosat/radio-principal-v32"
CORE_PY="$CORE_DIR/radioprincipal-core-v3.2.py"
CORE_UNIT="/etc/systemd/system/$V32_CORE"
ENV_FILE="/etc/studiosat/radioprincipal-v32.env"

mkdir -p "$BK"

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe(){
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

path_ready(){
  timeout 5 curl -fsS "http://127.0.0.1:9997/v3/paths/get/$1" 2>/dev/null |
    grep -q '"ready":true'
}

rollback(){
  say "ROLLBACK_TO_V31"
  systemctl disable --now "$V32_CORE" 2>/dev/null || true
  systemctl enable "$V31_CORE" 2>/dev/null || true
  systemctl restart "$V31_CORE" 2>/dev/null || true
}

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " STUDIO SAT RADIO PRINCIPAL V3.2 - LIVE PCM VERIFIED"
say "=============================================================="
say "BACKUP=$BK"

say "1/8 REQUIRE CURRENT INGEST + SHADOW"
systemctl is-active --quiet "$ICECAST_SVC" || systemctl start "$ICECAST_SVC"
systemctl is-active --quiet "$SHADOW" || systemctl start "$SHADOW"

probe 'rtmp://127.0.0.1:1935/radioprincipal-ns1' || fail "SHADOW_NOT_READY"
ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005' || fail "ICECAST_18005_NOT_LISTENING"
say "INGEST_AND_SHADOW=READY"

say "2/8 BUILD V3.2"
install -d -m 0755 "$CORE_DIR"
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v3/radioprincipal-core-v3.2.py' \
-o "$CORE_PY"
chmod 0755 "$CORE_PY"
python3 -m py_compile "$CORE_PY"
say "PYTHON_COMPILE=OK"

say "3/8 VERIFY RADIOBOSS AUDIO BYTES BEFORE CUTOVER"
LIVE_PRE=0
for i in $(seq 1 20); do
  if probe 'http://127.0.0.1:18005/radioprincipal-rb'; then
    LIVE_PRE=1
    say "RADIOBOSS_ICECAST_AUDIO=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

if [ "$LIVE_PRE" -ne 1 ]; then
  say "RADIOBOSS_NOT_READY_RESTARTING_ICECAST_ONCE"
  systemctl restart "$ICECAST_SVC"
  for i in $(seq 1 30); do
    if probe 'http://127.0.0.1:18005/radioprincipal-rb'; then
      LIVE_PRE=1
      say "RADIOBOSS_ICECAST_AUDIO=READY AFTER_RESTART=${i}s"
      break
    fi
    sleep 1
  done
fi

[ "$LIVE_PRE" -eq 1 ] || fail "RADIOBOSS_IS_NOT_DELIVERING_AUDIO_TO_ICECAST"

say "4/8 INSTALL V3.2 SERVICE"
cat >"$ENV_FILE" <<'EOF'
LIVE_URL=http://127.0.0.1:18005/radioprincipal-rb
ICECAST_STATUS=http://127.0.0.1:18005/status-json.xsl
FALLBACK_RTMP=rtmp://127.0.0.1:1935/radioprincipal-ns1
PUBLIC_RTMP=rtmp://127.0.0.1:1935/radioprincipal
STATE_PATH=/run/studiosat/radioprincipal-v32-state.json
PROMOTE_SEC=5
LIVE_GAP_SEC=0.50
FALLBACK_GAP_SEC=1.50
RESTART_DECODER_SEC=1
STATE_INTERVAL_SEC=1
EOF

cat >"$CORE_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V3.2 dual-decoder continuous core
After=network-online.target tps-mediamtx.service $SHADOW $ICECAST_SVC
Requires=tps-mediamtx.service $SHADOW $ICECAST_SVC
Conflicts=$V31_CORE $SELECTOR

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/python3 $CORE_PY
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/run/studiosat

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

say "5/8 CUTOVER CORE ONLY"
systemctl disable --now "$V31_CORE" 2>/dev/null || true
systemctl reset-failed "$V32_CORE" 2>/dev/null || true
if ! systemctl enable --now "$V32_CORE"; then
  rollback
  fail "V32_CORE_START_FAILED"
fi

say "6/8 REQUIRE PUBLIC RTMP"
PUB=0
for i in $(seq 1 20); do
  if path_ready radioprincipal && probe 'rtmp://127.0.0.1:1935/radioprincipal'; then
    PUB=1
    say "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
if [ "$PUB" -ne 1 ]; then
  journalctl -u "$V32_CORE" -n 120 --no-pager || true
  rollback
  fail "PUBLIC_RTMP_NOT_READY"
fi

say "7/8 REQUIRE ACTUAL LIVE PCM"
LIVE=0
for i in $(seq 1 30); do
  SRC="$(python3 - <<'PY'
import json
try:
    d=json.load(open('/run/studiosat/radioprincipal-v32-state.json'))
    print(d.get('selected_source') or 'unknown')
except Exception:
    print('unknown')
PY
)"
  LAGE="$(python3 - <<'PY'
import json
try:
    d=json.load(open('/run/studiosat/radioprincipal-v32-state.json'))
    print(d.get('live_age_sec'))
except Exception:
    print('unknown')
PY
)"
  say "SOURCE=$SRC LIVE_AGE=$LAGE WAIT=${i}s"
  if [ "$SRC" = "live" ]; then
    LIVE=1
    break
  fi
  sleep 1
done

say "8/8 FINAL"
STATE="$(cat /run/studiosat/radioprincipal-v32-state.json 2>/dev/null || true)"
echo "$STATE"

HLS=0
for i in $(seq 1 15); do
  if timeout 6 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null | grep -q '^#EXTM3U'; then
    HLS=1
    break
  fi
  sleep 1
done

echo "V32_CORE=$(systemctl is-active "$V32_CORE" 2>/dev/null || true)"
echo "ICECAST=$(systemctl is-active "$ICECAST_SVC" 2>/dev/null || true)"
echo "SHADOW=$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
echo "V31_CORE=$(systemctl is-active "$V31_CORE" 2>/dev/null || true)"
echo "OLD_SELECTOR=$(systemctl is-active "$SELECTOR" 2>/dev/null || true)"
echo "PUBLIC_RTMP=READY"
[ "$HLS" -eq 1 ] && echo "PUBLIC_HLS=READY" || echo "PUBLIC_HLS=PENDING"
if [ "$LIVE" -eq 1 ]; then
  echo "PUBLIC_SOURCE=RADIOBOSS_LIVE_PCM"
  echo "RESULTADO=RADIOPRINCIPAL_V32_RADIOBOSS_ON_AIR"
  exit 0
fi

echo "PUBLIC_SOURCE=FALLBACK_NS1"
echo "RESULTADO=RADIOPRINCIPAL_V32_PUBLIC_ON_AIR_BUT_RADIOBOSS_NOT_SELECTED"
exit 40
