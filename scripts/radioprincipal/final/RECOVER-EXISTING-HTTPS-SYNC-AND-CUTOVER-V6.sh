#!/usr/bin/env bash
set -Eeuo pipefail

SYNCROOT=/var/lib/studiosat/radio-v2/radioboss-sync
STATION="$SYNCROOT/radioprincipal"
CURRENT="$STATION/current"
CONTROL=/run/studiosat-radioprincipal-v8-control/playback.json
V32=studiosat-radioprincipal-v32-core.service
RBSYNC=studiosat-radioboss-sync.service
BRIDGE=studiosat-radioprincipal-v8-control-bridge.service
V6INSTALL=/root/INSTALL-RADIOPRINCIPAL-V6-PRODUCTION-NOW.sh
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/HTTPS-SYNC-RECOVERY-$TS"
mkdir -p "$BK"

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

age_check(){
python3 - "$CURRENT/playback.json" "$CONTROL" <<'PY'
import json,os,sys,time
from datetime import datetime,timezone
def parse_iso(v):
    if not v:return None
    s=str(v)
    if s.endswith('Z'): s=s[:-1]+'+00:00'
    try:
        d=datetime.fromisoformat(s)
        if d.tzinfo is None:d=d.replace(tzinfo=timezone.utc)
        return d.timestamp()
    except Exception:return None
def one(path):
    if not os.path.isfile(path):
        return {"path":path,"age":999999,"current":"","idx":None,"pos":None}
    x=json.load(open(path,encoding='utf-8-sig'))
    p=x.get('payload') or {}
    d=p.get('data') if isinstance(p,dict) and isinstance(p.get('data'),dict) else p
    cur=(d.get('current') or {}) if isinstance(d,dict) else {}
    ts=parse_iso(x.get('received_at_utc'))
    if isinstance(p,dict): ts=ts or parse_iso(p.get('collected_at_utc'))
    age=time.time()-ts if ts else time.time()-os.stat(path).st_mtime
    return {"path":path,"age":max(0,age),"current":cur.get('FILENAME') or cur.get('filename') or '',
            "idx":d.get('playlistpos') if isinstance(d,dict) else None,
            "pos":d.get('pos_ms') if isinstance(d,dict) else None}
vals=[one(p) for p in sys.argv[1:]]
for a in vals:
    label=("CONTROL" if "/run/" in a["path"] else "SYNC")
    print(f"{label}_AGE_SEC={a['age']:.2f}")
    print(f"{label}_CURRENT={a['current']}")
    print(f"{label}_PLAYLISTPOS={a['idx']}")
    print(f"{label}_POS_MS={a['pos']}")
best=min(vals,key=lambda x:x["age"])
raise SystemExit(0 if best["age"] <= 8 and best["current"] else 1)
PY
}

say "1/8 KEEP PUBLIC V32 UNTOUCHED"
systemctl is-active --quiet "$V32" || fail "V32_NOT_ACTIVE"
timeout 8 ffprobe -v error -rw_timeout 5000000 -show_entries stream=codec_name -of csv=p=0 \
  rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q . || fail "PUBLIC_RTMP_NOT_READY"
echo "PUBLIC_BASELINE=READY"

say "2/8 BACKUP EXISTING SYNC STATE"
cp -a /opt/studiosat/radio-v2/radioboss-sync/server.py "$BK/server.py.before" 2>/dev/null || true
cp -a /etc/systemd/system/studiosat-radioboss-sync.service "$BK/radioboss-sync.service.before" 2>/dev/null || true
cp -a "$STATION" "$BK/radioprincipal-state.before" 2>/dev/null || true

say "3/8 REPAIR SERVER-SIDE OWNERSHIP ONLY"
install -d -o studiosat-sync -g studiosat-sync -m 0750 "$SYNCROOT" "$STATION" "$CURRENT"
chown -R studiosat-sync:studiosat-sync "$SYNCROOT"
find "$SYNCROOT" -type d -exec chmod 0750 {} +
find "$SYNCROOT" -type f -exec chmod 0640 {} +
echo "SYNC_FS_PERMISSIONS=OK"

say "4/8 RESTART EXISTING HTTPS INGEST + CONTROL BRIDGE"
systemctl restart "$RBSYNC"
for i in $(seq 1 15); do
  if curl -fsS --max-time 2 http://127.0.0.1:8793/health >/dev/null; then
    echo "SYNC_API_DIRECT=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
curl -fsS --max-time 5 http://127.0.0.1:8793/health | tee "$BK/health-direct.json"
curl -kfsS --max-time 8 https://www.radio.studiosatweb.com.br/api/radioboss-sync/health | tee "$BK/health-nginx.json"
systemctl restart "$BRIDGE"
echo "CONTROL_BRIDGE=$(systemctl is-active "$BRIDGE")"

say "5/8 WAIT FOR EXISTING RADIOBOSS HTTPS AGENT"
OK=0
for i in $(seq 1 75); do
  if age_check >"$BK/freshness.txt" 2>&1; then
    cat "$BK/freshness.txt"
    OK=1
    echo "REALTIME_HTTPS_SYNC=FRESH AFTER=${i}s"
    break
  fi
  if (( i % 10 == 0 )); then
    cat "$BK/freshness.txt" 2>/dev/null || true
  fi
  sleep 1
done

if [ "$OK" -ne 1 ]; then
  echo "REALTIME_HTTPS_SYNC=NOT_RECEIVING"
  echo "PC_ACTION=START_EXISTING_TASK_StudioSat-RadioPrincipal-ControlAgent-V8"
  echo "NO_NEW_PC_INSTALL_REQUIRED=YES"
  echo "PUBLIC_V32_REMAINS_ACTIVE=YES"
  exit 42
fi

say "6/8 PROVE TWO CONSECUTIVE REALTIME UPDATES"
python3 - "$CURRENT/playback.json" <<'PY'
import json,os,sys,time
p=sys.argv[1]
def read():
    st=os.stat(p)
    x=json.load(open(p,encoding='utf-8-sig'))
    d=x.get('payload') or {}
    if isinstance(d,dict) and isinstance(d.get('data'),dict):d=d['data']
    return st.st_mtime_ns,d.get('playlistpos'),d.get('pos_ms'),((d.get('current') or {}).get('FILENAME') or '')
a=read(); time.sleep(2.3); b=read(); time.sleep(2.3); c=read()
print("UPDATE_A="+repr(a))
print("UPDATE_B="+repr(b))
print("UPDATE_C="+repr(c))
if not (b[0]>a[0] and c[0]>b[0]): raise SystemExit(1)
if not (b[3] and c[3]): raise SystemExit(2)
print("REALTIME_CADENCE=PASS")
PY

say "7/8 DOWNLOAD FINAL V6 INSTALLER"
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/final/INSTALL-RADIOPRINCIPAL-V6-PRODUCTION-NOW.sh' \
-o "$V6INSTALL"
chmod 0700 "$V6INSTALL"
bash -n "$V6INSTALL"
echo "V6_INSTALLER_SYNTAX=PASS"

say "8/8 RUN LAB-GATED FINAL CUTOVER"
bash "$V6INSTALL"
