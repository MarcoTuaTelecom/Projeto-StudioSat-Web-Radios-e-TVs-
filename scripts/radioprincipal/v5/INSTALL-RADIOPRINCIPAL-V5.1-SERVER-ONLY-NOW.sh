#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V51-SERVER-ONLY-${TS}"
mkdir -p "$BK"

V32='studiosat-radioprincipal-v32-core.service'
ICE='studiosat-radioprincipal-v31-icecast.service'
OLD_SHADOW='studiosat-radioprincipal-shadow-ns1.service'
V51='studiosat-radioprincipal-v51.service'
RBSYNC='studiosat-radioboss-sync.service'
BRIDGE='studiosat-radioprincipal-v8-control-bridge.service'
MEDIATRANSFER='studiosat-media-transfer.service'

BIN='/opt/studiosat/radio-principal-v51/radioprincipal-control-playout-v5.1.py'
UNIT="/etc/systemd/system/$V51"
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
CONTROL='/run/studiosat-radioprincipal-v8-control/playback.json'
BASE='/var/lib/studiosat/radio-principal-v51'

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
  systemctl disable --now "$V51" 2>/dev/null || true
  systemctl enable "$V32" 2>/dev/null || true
  systemctl restart "$V32" 2>/dev/null || true
  say "ROLLBACK_APPLIED"
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " RADIO PRINCIPAL V5.1 - EXISTING CONTROL CHANNEL / SERVER ONLY"
say "=============================================================="
say "BACKUP=$BK"

say "1/10 KEEP CURRENT PUBLIC AUDIO"
systemctl is-active --quiet "$V32" || fail "V32_CURRENT_PUBLIC_NOT_ACTIVE"
probe_rtmp rtmp://127.0.0.1:1935/radioprincipal || fail "PUBLIC_RTMP_NOT_READY"
say "CURRENT_PUBLIC=READY"

say "2/10 REQUIRE EXISTING HTTPS CONTROL STACK"
systemctl is-active --quiet "$RBSYNC" || systemctl start "$RBSYNC"
systemctl is-active --quiet "$BRIDGE" || systemctl start "$BRIDGE"
systemctl is-active --quiet "$MEDIATRANSFER" || systemctl start "$MEDIATRANSFER"

control_fresh(){
python3 - "$CONTROL" <<'PY'
import json,sys,time,os
from datetime import datetime,timezone
p=sys.argv[1]
if not os.path.isfile(p):
    print("CONTROL_FILE=ABSENT")
    raise SystemExit(2)
x=json.load(open(p,encoding='utf-8-sig'))
payload=x.get('payload') or {}
data=payload.get('data') if isinstance(payload,dict) else None
if not isinstance(data,dict):
    data=payload if isinstance(payload,dict) else {}
cur=data.get('current') or {}
fn=cur.get('FILENAME') or cur.get('filename') or ''
def parse(v):
    if not v:return None
    s=str(v)
    if s.endswith('Z'): s=s[:-1]+'+00:00'
    try:
        d=datetime.fromisoformat(s)
        if d.tzinfo is None:d=d.replace(tzinfo=timezone.utc)
        return d.astimezone(timezone.utc).timestamp()
    except Exception:return None
ts=parse(payload.get('collected_at_utc')) or parse(x.get('received_at_utc'))
age=(time.time()-ts) if ts else (time.time()-os.stat(p).st_mtime)
print(f"CONTROL_AGE_SEC={age:.2f}")
print("CONTROL_STATE="+str(data.get('state')))
print("CONTROL_PLAYLISTPOS="+str(data.get('playlistpos')))
print("CONTROL_POS_MS="+str(data.get('pos_ms')))
print("CONTROL_CURRENT="+str(fn))
print("CONTROL_NEXT="+str((data.get('next') or {}).get('FILENAME') or ''))
ok=(age<=30 and data.get('state') in ('play','playing',None) and bool(fn))
raise SystemExit(0 if ok else 1)
PY
}

if ! control_fresh | tee "$BK/control-before.txt"; then
  say "CONTROL_BRIDGE_REFRESH=RESTART_ONCE"
  systemctl restart "$BRIDGE"
  OK=0
  for i in $(seq 1 35); do
    if control_fresh >"$BK/control-after.txt" 2>&1; then
      cat "$BK/control-after.txt"
      OK=1
      break
    fi
    sleep 1
  done
  [ "$OK" -eq 1 ] || { cat "$BK/control-after.txt" 2>/dev/null || true; fail "EXISTING_CONTROL_CHANNEL_NOT_FRESH"; }
fi
say "EXISTING_CONTROL_CHANNEL=FRESH"

say "3/10 VALIDATE STATIC PLAYLIST + LIBRARY SNAPSHOTS"
python3 - "$SYNC" <<'PY'
import json,sys
from pathlib import Path
d=Path(sys.argv[1])
for n in ('playlist.json','librarymanifest.json'):
    p=d/n
    if not p.is_file():
        print("FATAL=MISSING_"+n.upper().replace('.','_'))
        raise SystemExit(2)
    x=json.load(open(p,encoding='utf-8-sig'))
    print(n.upper().replace('.','_')+"_REVISION="+str(x.get('revision')))
    print(n.upper().replace('.','_')+"_RECEIVED_AT="+str(x.get('received_at_utc')))
print("STATIC_SNAPSHOTS=VALID")
PY

say "4/10 INSTALL PRE-TESTED V5.1 ENGINE"
install -d -m 0755 /opt/studiosat/radio-principal-v51
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v5/radioprincipal-control-playout-v5.1.py' \
-o "$BIN"
chmod 0755 "$BIN"
python3 -m py_compile "$BIN"
"$BIN" --selftest | tee "$BK/selftest.txt"
grep -q '^SELFTEST=PASS$' "$BK/selftest.txt" || fail "SELFTEST_FAILED"
say "ENGINE_TESTS=PASS"

say "5/10 RESOLVE REAL RADIOBOSS CURRENT/NEXT FROM NS1 MEDIA"
set +e
STUDIOSAT_V51_CONTROL_PLAYBACK="$CONTROL" \
STUDIOSAT_V51_CONTROL_FRESH_SEC=30 \
"$BIN" --check | tee "$BK/real-check.txt"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" -eq 0 ] || fail "CURRENT_OR_NEXT_NOT_RESOLVED"

CURRENT_READY="$(awk -F= '/^CURRENT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
NEXT_READY="$(awk -F= '/^NEXT_READY=/{print $2}' "$BK/real-check.txt" | tail -1)"
COVERAGE="$(awk -F= '/^COVERAGE_PCT=/{print $2}' "$BK/real-check.txt" | tail -1)"
DBALIASES="$(awk -F= '/^DB_ALIASES=/{print $2}' "$BK/real-check.txt" | tail -1)"

[ "$CURRENT_READY" = YES ] || fail "CURRENT_NOT_RESOLVED"
[ "$NEXT_READY" = YES ] || fail "NEXT_NOT_RESOLVED"

CURRENT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v51/effective-queue.json'))
print((q.get('current') or {}).get('local_path') or '')
PY
)"
NEXT_LOCAL="$(python3 - <<'PY'
import json
q=json.load(open('/var/lib/studiosat/radio-principal-v51/effective-queue.json'))
print((q.get('next') or {}).get('local_path') or '')
PY
)"

[ -n "$CURRENT_LOCAL" ] || fail "CURRENT_LOCAL_EMPTY"
[ -n "$NEXT_LOCAL" ] || fail "NEXT_LOCAL_EMPTY"

timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$CURRENT_LOCAL" 2>/dev/null | grep -q . || fail "CURRENT_LOCAL_NOT_DECODABLE"
timeout 8 ffprobe -v error -show_entries stream=codec_name \
  -of csv=p=0 "$NEXT_LOCAL" 2>/dev/null | grep -q . || fail "NEXT_LOCAL_NOT_DECODABLE"

python3 - <<'PY'
import json,sys
q=json.load(open('/var/lib/studiosat/radio-principal-v51/effective-queue.json'))
cur=q.get('current_index')
qq=q.get('queue') or []
bad=[]
good=0
if cur is not None:
    for x in qq[cur:cur+12]:
        if x.get('virtual'):
            continue
        if x.get('available'):
            good+=1
        else:
            bad.append(x.get('source_path'))
print("UPCOMING_MEDIA_READY="+str(good))
print("UPCOMING_MEDIA_MISSING="+str(len(bad)))
for x in bad[:10]:
    print("UPCOMING_MISSING="+str(x))
if good < 3:
    raise SystemExit(1)
PY

echo "QUEUE_COVERAGE_PCT=$COVERAGE"
echo "DB_ALIASES=$DBALIASES"
echo "CURRENT_LOCAL=$CURRENT_LOCAL"
echo "NEXT_LOCAL=$NEXT_LOCAL"
say "REAL_MEDIA_PREFLIGHT=PASS"

say "6/10 INSTALL V5.1 SERVICE"
cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V5.1 server-only synchronized playout
After=network-online.target tps-mediamtx.service $RBSYNC $BRIDGE $MEDIATRANSFER
Requires=tps-mediamtx.service $RBSYNC $BRIDGE
Wants=$MEDIATRANSFER
StartLimitIntervalSec=0
Conflicts=$V32

[Service]
Type=simple
User=root
Group=root
Environment=STUDIOSAT_V51_CONTROL_FRESH_SEC=30
Environment=STUDIOSAT_V51_CONTROL_PLAYBACK=$CONTROL
Environment=STUDIOSAT_V51_RTMP=rtmp://127.0.0.1:1935/radioprincipal
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
ReadWritePaths=/run/studiosat $BASE

[Install]
WantedBy=multi-user.target
EOF

systemd-analyze verify "$UNIT"
systemctl daemon-reload

say "7/10 CUTOVER PUBLIC PUBLISHER"
systemctl disable --now "$V32" 2>/dev/null || true
MUTATED=1
systemctl enable --now "$V51"

PUB=0
for i in $(seq 1 25); do
  if systemctl is-active --quiet "$V51" &&
     probe_rtmp rtmp://127.0.0.1:1935/radioprincipal; then
    PUB=1
    say "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$PUB" -eq 1 ] || { journalctl -u "$V51" -n 120 --no-pager || true; fail "V51_PUBLIC_RTMP_NOT_READY"; }

say "8/10 REQUIRE HOT SYNC USING EXISTING CONTROL BRIDGE"
SYNC_OK=0
for i in $(seq 1 25); do
  if python3 - <<'PY'
import json,sys
s=json.load(open('/var/lib/studiosat/radio-principal-v51/state.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-v51/effective-queue.json'))
cur=q.get('current') or {}
st=s.get('current') or {}
print("PLAYOUT_MODE="+str(s.get('mode')))
print("CONTROL_SOURCE="+str(s.get('control_source')))
print("CONTROL_AGE_SEC="+str(s.get('control_age_sec')))
print("QUEUE_CURRENT_INDEX="+str(q.get('current_index')))
print("PLAYOUT_CURRENT_INDEX="+str(s.get('current_index')))
print("CURRENT_LOCAL="+str(cur.get('local_path')))
print("PLAYOUT_LOCAL="+str(st.get('local_path')))
print("AUDIO_AGE_SEC="+str(s.get('last_audio_age_sec')))
ok=(
    s.get('mode')=='hot-sync'
    and str(s.get('control_source','')).endswith('/run/studiosat-radioprincipal-v8-control/playback.json')
    and isinstance(s.get('control_age_sec'),(int,float))
    and s.get('control_age_sec')<=30
    and q.get('current_index') is not None
    and s.get('current_index')==q.get('current_index')
    and bool(cur.get('local_path'))
    and cur.get('local_path')==st.get('local_path')
    and isinstance(s.get('last_audio_age_sec'),(int,float))
    and s.get('last_audio_age_sec')<1.5
)
raise SystemExit(0 if ok else 1)
PY
  then
    SYNC_OK=1
    break
  fi
  sleep 1
done
[ "$SYNC_OK" -eq 1 ] || fail "V51_HOT_SYNC_NOT_CONFIRMED"

say "9/10 REQUIRE PUBLIC HTTPS HLS"
HLS=0
for i in $(seq 1 25); do
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

say "10/10 REMOVE AUDIO-TUNNEL PATH FROM NS1"
systemctl disable --now "$ICE" 2>/dev/null || true
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

# Disable the dedicated RadioBOSS SSH forwarding account server-side.
# This requires no change on the RadioBOSS PC; future tunnel reconnects are rejected by NS1.
if id studiosat-rb-tunnel >/dev/null 2>&1; then
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-studiosat-disable-rb-tunnel.conf <<'EOF'
DenyUsers studiosat-rb-tunnel
EOF
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  pkill -u studiosat-rb-tunnel 2>/dev/null || true
  echo "RADIOBOSS_SSH_TUNNEL_ACCOUNT=DISABLED_SERVER_SIDE"
fi

systemctl enable "$V51" "$RBSYNC" "$BRIDGE" "$MEDIATRANSFER" >/dev/null 2>&1 || true

python3 - <<'PY'
import json
idx=json.load(open('/var/lib/studiosat/radio-principal-v51/library-index.json'))
q=json.load(open('/var/lib/studiosat/radio-principal-v51/effective-queue.json'))
s=json.load(open('/var/lib/studiosat/radio-principal-v51/state.json'))
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
print("CONTROL_SOURCE="+str(s.get('control_source')))
print("CONTROL_AGE_SEC="+str(s.get('control_age_sec')))
print("PLAYOUT_MODE="+str(s.get('mode')))
print("PLAYOUT_AUDIO_AGE="+str(s.get('last_audio_age_sec')))
PY

echo "PUBLIC_V51=$(systemctl is-active "$V51")"
echo "RADIOBOSS_SYNC=$(systemctl is-active "$RBSYNC")"
echo "CONTROL_BRIDGE=$(systemctl is-active "$BRIDGE")"
echo "MEDIA_TRANSFER=$(systemctl is-active "$MEDIATRANSFER")"
echo "AUDIO_ICECAST=$(systemctl is-active "$ICE" 2>/dev/null || true)"
echo "OLD_SHADOW=$(systemctl is-active "$OLD_SHADOW" 2>/dev/null || true)"
echo "PUBLIC_RTMP=READY"
echo "PUBLIC_HLS=READY"
echo "RADIOBOSS_AUDIO_TUNNEL_REQUIRED=NO"
echo "RADIOBOSS_CONTROL_CHANNEL=EXISTING_HTTPS_V8_BRIDGE"
echo "RESULTADO=RADIOPRINCIPAL_V51_SERVER_ONLY_LIVE"
MUTATED=0
