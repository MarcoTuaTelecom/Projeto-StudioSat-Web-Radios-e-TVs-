#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/LIBSYNC-V42-${TS}"
mkdir -p "$BK"

V32='studiosat-radioprincipal-v32-core.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
BIN='/opt/studiosat/radio-principal-v42/radioprincipal-library-shadow-v4.2.py'
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
BASE='/var/lib/studiosat/radio-principal-v42'
MUTATED=0
UNIT_PATH=''

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe_rtmp(){
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

rollback(){
  [ "$MUTATED" -eq 1 ] || return 0
  say "ROLLBACK_START"
  if [ -n "$UNIT_PATH" ] && [ -f "$BK/shadow.service.before" ]; then
    cp -a "$BK/shadow.service.before" "$UNIT_PATH"
    systemctl daemon-reload
    systemctl restart "$SHADOW" || true
  fi
  say "ROLLBACK_APPLIED"
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " RADIO PRINCIPAL V4.2 - TESTED LIBRARY SYNC + HOT SHADOW"
say "=============================================================="
say "BACKUP=$BK"

say "1/9 REQUIRE PUBLIC RADIOBOSS LIVE + VALID CONTROL"
systemctl is-active --quiet "$V32" || systemctl start "$V32"

probe_rtmp http://127.0.0.1:18005/radioprincipal-rb || fail "RADIOBOSS_ICECAST_AUDIO_NOT_READY"
probe_rtmp rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"

LIVE_OK=0
for i in $(seq 1 20); do
  if python3 - <<'PY'
import json,time
p='/run/studiosat/radioprincipal-v32-state.json'
a=json.load(open(p))
b1=int(a.get('live_bytes') or 0)
time.sleep(1)
b=json.load(open(p))
b2=int(b.get('live_bytes') or 0)
print("PUBLIC_SOURCE="+str(b.get('selected_source')))
print("LIVE_BYTES_DELTA="+str(b2-b1))
print("LIVE_AGE_SEC="+str(b.get('live_age_sec')))
ok=(b.get('selected_source')=='live' and b2>b1 and isinstance(b.get('live_age_sec'),(int,float)) and b.get('live_age_sec')<1)
raise SystemExit(0 if ok else 1)
PY
  then
    LIVE_OK=1
    break
  fi
  sleep 1
done
[ "$LIVE_OK" -eq 1 ] || fail "RADIOBOSS_NOT_SELECTED_LIVE"
say "PUBLIC_RADIOBOSS_LIVE=CONFIRMED"

python3 - "$SYNC" <<'PY'
import json,sys,time
from pathlib import Path
d=Path(sys.argv[1])

# Playlist/library manifest are versioned snapshots. Old mtime is not a failure
# when their content/revision has not changed.
for n in ("playlist.json","librarymanifest.json"):
    p=d/n
    if not p.is_file():
        print("FATAL=MISSING_"+n.upper().replace(".","_"))
        raise SystemExit(2)
    x=json.load(open(p,encoding='utf-8-sig'))
    if x.get('station_id') not in (None,'radioprincipal'):
        print("FATAL=WRONG_STATION_"+n.upper().replace(".","_"))
        raise SystemExit(3)
    print(n.upper().replace(".","_")+"_REVISION="+str(x.get('revision')))
    print(n.upper().replace(".","_")+"_RECEIVED_AT="+str(x.get('received_at_utc')))

# Playback is dynamic and must be fresh.
p=d/'playback.json'
if not p.is_file():
    print("FATAL=MISSING_PLAYBACK_JSON")
    raise SystemExit(4)
x=json.load(open(p,encoding='utf-8-sig'))
age=time.time()-p.stat().st_mtime
payload=x.get('payload') or {}
if isinstance(payload,dict) and isinstance(payload.get('data'),dict):
    payload=payload['data']
cur=payload.get('current') or {}
fn=cur.get('FILENAME') or cur.get('filename') or ''
print(f"PLAYBACK_AGE_SEC={age:.2f}")
print("PLAYBACK_STATE="+str(payload.get('state')))
print("PLAYLISTPOS="+str(payload.get('playlistpos')))
print("POS_MS="+str(payload.get('pos_ms')))
print("CURRENT_FILENAME="+str(fn))
if age>30 or not fn:
    print("FATAL=PLAYBACK_CONTROL_STALE_OR_EMPTY")
    raise SystemExit(5)

print("RADIOBOSS_CONTROL=VALID")
PY

say "2/9 INSTALL EXACT ENGINE REVISION"
install -d -m 0755 /opt/studiosat/radio-principal-v42
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v4/radioprincipal-library-shadow-v4.2.py' \
-o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
echo "PYTHON_COMPILE=PASS"

say "3/9 RUN BUILT-IN SELFTEST BEFORE PRODUCTION DATA"
"$BIN" --selftest | tee "$BK/selftest.txt"
grep -q '^SELFTEST=PASS$' "$BK/selftest.txt" || fail "ENGINE_SELFTEST_FAILED"

say "4/9 BUILD REAL INDEX + EFFECTIVE QUEUE"
set +e
"$BIN" --check | tee "$BK/check.txt"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" -eq 0 ] || fail "CURRENT_OR_NEXT_NOT_RESOLVED"

CURRENT_READY="$(awk -F= '/^CURRENT_READY=/{print $2}' "$BK/check.txt" | tail -1)"
NEXT_READY="$(awk -F= '/^NEXT_READY=/{print $2}' "$BK/check.txt" | tail -1)"
COVERAGE="$(awk -F= '/^COVERAGE_PCT=/{print $2}' "$BK/check.txt" | tail -1)"
LIBFILES="$(awk -F= '/^LIBRARY_FILES=/{print $2}' "$BK/check.txt" | tail -1)"
ALIASES="$(awk -F= '/^SYMLINK_ALIASES=/{print $2}' "$BK/check.txt" | tail -1)"

echo "LIBRARY_FILES=$LIBFILES"
echo "SYMLINK_ALIASES=$ALIASES"
echo "CURRENT_READY=$CURRENT_READY"
echo "NEXT_READY=$NEXT_READY"
echo "COVERAGE_PCT=$COVERAGE"

[ "$CURRENT_READY" = "YES" ] || fail "CURRENT_NOT_RESOLVED"
[ "$NEXT_READY" = "YES" ] || fail "NEXT_NOT_RESOLVED"

python3 - "$COVERAGE" <<'PY'
import sys
v=float(sys.argv[1] or 0)
print(f"COVERAGE_GATE={v}")
if v < 90:
    raise SystemExit(1)
PY

CURRENT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v42/effective-queue.json'))
print((q.get('current') or {}).get('local_path') or '')
PY
)"
NEXT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v42/effective-queue.json'))
print((q.get('next') or {}).get('local_path') or '')
PY
)"

[ -n "$CURRENT_LOCAL" ] || fail "CURRENT_LOCAL_EMPTY"
[ -n "$NEXT_LOCAL" ] || fail "NEXT_LOCAL_EMPTY"

timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$CURRENT_LOCAL" 2>/dev/null | grep -q . || fail "CURRENT_LOCAL_NOT_DECODABLE"
timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$NEXT_LOCAL" 2>/dev/null | grep -q . || fail "NEXT_LOCAL_NOT_DECODABLE"

echo "CURRENT_AUDIO=DECODABLE"
echo "NEXT_AUDIO=DECODABLE"
say "REAL_DATA_PREFLIGHT=PASS"

say "5/9 BACKUP CANONICAL SHADOW UNIT"
UNIT_PATH="$(systemctl show -p FragmentPath --value "$SHADOW")"
[ -n "$UNIT_PATH" ] && [ -f "$UNIT_PATH" ] || fail "SHADOW_FRAGMENT_NOT_FOUND"
cp -a "$UNIT_PATH" "$BK/shadow.service.before"
systemctl cat "$SHADOW" >"$BK/shadow.unit.before.txt" 2>&1 || true

say "6/9 REPLACE ENGINE IN SAME CANONICAL SHADOW SERVICE"
cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Studio Sat Radio Principal V4.2 synchronized RadioBOSS library shadow
After=network-online.target tps-mediamtx.service
Requires=tps-mediamtx.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_V42_CONTROL_FRESH_SEC=30
ExecStart=/usr/bin/python3 $BIN
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/run/studiosat $BASE

[Install]
WantedBy=multi-user.target
EOF

systemd-analyze verify "$UNIT_PATH"
systemctl daemon-reload
MUTATED=1
systemctl restart "$SHADOW"

say "7/9 REQUIRE NEW SYNCHRONIZED SHADOW RTMP"
READY=0
for i in $(seq 1 30); do
  if systemctl is-active --quiet "$SHADOW" &&
     probe_rtmp rtmp://127.0.0.1:1935/radioprincipal-ns1; then
    READY=1
    say "SHADOW_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$READY" -eq 1 ] || fail "SYNCHRONIZED_SHADOW_NOT_READY"

say "8/9 REQUIRE HOT SYNC TO CURRENT RADIOBOSS ITEM"
SYNC_OK=0
for i in $(seq 1 20); do
  if python3 - <<'PY'
import json,os,sys,time
q=json.load(open('/var/lib/studiosat/radio-principal-v42/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v42/state.json'))
pb='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'
age=time.time()-os.stat(pb).st_mtime
cur=q.get('current') or {}
stcur=s.get('current') or {}
print("SYNC_MODE="+str(s.get('mode')))
print("PLAYBACK_AGE_SEC="+f"{age:.2f}")
print("QUEUE_CURRENT_INDEX="+str(q.get('current_index')))
print("SHADOW_CURRENT_INDEX="+str(s.get('current_index')))
print("CURRENT_SOURCE="+str(cur.get('source_path')))
print("CURRENT_LOCAL="+str(cur.get('local_path')))
print("SHADOW_LOCAL="+str(stcur.get('local_path')))
print("SHADOW_AUDIO_AGE="+str(s.get('last_audio_age_sec')))
ok=(
    s.get('mode')=='hot-sync'
    and age<=30
    and q.get('current_index') is not None
    and s.get('current_index')==q.get('current_index')
    and bool(cur.get('local_path'))
    and cur.get('local_path')==stcur.get('local_path')
    and isinstance(s.get('last_audio_age_sec'),(int,float))
    and s.get('last_audio_age_sec')<1.5
)
sys.exit(0 if ok else 1)
PY
  then
    SYNC_OK=1
    break
  fi
  sleep 1
done
[ "$SYNC_OK" -eq 1 ] || fail "HOT_SYNC_NOT_CONFIRMED"

say "9/9 FINAL ACCEPTANCE"
systemctl is-active --quiet "$V32" || fail "PUBLIC_V32_STOPPED"
probe_rtmp rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_LOST"
probe_rtmp rtmp://127.0.0.1:1935/radioprincipal-ns1 || fail "SHADOW_RTMP_LOST"

python3 - <<'PY'
import json,os,time
idx=json.load(open('/var/lib/studiosat/radio-principal-v42/library-index.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-v42/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v42/state.json'))
pb='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'
print("LIBRARY_INDEX_FILES="+str(idx.get('count')))
print("SYMLINK_ALIASES="+str(idx.get('symlink_aliases')))
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
print("PLAYBACK_AGE_SEC="+f"{time.time()-os.stat(pb).st_mtime:.2f}")
print("SHADOW_MODE="+str(s.get('mode')))
print("SHADOW_CURRENT_INDEX="+str(s.get('current_index')))
print("SHADOW_AUDIO_AGE="+str(s.get('last_audio_age_sec')))
PY

echo "PUBLIC_V32=active"
echo "CANONICAL_SHADOW_V42=active"\necho "RADIOBOSS_LIVE=ACTIVE"
echo "PUBLIC_RTMP=READY"
echo "NS1_SHADOW_RTMP=READY"
echo "RADIOBOSS_CONTROL=FRESH"
echo "RADIOBOSS_LIBRARY_SYNC=ACTIVE"
echo "RADIOBOSS_CURRENT_POSITION_SYNC=ACTIVE"
echo "RESULTADO=RADIOPRINCIPAL_V42_LIVE_AND_SYNCHRONIZED"
MUTATED=0
