#!/usr/bin/env bash
# C17 - read-only baseline for RadioPrincipal V2 rebuild.
# PROIBIDO alterar produção. Este script não chama systemctl start/stop/restart/enable/disable.
set -euo pipefail

echo '=============================================================='
echo ' C17 - RADIOPRINCIPAL V2 READ-ONLY BASELINE'
echo '=============================================================='
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"

echo
echo '===== 1. PRODUCTION SERVICES (READ ONLY) ====='
for u in   tps-mediamtx.service   nginx.service   studiosat-radioboss-sync.service   studiosat-media-transfer.service   studiosat-radioprincipal-selector.service   studiosat-radioprincipal-shadow-ns1.service   studiosat-radioprincipal-authority-candidate.service
do
  printf '%s ACTIVE=%s ENABLED=%s\n'     "$u"     "$(systemctl is-active "$u" 2>/dev/null || true)"     "$(systemctl is-enabled "$u" 2>/dev/null || true)"
done

echo
echo '===== 2. PORTS / TCP ====='
ss -ltnp 2>/dev/null | grep -E ':1935|:18005|:8789|:8793|:8888' || true
echo '-- established relevant --'
ss -tnp state established 2>/dev/null | grep -E ':18005|:1935|:8789|:8793' | tail -80 || true

echo
echo '===== 3. PUBLIC / SHADOW READ PROBES ====='
for p in radioprincipal radioprincipal-ns1; do
  echo "--- $p ---"
  timeout 6 ffprobe -v error -rw_timeout 3000000     -show_entries stream=codec_name,codec_type,sample_rate,channels     -of default=nw=1     "rtmp://127.0.0.1:1935/$p" 2>&1 || true
done

echo
echo '===== 4. SELECTOR LAST 5 MIN ====='
journalctl -u studiosat-radioprincipal-selector.service   --since '5 minutes ago' --no-pager |
  grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|emergency_blank|Feeding|Error|New metadata' |
  tail -160 || true

echo
echo '===== 5. AUTHORITY STATUS ====='
STATUS='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json'
if [ -r "$STATUS" ]; then
python3 - "$STATUS" <<'PY'
import json,sys,os,time
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
print("STATUS_MTIME_AGE_SEC=%.3f"%(time.time()-os.stat(p).st_mtime))
for k in ("version","status","playlist_revision_id","items","available","missing","unresolved","schedule_revision_id","schedule_events"):
 print(k.upper()+"="+str(d.get(k)))
print("PLAYBACK="+json.dumps(d.get("playback",{}),ensure_ascii=False))
print("FRESHNESS="+json.dumps(d.get("freshness",{}),ensure_ascii=False))
print("READINESS="+json.dumps(d.get("readiness",{}),ensure_ascii=False))
PY
else
  echo 'AUTHORITY_STATUS=UNAVAILABLE'
fi

echo
echo '===== 6. CURRENT MEDIA MAP ====='
MAP='/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json'
if [ -r "$MAP" ]; then
python3 - "$MAP" <<'PY'
import json,sys,os,time
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
print("MEDIA_MAP_AGE_SEC=%.3f"%(time.time()-os.stat(p).st_mtime))
for k in ("generation","mode","available_count","missing_count"):
 print(k.upper()+"="+str(d.get(k)))
tracks=d.get("tracks") or []
print("TRACKS="+str(len(tracks)))
for i,t in enumerate(tracks[:5]):
 print("TRACK[%d]=%s"%(i,json.dumps(t,ensure_ascii=False,sort_keys=True)))
PY
else
  echo 'MEDIA_MAP=UNAVAILABLE'
fi

echo
echo '===== 7. MEDIA TRANSFER SERVER: EXACT PUT PROTOCOL ====='
SERVER='/opt/studiosat/radio-v2/media-transfer/server.py'
if [ -r "$SERVER" ]; then
  sed -n '250,375p' "$SERVER"
else
  echo 'MEDIA_TRANSFER_SERVER=UNREADABLE'
fi

echo
echo '===== 8. MEDIA TRANSFER SERVER: EXISTS/REPORT PROTOCOL ====='
if [ -r "$SERVER" ]; then
  sed -n '165,250p' "$SERVER"
fi

echo
echo '===== 9. MEDIA TRANSFER DB SCHEMA ====='
DB='/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3'
if [ -r "$DB" ]; then
python3 - "$DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
for name in ("assets","sources","repository_index"):
 print("---",name,"---")
 row=c.execute("select sql from sqlite_master where type='table' and name=?",(name,)).fetchone()
 print(row[0] if row else "MISSING")
 try:
  print("COUNT="+str(c.execute("select count(*) from "+name).fetchone()[0]))
 except Exception as e: print("COUNT_ERROR="+repr(e))
c.close()
PY
else
  echo 'MEDIA_TRANSFER_DB=UNREADABLE'
fi

echo
echo '===== 10. RADIOBOSS CURRENT SNAPSHOT AGES ====='
ROOT='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
python3 - "$ROOT" <<'PY'
import os,time,sys,json
from pathlib import Path
r=Path(sys.argv[1])
for n in ("playlist.json","playback.json","schedule.json","librarymanifest.json","heartbeat.json"):
 p=r/n
 if not p.exists():
  print(n+"=MISSING");continue
 try:d=json.load(open(p,encoding='utf-8'))
 except Exception:d={}
 print("%s AGE_SEC=%.3f RECEIVED=%s REV=%s"%(n,time.time()-p.stat().st_mtime,d.get("received_at_utc"),d.get("revision")))
PY

echo
echo '===== 11. NO-DOWNTIME ASSERTION ====='
echo 'NO_SYSTEMCTL_MUTATION=YES'
echo 'NO_FILE_MUTATION=YES'
echo 'NO_PUBLIC_PATH_CHANGE=YES'
echo 'RESULTADO=C17_READONLY_BASELINE_OK'
