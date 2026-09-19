#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/STABLE-SHADOW-${TS}"
mkdir -p "$BK"

PUBLIC='studiosat-radioprincipal-v32-core.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
BIN='/opt/studiosat/radio-principal-stable/radioprincipal-stable-shadow-v6.1.py'
UNIT_PATH="$(systemctl show -p FragmentPath --value "$SHADOW")"
BASE='/var/lib/studiosat/radio-principal-stable'
CONTROL='/run/studiosat-radioprincipal-v8-control/playback.json'
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe(){
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

rollback(){
  say "ROLLBACK_SHADOW"
  if [ -f "$BK/shadow.service.before" ] && [ -n "$UNIT_PATH" ]; then
    cp -a "$BK/shadow.service.before" "$UNIT_PATH"
    systemctl daemon-reload
    systemctl restart "$SHADOW" || true
  fi
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"
[ -n "$UNIT_PATH" ] && [ -f "$UNIT_PATH" ] || fail "SHADOW_UNIT_NOT_FOUND"

say "=============================================================="
say " RADIO PRINCIPAL - STABLE NS1 SHADOW / NO SEEK LOOP"
say "=============================================================="
say "BACKUP=$BK"

say "1/8 KEEP PUBLIC RADIO ONLINE"
systemctl is-active --quiet "$PUBLIC" || fail "PUBLIC_V32_NOT_ACTIVE"
probe rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"
echo "PUBLIC_BASELINE=READY"

say "2/8 BACKUP CURRENT SHADOW"
cp -a "$UNIT_PATH" "$BK/shadow.service.before"
systemctl cat "$SHADOW" >"$BK/shadow.unit.before.txt" 2>&1 || true

say "3/8 INSTALL PRE-TESTED STABLE ENGINE"
install -d -m 0755 /opt/studiosat/radio-principal-stable
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/final/radioprincipal-stable-shadow-v6.1.py' \
-o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
"$BIN" --selftest | tee "$BK/selftest.txt"
grep -q '^SELFTEST=PASS$' "$BK/selftest.txt" || fail "SELFTEST_FAILED"

say "4/8 RESOLVE CURRENT + NEXT BEFORE CUTOVER"
set +e
STUDIOSAT_STABLE_BASE="$BASE" \
STUDIOSAT_STABLE_CONTROL_PLAYBACK="$CONTROL" \
STUDIOSAT_STABLE_CONTROL_FRESH_SEC=15 \
"$BIN" --check | tee "$BK/check.txt"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" -eq 0 ] || fail "CURRENT_OR_NEXT_NOT_RESOLVED"

grep -q '^CURRENT_READY=YES$' "$BK/check.txt" || fail "CURRENT_NOT_READY"
grep -q '^NEXT_READY=YES$' "$BK/check.txt" || fail "NEXT_NOT_READY"

say "5/8 INSTALL STABLE SHADOW SERVICE"
cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Studio Sat Radio Principal stable NS1 shadow
After=network-online.target tps-mediamtx.service
Requires=tps-mediamtx.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_STABLE_BASE=$BASE
Environment=STUDIOSAT_STABLE_CONTROL_PLAYBACK=$CONTROL
Environment=STUDIOSAT_STABLE_CONTROL_FRESH_SEC=15
Environment=STUDIOSAT_STABLE_RTMP=rtmp://127.0.0.1:1935/radioprincipal-ns1
ExecStart=/usr/bin/python3 $BIN
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=$SYNC $CONTROL
ReadWritePaths=$BASE

[Install]
WantedBy=multi-user.target
EOF

systemd-analyze verify "$UNIT_PATH"
systemctl daemon-reload
systemctl restart "$SHADOW"

say "6/8 REQUIRE STABLE SHADOW RTMP"
OK=0
for i in $(seq 1 30); do
  if systemctl is-active --quiet "$SHADOW" &&
     probe rtmp://127.0.0.1:1935/radioprincipal-ns1; then
    OK=1
    echo "SHADOW_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$OK" -eq 1 ] || fail "STABLE_SHADOW_NOT_READY"

say "7/8 PROVE NO RESTART / NO SEEK CHURN"
PID1="$(systemctl show -p MainPID --value "$SHADOW")"
python3 - <<'PY'
import json,time,sys,os
p='/var/lib/studiosat/radio-principal-stable/state.json'
last=None
for i in range(12):
    try:
        s=json.load(open(p))
        cur=s.get('current') or {}
        print("SAMPLE",i,
              "mode="+str(s.get('mode')),
              "index="+str(s.get('current_index')),
              "audio_age="+str(s.get('last_audio_age_sec')),
              "file="+str(cur.get('local_path')))
        if s.get('last_audio_age_sec') is None or s.get('last_audio_age_sec')>1.5:
            raise SystemExit(2)
        if last is not None and s.get('current_index') != last and i < 5:
            # Early item jumps during first seconds indicate churn.
            raise SystemExit(3)
        last=s.get('current_index')
    except FileNotFoundError:
        raise SystemExit(4)
    time.sleep(1)
PY
PID2="$(systemctl show -p MainPID --value "$SHADOW")"
[ "$PID1" = "$PID2" ] || fail "SHADOW_PROCESS_RESTARTED"

echo "SHADOW_PID_STABLE=$PID2"
echo "NO_SEEK_CHURN=PASS"

say "8/8 VERIFY PUBLIC STILL ONLINE"
probe rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_LOST"

python3 - <<'PY'
import json
s=json.load(open('/var/lib/studiosat/radio-principal-stable/state.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-stable/effective-queue.json'))
print("MODE="+str(s.get('mode')))
print("CURRENT_INDEX="+str(s.get('current_index')))
print("CURRENT_LOCAL="+str((s.get('current') or {}).get('local_path')))
print("NEXT_LOCAL="+str((q.get('next') or {}).get('local_path')))
print("CONTROL_AGE_SEC="+str(q.get('control_age_sec')))
print("CONTROL_MODE="+str(q.get('control_mode')))
print("QUEUE_COVERAGE_PCT="+str(q.get('coverage_pct')))
print("QUEUE_MISSING="+str(q.get('missing_count')))
PY

echo "PUBLIC_V32=$(systemctl is-active "$PUBLIC")"
echo "STABLE_SHADOW=$(systemctl is-active "$SHADOW")"
echo "PUBLIC_RTMP=READY"
echo "RESULTADO=RADIOPRINCIPAL_NS1_STABLE_NO_SKIP"
