#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/RADIOPRINCIPAL-V6-${TS}"
mkdir -p "$BK"

V32='studiosat-radioprincipal-v32-core.service'
V6='studiosat-radioprincipal.service'
LAB='studiosat-radioprincipal-v6-lab.service'
RBSYNC='studiosat-radioboss-sync.service'
BRIDGE='studiosat-radioprincipal-v8-control-bridge.service'
MEDIATRANSFER='studiosat-media-transfer.service'
ICE='studiosat-radioprincipal-v31-icecast.service'
OLD_SHADOW='studiosat-radioprincipal-shadow-ns1.service'

BIN='/opt/studiosat/radio-principal/radioprincipal-production-v6.py'
UNIT="/etc/systemd/system/$V6"
LABUNIT="/etc/systemd/system/$LAB"
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
CONTROL='/run/studiosat-radioprincipal-v8-control/playback.json'
BASE='/var/lib/studiosat/radio-principal'
LABBASE='/var/lib/studiosat/radio-principal-v6-lab'

MUTATED=0

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }
probe(){ timeout 8 ffprobe -v error -rw_timeout 5000000 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$1" 2>/dev/null | grep -q .; }

rollback(){
  [ "$MUTATED" -eq 1 ] || return 0
  say "ROLLBACK_TO_V32"
  systemctl disable --now "$V6" 2>/dev/null || true
  systemctl enable "$V32" 2>/dev/null || true
  systemctl restart "$V32" 2>/dev/null || true
  systemctl disable --now "$LAB" 2>/dev/null || true
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " RADIO PRINCIPAL V6 - FINAL CONSOLIDATED PRODUCTION"
say "=============================================================="
say "BACKUP=$BK"

say "1/12 FREEZE CURRENT PUBLIC BASELINE"
systemctl is-active --quiet "$V32" || fail "V32_NOT_ACTIVE"
probe rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"
echo "CURRENT_PUBLIC=READY"

say "2/12 REQUIRE EXISTING CONTROL + MEDIA SERVICES"
systemctl is-active --quiet "$RBSYNC" || systemctl start "$RBSYNC"
systemctl is-active --quiet "$BRIDGE" || systemctl start "$BRIDGE"
systemctl is-active --quiet "$MEDIATRANSFER" || systemctl start "$MEDIATRANSFER"

say "3/12 INSTALL EXACT TESTED ENGINE"
install -d -m 0755 /opt/studiosat/radio-principal
curl -fsSL 'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/final/radioprincipal-production-v6.py' -o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
"$BIN" --selftest | tee "$BK/selftest.txt"
grep -q '^SELFTEST=PASS$' "$BK/selftest.txt" || fail "SELFTEST_FAILED"

say "4/12 REAL LIBRARY / QUEUE PREFLIGHT"
set +e
STUDIOSAT_V6_CONTROL_PLAYBACK="$CONTROL" STUDIOSAT_V6_CONTROL_FRESH_SEC=15 "$BIN" --check | tee "$BK/real-check.txt"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" -eq 0 ] || fail "CURRENT_OR_NEXT_NOT_RESOLVED"

CURRENT_READY="$(awk -F= '/^CURRENT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
NEXT_READY="$(awk -F= '/^NEXT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
COVERAGE="$(awk -F= '/^COVERAGE_PCT=/{print $2}' "$BK/real-check.txt" | tail -1)"
[ "$CURRENT_READY" = YES ] || fail "CURRENT_NOT_READY"
[ "$NEXT_READY" = YES ] || fail "NEXT_NOT_READY"
python3 - "$COVERAGE" <<'PY'
import sys
v=float(sys.argv[1] or 0)
print(f"COVERAGE_GATE={v}")
if v < 80: raise SystemExit(1)
PY

CURRENT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal/effective-queue.json'))
print((q.get('current') or {}).get('local_path') or '')
PY
)"
NEXT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal/effective-queue.json'))
print((q.get('next') or {}).get('local_path') or '')
PY
)"
probe "$CURRENT_LOCAL" || fail "CURRENT_AUDIO_NOT_DECODABLE"
probe "$NEXT_LOCAL" || fail "NEXT_AUDIO_NOT_DECODABLE"

say "5/12 SHOW CONTROL MODE"
python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal/effective-queue.json'))
for k in ("control_source","control_age_sec","control_mode","control_extrapolated_hops","effective_pos_ms"):
    print(k.upper()+"="+str(q.get(k)))
PY

say "6/12 BUILD LAB SERVICE ON EXISTING radioprincipal-test PATH"
cat >"$LABUNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V6 lab candidate
After=network-online.target tps-mediamtx.service $RBSYNC $BRIDGE $MEDIATRANSFER
Requires=tps-mediamtx.service $RBSYNC $BRIDGE
Wants=$MEDIATRANSFER

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_V6_BASE=$LABBASE
Environment=STUDIOSAT_V6_CONTROL_FRESH_SEC=15
Environment=STUDIOSAT_V6_CONTROL_PLAYBACK=$CONTROL
Environment=STUDIOSAT_V6_RTMP=rtmp://127.0.0.1:1935/radioprincipal-test
ExecStart=/usr/bin/python3 $BIN
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=$SYNC $CONTROL
ReadWritePaths=$LABBASE

[Install]
WantedBy=multi-user.target
EOF
systemd-analyze verify "$LABUNIT"
systemctl daemon-reload
systemctl disable --now "$LAB" 2>/dev/null || true
systemctl enable --now "$LAB"

say "7/12 REQUIRE LAB RTMP + AUDIO"
LAB_OK=0
for i in $(seq 1 25); do
  if systemctl is-active --quiet "$LAB" && probe rtmp://127.0.0.1:1935/radioprincipal-test; then
    LAB_OK=1; echo "LAB_RTMP=READY AFTER=${i}s"; break
  fi
  sleep 1
done
[ "$LAB_OK" -eq 1 ] || { journalctl -u "$LAB" -n 120 --no-pager || true; fail "LAB_NOT_READY"; }

say "8/12 REQUIRE LAB STATE HEALTH"
python3 - <<'PY'
import json,sys,time
p='/var/lib/studiosat/radio-principal-v6-lab/state.json'
for _ in range(15):
    try:
        s=json.load(open(p)); age=s.get('last_audio_age_sec'); mode=s.get('mode'); cur=s.get('current') or {}
        print("LAB_MODE="+str(mode)); print("LAB_CURRENT="+str(cur.get('source_path'))); print("LAB_AUDIO_AGE_SEC="+str(age))
        if mode in ('hot-sync','autonomous-extrapolated','autonomous') and isinstance(age,(int,float)) and age<1.5 and cur.get('local_path'):
            raise SystemExit(0)
    except FileNotFoundError: pass
    time.sleep(1)
raise SystemExit(1)
PY

say "9/12 INSTALL SINGLE CANONICAL PRODUCTION SERVICE"
cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal canonical production
After=network-online.target tps-mediamtx.service $RBSYNC $BRIDGE $MEDIATRANSFER
Requires=tps-mediamtx.service $RBSYNC $BRIDGE
Wants=$MEDIATRANSFER
Conflicts=$V32

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_V6_BASE=$BASE
Environment=STUDIOSAT_V6_CONTROL_FRESH_SEC=15
Environment=STUDIOSAT_V6_CONTROL_PLAYBACK=$CONTROL
Environment=STUDIOSAT_V6_RTMP=rtmp://127.0.0.1:1935/radioprincipal
ExecStart=/usr/bin/python3 $BIN
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=$SYNC $CONTROL
ReadWritePaths=$BASE

[Install]
WantedBy=multi-user.target
EOF
systemd-analyze verify "$UNIT"
systemctl daemon-reload

say "10/12 CONTROLLED CUTOVER"
systemctl disable --now "$LAB" 2>/dev/null || true
systemctl disable --now "$V32" 2>/dev/null || true
MUTATED=1
systemctl enable --now "$V6"

PUB_OK=0
for i in $(seq 1 25); do
  if systemctl is-active --quiet "$V6" && probe rtmp://127.0.0.1:1935/radioprincipal; then
    PUB_OK=1; echo "PUBLIC_RTMP=READY AFTER=${i}s"; break
  fi
  sleep 1
done
[ "$PUB_OK" -eq 1 ] || { journalctl -u "$V6" -n 120 --no-pager || true; fail "PUBLIC_V6_NOT_READY"; }

say "11/12 REQUIRE PUBLIC HLS"
HLS_OK=0
for i in $(seq 1 25); do
  if curl -LfsS --max-time 8 https://radio.studiosatweb.com.br/radioprincipal/index.m3u8 2>/dev/null | grep -q '^#EXTM3U'; then
    HLS_OK=1; echo "PUBLIC_HLS=READY AFTER=${i}s"; break
  fi
  sleep 1
done
[ "$HLS_OK" -eq 1 ] || fail "PUBLIC_HLS_NOT_READY"

say "12/12 CONSOLIDATE OLD COMPETING AUDIO PATHS"
systemctl disable --now "$ICE" 2>/dev/null || true
systemctl disable --now "$OLD_SHADOW" 2>/dev/null || true
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-emergency-direct.service studiosat-radioprincipal-v3-core.service studiosat-radioprincipal-v3-icecast.service studiosat-radioprincipal-v31-core.service studiosat-radioprincipal-v32-hls-warmer.service studiosat-radioprincipal-v32-health.service studiosat-radioprincipal-v51.service studiosat-radioprincipal-v5.service; do
  systemctl disable --now "$u" 2>/dev/null || true
done

if id studiosat-rb-tunnel >/dev/null 2>&1; then
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-studiosat-disable-rb-tunnel.conf <<'EOF'
DenyUsers studiosat-rb-tunnel
EOF
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  pkill -u studiosat-rb-tunnel 2>/dev/null || true
  echo "OBSOLETE_AUDIO_TUNNEL=DISABLED_SERVER_SIDE"
fi

systemctl enable "$V6" "$RBSYNC" "$BRIDGE" "$MEDIATRANSFER" >/dev/null 2>&1 || true

python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal/state.json'))
idx=json.load(open('/var/lib/studiosat/radio-principal/library-index.json'))
for k,v in [
("LIBRARY_FILES",idx.get("count")),("DB_ALIASES",idx.get("db_aliases")),("QUEUE_TRACKS",q.get("track_count")),
("QUEUE_AVAILABLE",q.get("available_count")),("QUEUE_MISSING",q.get("missing_count")),("QUEUE_COVERAGE_PCT",q.get("coverage_pct")),
("CONTROL_SOURCE",q.get("control_source")),("CONTROL_AGE_SEC",q.get("control_age_sec")),("CONTROL_MODE",q.get("control_mode")),
("CURRENT_SOURCE",(q.get("current") or {}).get("source_path")),("CURRENT_LOCAL",(q.get("current") or {}).get("local_path")),
("NEXT_SOURCE",(q.get("next") or {}).get("source_path")),("NEXT_LOCAL",(q.get("next") or {}).get("local_path")),
("EFFECTIVE_POS_MS",q.get("effective_pos_ms")),("PLAYOUT_MODE",s.get("mode")),("PLAYOUT_AUDIO_AGE",s.get("last_audio_age_sec"))]:
    print(str(k)+"="+str(v))
PY

echo "RADIOPRINCIPAL=$(systemctl is-active "$V6")"
echo "RADIOBOSS_SYNC=$(systemctl is-active "$RBSYNC")"
echo "CONTROL_BRIDGE=$(systemctl is-active "$BRIDGE")"
echo "MEDIA_TRANSFER=$(systemctl is-active "$MEDIATRANSFER")"
echo "PUBLIC_RTMP=READY"
echo "PUBLIC_HLS=READY"
echo "AUDIO_TUNNEL_REQUIRED=NO"
echo "ARCHITECTURE=ONE_CANONICAL_SERVER_PLAYOUT"
echo "RESULTADO=RADIOPRINCIPAL_V6_PRODUCTION_ACTIVE"
MUTATED=0
