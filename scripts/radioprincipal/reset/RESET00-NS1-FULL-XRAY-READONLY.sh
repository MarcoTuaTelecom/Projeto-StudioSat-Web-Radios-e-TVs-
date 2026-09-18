#!/usr/bin/env bash
set -Eeuo pipefail
OUT="${1:-/root/RESET00-XRAY-RADIOPRINCIPAL-$(date -u +%Y%m%dT%H%M%SZ).txt}"
exec > >(tee "$OUT") 2>&1
sec(){ echo; printf '%0.s=' {1..110}; echo; echo "$1"; printf '%0.s=' {1..110}; echo; }

sec "RESET00-00 IDENTITY / SAFETY"
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"
echo "KERNEL=$(uname -a)"
echo "REPORT=$OUT"
echo "READ_ONLY_PRODUCTION=YES"

sec "RESET00-01 SYSTEMD RADIOPRINCIPAL INVENTORY"
mapfile -t UNITS < <(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -Ei 'radioprincipal|radioboss|mediamtx|nginx|media-transfer|studiosat' | sort -u)
for u in "${UNITS[@]}"; do
  echo "--- $u ---"
  systemctl show "$u" -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState -p MainPID -p NRestarts -p Result -p ExecMainStatus -p FragmentPath -p DropInPaths -p ExecStart 2>&1 || true
done

sec "RESET00-02 ACTIVE PROCESSES"
ps -eo pid,ppid,user,lstart,stat,%cpu,%mem,args --width 500 | grep -Ei 'liquidsoap|mediamtx|nginx|radioprincipal|radioboss|media-transfer|ffmpeg|ssh[d]?' | grep -v grep || true

sec "RESET00-03 LISTENERS / CONNECTIONS"
ss -ltnp 2>/dev/null | grep -E ':22\b|:1935\b|:8888\b|:9997\b|:18005\b|:18006\b|:8789\b|:8793\b|:8794\b|:8796\b' || true
echo "--- established ---"
ss -tinp state established 2>/dev/null | grep -A2 -B1 -E ':18005\b|:1935\b|:8793\b|:8794\b|:8796\b' || true

sec "RESET00-04 PUBLIC / SHADOW / TEST STREAM PROBES"
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-v2-shadow radioprincipal-v2-shadow-hotfix radioprincipal-test; do
  echo "--- $p ---"
  timeout 7 ffprobe -v error -rw_timeout 4000000 -show_entries stream=codec_name,codec_type,sample_rate,channels -of default=nw=1 "rtmp://127.0.0.1:1935/$p" 2>&1 || echo "PROBE_FAIL=$p"
done

sec "RESET00-05 HLS / MEDIAMTX API"
echo "--- HLS public ---"
timeout 7 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>&1 | head -40 || true
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-v2-shadow radioprincipal-v2-shadow-hotfix; do
  echo "--- API $p ---"
  timeout 4 curl -fsS "http://127.0.0.1:9997/v3/paths/get/$p" 2>&1 || true
  echo
done

sec "RESET00-06 SELECTOR CURRENT UNIT / CONFIG"
systemctl cat studiosat-radioprincipal-selector.service 2>&1 || true
if [ -f /etc/studiosat/radioprincipal-selector.liq ]; then
  echo "--- /etc/studiosat/radioprincipal-selector.liq ---"
  stat -Lc 'MODE=%a OWNER=%U:%G SIZE=%s MTIME=%y PATH=%n' /etc/studiosat/radioprincipal-selector.liq 2>&1 || true
  sha256sum /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true
  sed -n '1,360p' /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true
fi

sec "RESET00-07 SELECTOR JOURNAL LAST 6 HOURS"
journalctl -u studiosat-radioprincipal-selector.service --since '6 hours ago' -o short-iso-precise --no-pager 2>&1 | tail -3000 || true

sec "RESET00-08 RADIOBOSS LIVE / HARBOR EVIDENCE"
echo "HARBOR_LISTEN=$(ss -ltn 2>/dev/null | grep -q ':18005' && echo YES || echo NO)"
echo "HARBOR_ESTABLISHED=$(ss -tn state established 2>/dev/null | grep -q ':18005' && echo YES || echo NO)"
journalctl -u studiosat-radioprincipal-selector.service --since '6 hours ago' --no-pager 2>&1 | grep -Ei 'radioprincipal_rb_harbor|Switch to|Feeding|New metadata|Error while reading|Invalid data|relaying stopped' | tail -500 || true

sec "RESET00-09 RADIOBOSS CONTROL SNAPSHOTS"
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
python3 - "$SYNC" <<'PY' 2>&1 || true
import json,os,time,sys
from pathlib import Path
r=Path(sys.argv[1])
for name in ("playlist.json","playback.json","schedule.json","librarymanifest.json","heartbeat.json"):
    p=r/name
    print("\n###",name)
    if not p.exists():
        print("MISSING"); continue
    print("AGE_SEC=%.3f"%(time.time()-p.stat().st_mtime))
    try:d=json.load(open(p,encoding="utf-8"))
    except Exception as e:
        print("JSON_ERROR",repr(e)); continue
    print("REVISION=",d.get("revision"))
    print("RECEIVED=",d.get("received_at_utc"))
    q=d.get("payload",{}); x=q.get("data",q) if isinstance(q,dict) else {}
    if name=="playback.json" and isinstance(x,dict):
        c=x.get("current") or {}; n=x.get("next") or {}
        def ref(o):
            if not isinstance(o,dict):return None
            return o.get("FILENAME") or o.get("filename") or (o.get("TAG") or {}).get("FN")
        print("STATE=",x.get("state"))
        print("PLAYLISTPOS=",x.get("playlistpos"))
        print("POS_MS=",x.get("pos_ms"))
        print("LEN_MS=",x.get("len_ms"))
        print("CURRENT_REF=",ref(c))
        print("CURRENT_TITLE=",c.get("ITEMTITLE") or c.get("CASTTITLE") or c.get("TITLE"))
        print("NEXT_REF=",ref(n))
        print("NEXT_TITLE=",n.get("ITEMTITLE") or n.get("CASTTITLE") or n.get("TITLE"))
PY

sec "RESET00-10 RADIOBOSS PLAYLIST STRUCTURE"
python3 - "$SYNC/playlist.json" <<'PY' 2>&1 || true
import json,sys,xml.etree.ElementTree as ET
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
xmls=[]
def walk(x):
    if isinstance(x,str) and '<Playlist' in x: xmls.append(x)
    elif isinstance(x,dict):
        for v in x.values():walk(v)
    elif isinstance(x,list):
        for v in x:walk(v)
walk(d)
if not xmls:
    print("PLAYLIST_XML=NOT_FOUND")
    raise SystemExit
root=ET.fromstring(max(xmls,key=len))
tracks=root.findall('.//TRACK')
print("TRACK_COUNT="+str(len(tracks)))
for i,t in enumerate(tracks[:220]):
    a=dict(t.attrib)
    for c in list(t):
        a.setdefault(c.tag,c.text or '')
    ref=a.get('FILENAME') or a.get('filename') or a.get('FN') or a.get('FILE') or a.get('PATH') or ''
    print(f"{i:04d}\t{ref}")
PY

sec "RESET00-11 SHADOW CURRENT UNIT / EXECSTART"
systemctl cat studiosat-radioprincipal-shadow-ns1.service 2>&1 || true
systemctl show studiosat-radioprincipal-shadow-ns1.service -p ExecStart -p User -p Group -p Environment -p ReadOnlyPaths -p ReadWritePaths 2>&1 || true

sec "RESET00-12 LEGACY / V2 FILES"
for f in /opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py /opt/studiosat/radio-v2-next/radioprincipal/ordered-authoritative-shadow.py /opt/studiosat/radio-v2-next/radioprincipal/v2-shadow-playback-follower.py /opt/studiosat/radio-v2-next/radioprincipal/edge-bridge.py; do
  [ -e "$f" ] || continue
  echo "--- $f ---"
  stat -Lc 'MODE=%a OWNER=%U:%G SIZE=%s MTIME=%y PATH=%n' "$f" || true
  sha256sum "$f" 2>/dev/null || true
done

sec "RESET00-13 MEDIA TRANSFER / DATABASE"
systemctl cat studiosat-media-transfer.service 2>&1 || true
DB='/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3'
if [ -r "$DB" ]; then
python3 - "$DB" <<'PY' 2>&1 || true
import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
for t in ("assets","sources","repository_index"):
    print("\nTABLE",t)
    try:print("COUNT",c.execute("select count(*) from "+t).fetchone()[0])
    except Exception as e:print("COUNT_ERROR",repr(e))
    r=c.execute("select sql from sqlite_master where type='table' and name=?",(t,)).fetchone()
    print(r[0] if r else "SCHEMA_MISSING")
c.close()
PY
fi

sec "RESET00-14 HUMAN REPOSITORY"
ROOT='/srv/studiosat/radio-principal'
if [ -d "$ROOT" ]; then
  find "$ROOT" -maxdepth 3 -type d -print | sort
  python3 - "$ROOT" <<'PY' 2>&1 || true
import sys
from pathlib import Path
root=Path(sys.argv[1]);ext={'.mp3','.wav','.flac','.m4a','.aac','.ogg','.opus'}
for p in ('manha','tarde','noite'):
    d=root/'grade'/p
    if not d.is_dir():
        print(p.upper()+"=MISSING_DIR");continue
    fs=[x for x in d.iterdir() if x.is_file() and x.suffix.lower() in ext]
    print(p.upper()+"="+str(len(fs)))
PY
else
  echo "HUMAN_REPOSITORY=MISSING"
fi

sec "RESET00-15 OLD EXPERIMENTAL TASKS / TIMERS"
systemctl list-units --all --no-pager 2>/dev/null | grep -Ei 'radioprincipal|radioboss' || true
systemctl list-timers --all --no-pager 2>/dev/null | grep -Ei 'radioprincipal|radioboss|media-repo' || true

sec "RESET00-16 SSH TUNNEL ACCOUNT"
getent passwd studiosat-rb-tunnel 2>/dev/null || true
passwd -S studiosat-rb-tunnel 2>/dev/null || true
namei -l /var/lib/studiosat-rb-tunnel/.ssh/authorized_keys 2>/dev/null || true
[ -r /var/lib/studiosat-rb-tunnel/.ssh/authorized_keys ] && ssh-keygen -lf /var/lib/studiosat-rb-tunnel/.ssh/authorized_keys 2>/dev/null || true
for f in /etc/ssh/sshd_config.d/*radioboss* /etc/ssh/sshd_config.d/*studiosat*; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  sed -n '1,220p' "$f"
done

sec "RESET00-17 RECENT PRODUCTION FAILURES"
journalctl --since '12 hours ago' --no-pager 2>/dev/null | grep -Ei 'radioprincipal|radioboss|liquidsoap|mediamtx|mirror-playout|ordered-authoritative|sqlite|18005' | tail -4000 || true

sec "RESET00-18 FINAL FACT SUMMARY"
python3 - <<'PY' 2>&1 || true
import subprocess,os,time
def sh(x):
    return subprocess.run(x,shell=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True).stdout.strip()
for u in ['tps-mediamtx.service','nginx.service','studiosat-radioboss-sync.service','studiosat-media-transfer.service','studiosat-radioprincipal-selector.service','studiosat-radioprincipal-shadow-ns1.service']:
    print(u+"="+sh("systemctl is-active "+u))
print("HARBOR_LISTEN="+("YES" if ":18005" in sh("ss -ltn") else "NO"))
print("HARBOR_ESTABLISHED="+("YES" if ":18005" in sh("ss -tn state established") else "NO"))
for p in ("radioprincipal","radioprincipal-ns1"):
    q=sh("timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0 rtmp://127.0.0.1:1935/"+p)
    print(p.upper()+"="+("READY:"+q if q else "NOT_READY"))
pb='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'
if os.path.isfile(pb):
    print("PLAYBACK_AGE_SEC=%.3f"%(time.time()-os.stat(pb).st_mtime))
PY

echo "RESULTADO=RESET00_XRAY_COMPLETE"
echo "REPORT=$OUT"
