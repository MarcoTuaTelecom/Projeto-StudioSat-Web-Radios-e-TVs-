#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V5-SERVER-ONLY-${TS}"
mkdir -p "$BK"

V32='studiosat-radioprincipal-v32-core.service'
V31ICE='studiosat-radioprincipal-v31-icecast.service'
OLD_SHADOW='studiosat-radioprincipal-shadow-ns1.service'
V5='studiosat-radioprincipal-v5.service'
RBSYNC='studiosat-radioboss-sync.service'
MEDIATRANSFER='studiosat-media-transfer.service'

BIN='/opt/studiosat/radio-principal-v5/radioprincipal-control-playout-v5.py'
UNIT="/etc/systemd/system/$V5"
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
BASE='/var/lib/studiosat/radio-principal-v5'

MUTATED=0

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
  systemctl disable --now "$V5" 2>/dev/null || true
  systemctl enable "$V32" 2>/dev/null || true
  systemctl restart "$V32" 2>/dev/null || true
  say "ROLLBACK_APPLIED"
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " RADIO PRINCIPAL V5 - SERVER ONLY / RADIOBOSS CONTROL CHANNEL"
say "=============================================================="
say "BACKUP=$BK"

say "1/10 KEEP CURRENT PUBLIC AUDIO UNTIL V5 IS READY"
systemctl is-active --quiet "$V32" || fail "V32_CURRENT_PUBLIC_NOT_ACTIVE"
probe_rtmp rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"
say "CURRENT_PUBLIC=READY"

say "2/10 REQUIRE EXISTING SECURE RADIOBOSS CONTROL CHANNEL"
systemctl is-active --quiet "$RBSYNC" || systemctl start "$RBSYNC"
systemctl is-active --quiet "$MEDIATRANSFER" || systemctl start "$MEDIATRANSFER"

python3 - "$SYNC" <<'PY'
import json,sys,time
from pathlib import Path
d=Path(sys.argv[1])
for n in ("playlist.json","playback.json","librarymanifest.json"):
    p=d/n
    if not p.is_file():
        print("FATAL=MISSING_"+n.upper().replace(".","_"))
        raise SystemExit(2)

p=d/"playback.json"
x=json.load(open(p,encoding="utf-8-sig"))
age=time.time()-p.stat().st_mtime
payload=x.get("payload") or {}
if isinstance(payload,dict) and isinstance(payload.get("data"),dict):
    payload=payload["data"]
cur=payload.get("current") or {}
fn=cur.get("FILENAME") or cur.get("filename") or ""
print(f"PLAYBACK_AGE_SEC={age:.2f}")
print("PLAYBACK_STATE="+str(payload.get("state")))
print("PLAYLISTPOS="+str(payload.get("playlistpos")))
print("POS_MS="+str(payload.get("pos_ms")))
print("CURRENT_FILENAME="+str(fn))
if age>20 or not fn:
    print("FATAL=RADIOBOSS_CONTROL_NOT_FRESH")
    raise SystemExit(3)
print("RADIOBOSS_CONTROL_CHANNEL=FRESH")
PY

say "3/10 INSTALL TESTED V5 ENGINE"
install -d -m 0755 /opt/studiosat/radio-principal-v5
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v5/radioprincipal-control-playout-v5.py' \
-o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
"$BIN" --selftest | tee "$BK/selftest.txt"
grep -q '^SELFTEST=PASS$' "$BK/selftest.txt" || fail "SELFTEST_FAILED"
say "ENGINE_TESTS=PASS"

say "4/10 RESOLVE REAL RADIOBOSS QUEUE AGAINST NS1 MEDIA"
set +e
STUDIOSAT_V5_CONTROL_FRESH_SEC=20 "$BIN" --check | tee "$BK/real-check.txt"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" -eq 0 ] || fail "CURRENT_OR_NEXT_NOT_RESOLVED"

CURRENT_READY="$(awk -F= '/^CURRENT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
NEXT_READY="$(awk -F= '/^NEXT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
COVERAGE="$(awk -F= '/^COVERAGE_PCT=/{print $2}' "$BK/real-check.txt" | tail -1)"
DBALIASES="$(awk -F= '/^DB_ALIASES=/{print $2}' "$BK/real-check.txt" | tail -1)"

echo "CURRENT_READY=$CURRENT_READY"
echo "NEXT_READY=$NEXT_READY"
echo "COVERAGE_PCT=$COVERAGE"
echo "DB_ALIASES=$DBALIASES"

[ "$CURRENT_READY" = YES ] || fail "CURRENT_NOT_RESOLVED"
[ "$NEXT_READY" = YES ] || fail "NEXT_NOT_RESOLVED"

CURRENT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v5/effective-queue.json'))
print((q.get('current') or {}).get('local_path') or '')
PY
)"
NEXT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v5/effective-queue.json'))
print((q.get('next') or {}).get('local_path') or '')
PY
)"

[ -n "$CURRENT_LOCAL" ] || fail "CURRENT_LOCAL_EMPTY"
[ -n "$NEXT_LOCAL" ] || fail "NEXT_LOCAL_EMPTY"

timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$CURRENT_LOCAL" 2>/dev/null | grep -q . || fail "CURRENT_LOCAL_NOT_DECODABLE"
timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$NEXT_LOCAL" 2>/dev/null | grep -q . || fail "NEXT_LOCAL_NOT_DECODABLE"

echo "CURRENT_LOCAL=$CURRENT_LOCAL"
echo "NEXT_LOCAL=$NEXT_LOCAL"
say "REAL_MEDIA_PREFLIGHT=PASS"

say "5/10 INSTALL V5 SYSTEMD SERVICE"
cp -a "$UNIT" "$BK/v5.service.before" 2>/dev/null || true

cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V5 server-only RadioBOSS control playout
After=network-online.target tps-mediamtx.service $RBSYNC $MEDIATRANSFER
Requires=tps-mediamtx.service $RBSYNC
Wants=$MEDIATRANSFER
StartLimitIntervalSec=0
Conflicts=$V32

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_V5_CONTROL_FRESH_SEC=20
Environment=STUDIOSAT_V5_RTMP=rtmp://127.0.0.1:1935/radioprincipal
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

systemd-analyze verify "$UNIT"
systemctl daemon-reload

say "6/10 CUTOVER PUBLIC PUBLISHER ONLY"
systemctl disable --now "$V32" 2>/dev/null || true
MUTATED=1

if ! systemctl enable --now "$V5"; then
  fail "V5_START_FAILED"
fi

say "7/10 REQUIRE PUBLIC RTMP FROM V5"
PUB=0
for i in $(seq 1 25); do
  if systemctl is-active --quiet "$V5" &&
     probe_rtmp rtmp://127.0.0.1:1935/radioprincipal; then
    PUB=1
    say "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$PUB" -eq 1 ] || { journalctl -u "$V5" -n 120 --no-pager || true; fail "V5_PUBLIC_RTMP_NOT_READY"; }

say "8/10 REQUIRE HOT SYNC TO RADIOBOSS CURRENT"
SYNC_OK=0
for i in $(seq 1 20); do
  if python3 - <<'PY'
import json,os,time,sys
state='/var/lib/studiosat/radio-principal-v5/state.json'
queue='/var/lib/studiosat/radio-principal-v5/effective-queue.json'
pb='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'
try:
    s=json.load(open(state))
    q=json.load(open(queue))
    age=time.time()-os.stat(pb).st_mtime
    cur=q.get('current') or {}
    st=s.get('current') or {}
    print("MODE="+str(s.get('mode')))
    print("PLAYBACK_AGE_SEC="+f"{age:.2f}")
    print("QUEUE_CURRENT_INDEX="+str(q.get('current_index')))
    print("PLAYOUT_CURRENT_INDEX="+str(s.get('current_index')))
    print("CURRENT_LOCAL="+str(cur.get('local_path')))
    print("PLAYOUT_LOCAL="+str(st.get('local_path')))
    print("AUDIO_AGE_SEC="+str(s.get('last_audio_age_sec')))
    ok=(
        s.get('mode')=='hot-sync'
        and age<=20
        and q.get('current_index') is not None
        and s.get('current_index')==q.get('current_index')
        and bool(cur.get('local_path'))
        and cur.get('local_path')==st.get('local_path')
        and isinstance(s.get('last_audio_age_sec'),(int,float))
        and s.get('last_audio_age_sec')<1.5
    )
    raise SystemExit(0 if ok else 1)
except Exception as e:
    print("SYNC_CHECK_ERROR="+repr(e))
    raise SystemExit(1)
PY
  then
    SYNC_OK=1
    break
  fi
  sleep 1
done
[ "$SYNC_OK" -eq 1 ] || fail "V5_HOT_SYNC_NOT_CONFIRMED"

say "9/10 REQUIRE HLS PUBLIC"
HLS=0
for i in $(seq 1 20); do
  if curl -LfsS --max-time 8 \
      https://radio.studiosatweb.com.br/radioprincipal/index.m3u8 2>/dev/null |
      grep -q '^#EXTM3U'; then
    HLS=1
    say "PUBLIC_HLS=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$HLS" -eq 1 ] || fail "PUBLIC_HLS_NOT_READY"

say "10/10 REMOVE OLD AUDIO-TUNNEL DEPENDENCIES ON NS1"
systemctl disable --now "$V31ICE" 2>/dev/null || true
systemctl disable --now "$OLD_SHADOW" 2>/dev/null || true
for u in \
  studiosat-radioprincipal-selector.service \
  studiosat-radioprincipal-emergency-direct.service \
  studiosat-radioprincipal-v3-core.service \
  studiosat-radioprincipal-v3-icecast.service \
  studiosat-radioprincipal-v31-core.service \
  studiosat-radioprincipal-v32-hls-warmer.service \
  studiosat-radioprincipal-v32-health.service
do
  systemctl disable --now "$u" 2>/dev/null || true
done

systemctl enable "$V5" "$RBSYNC" "$MEDIATRANSFER" >/dev/null 2>&1 || true

python3 - <<'PY'
import json,os,time
idx=json.load(open('/var/lib/studiosat/radio-principal-v5/library-index.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-v5/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v5/state.json'))
pb='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'
print("LIBRARY_FILES="+str(idx.get('count')))
print("DB_ALIASES="+str(idx.get('db_aliases')))
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
print("PLAYOUT_MODE="+str(s.get('mode')))
print("PLAYOUT_CURRENT_INDEX="+str(s.get('current_index')))
print("PLAYOUT_AUDIO_AGE="+str(s.get('last_audio_age_sec')))
PY

echo "PUBLIC_V5=$(systemctl is-active "$V5")"
echo "RADIOBOSS_SYNC=$(systemctl is-active "$RBSYNC")"
echo "MEDIA_TRANSFER=$(systemctl is-active "$MEDIATRANSFER")"
echo "AUDIO_ICECAST=$(systemctl is-active "$V31ICE" 2>/dev/null || true)"
echo "OLD_SHADOW=$(systemctl is-active "$OLD_SHADOW" 2>/dev/null || true)"
echo "PUBLIC_RTMP=READY"
echo "PUBLIC_HLS=READY"
echo "RADIOBOSS_AUDIO_TUNNEL_REQUIRED=NO"
echo "RADIOBOSS_CONTROL_CHANNEL=HTTPS_EXISTING"
echo "RESULTADO=RADIOPRINCIPAL_V5_SERVER_ONLY_SYNCHRONIZED"
MUTATED=0
