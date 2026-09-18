#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/LIBSYNC-V4-${TS}"
mkdir -p "$BK"

OLD='studiosat-radioprincipal-shadow-ns1.service'
NEW='studiosat-radioprincipal-shadow-v4.service'
V32='studiosat-radioprincipal-v32-core.service'
BIN='/opt/studiosat/radio-principal-v4/radioprincipal-library-shadow-v4.py'
UNIT="/etc/systemd/system/$NEW"

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe(){
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

rollback(){
  say "ROLLBACK_SHADOW_V4"
  systemctl disable --now "$NEW" 2>/dev/null || true
  systemctl enable "$OLD" 2>/dev/null || true
  systemctl restart "$OLD" 2>/dev/null || true
  say "ROLLBACK_APPLIED"
}

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " RADIO PRINCIPAL V4 - LIBRARY SYNC + EFFECTIVE QUEUE + SHADOW"
say "=============================================================="
say "BACKUP=$BK"

say "1/8 KEEP PUBLIC V3.2 LIVE"
systemctl is-active --quiet "$V32" || fail "V32_PUBLIC_CORE_NOT_ACTIVE"
probe rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"

say "2/8 INSTALL ENGINE"
install -d -m 0755 /opt/studiosat/radio-principal-v4
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v4/radioprincipal-library-shadow-v4.py' \
-o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
say "PYTHON_COMPILE=OK"

say "3/8 BUILD LIBRARY INDEX + QUEUE"
set +e
"$BIN" --check | tee "$BK/check.txt"
RC=${PIPESTATUS[0]}
set -e
if [ "$RC" -ne 0 ]; then
  cat "$BK/check.txt"
  fail "CURRENT_OR_NEXT_NOT_RESOLVED"
fi

grep -q '^CURRENT_READY=YES$' "$BK/check.txt" || fail "CURRENT_NOT_READY"
grep -q '^NEXT_READY=YES$' "$BK/check.txt" || fail "NEXT_NOT_READY"

COVERAGE="$(awk -F= '/^COVERAGE_PCT=/{print $2}' "$BK/check.txt" | tail -1)"
python3 - "$COVERAGE" <<'PY' || exit 24
import sys
v=float(sys.argv[1] or 0)
print(f"COVERAGE_CHECK={v}")
if v < 80:
    raise SystemExit(1)
PY
say "LIBRARY_QUEUE_PREFLIGHT=PASS"

say "4/8 INSTALL SHADOW V4 SERVICE"
systemctl cat "$OLD" >"$BK/old-shadow.unit.txt" 2>&1 || true
cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V4 library-synchronized shadow
After=network-online.target tps-mediamtx.service
Requires=tps-mediamtx.service
Conflicts=$OLD

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/python3 $BIN
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/run/studiosat /var/lib/studiosat/radio-principal-v4

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

say "5/8 SWAP SHADOW ONLY - PUBLIC LIVE V3.2 REMAINS"
systemctl disable --now "$OLD" 2>/dev/null || true
if ! systemctl enable --now "$NEW"; then
  rollback
  fail "SHADOW_V4_START_FAILED"
fi

say "6/8 REQUIRE SYNCHRONIZED NS1 RTMP"
READY=0
for i in $(seq 1 30); do
  if probe rtmp://127.0.0.1:1935/radioprincipal-ns1; then
    READY=1
    say "SHADOW_V4_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  journalctl -u "$NEW" -n 120 --no-pager || true
  rollback
  fail "SHADOW_V4_RTMP_NOT_READY"
fi

say "7/8 REQUIRE QUEUE + CURRENT SYNC"
OK=0
for i in $(seq 1 20); do
  if python3 - <<'PY'
import json,sys
q=json.load(open('/var/lib/studiosat/radio-principal-v4/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v4/state.json'))
cur=q.get('current') or {}
ok=(cur.get('virtual') or cur.get('available')) and q.get('missing_count') is not None and s.get('current_index') is not None
print("QUEUE_COVERAGE_PCT="+str(q.get('coverage_pct')))
print("QUEUE_MISSING="+str(q.get('missing_count')))
print("CURRENT="+str(cur.get('source_path')))
print("CURRENT_LOCAL="+str(cur.get('local_path')))
print("SHADOW_MODE="+str(s.get('mode')))
print("SHADOW_CURRENT_INDEX="+str(s.get('current_index')))
sys.exit(0 if ok else 1)
PY
  then
    OK=1
    break
  fi
  sleep 1
done
if [ "$OK" -ne 1 ]; then
  rollback
  fail "QUEUE_OR_CURRENT_SYNC_NOT_READY"
fi

say "8/8 FINAL"
python3 - <<'PY'
import json
idx=json.load(open('/var/lib/studiosat/radio-principal-v4/library-index.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-v4/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v4/state.json'))
print("LIBRARY_INDEX_FILES="+str(idx.get('count')))
print("QUEUE_TRACKS="+str(q.get('track_count')))
print("QUEUE_AVAILABLE="+str(q.get('available_count')))
print("QUEUE_MISSING="+str(q.get('missing_count')))
print("QUEUE_COVERAGE_PCT="+str(q.get('coverage_pct')))
print("CURRENT_SOURCE="+str((q.get('current') or {}).get('source_path')))
print("CURRENT_LOCAL="+str((q.get('current') or {}).get('local_path')))
print("NEXT_SOURCE="+str((q.get('next') or {}).get('source_path')))
print("NEXT_LOCAL="+str((q.get('next') or {}).get('local_path')))
print("PLAYLISTPOS="+str((q.get('playback') or {}).get('playlistpos')))
print("POS_MS="+str((q.get('playback') or {}).get('pos_ms')))
print("SHADOW_MODE="+str(s.get('mode')))
print("SHADOW_CURRENT_INDEX="+str(s.get('current_index')))
PY

echo "PUBLIC_V32=$(systemctl is-active "$V32")"
echo "SHADOW_V4=$(systemctl is-active "$NEW")"
echo "OLD_SHADOW=$(systemctl is-active "$OLD" 2>/dev/null || true)"
echo "PUBLIC_RTMP=READY"
echo "NS1_SHADOW_RTMP=READY"
echo "RADIOBOSS_LIBRARY_SYNC=ACTIVE"
echo "RESULTADO=RADIOPRINCIPAL_V4_LIBRARY_SYNC_SHADOW_ACTIVE"
