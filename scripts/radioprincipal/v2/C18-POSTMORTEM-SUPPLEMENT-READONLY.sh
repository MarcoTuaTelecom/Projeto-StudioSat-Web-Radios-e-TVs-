#!/usr/bin/env bash
# RadioPrincipal C18 supplement — read-only postmortem after C12/C14 incidents.
# It does not start/stop/restart/enable/disable services and does not change configs/media.
set -uo pipefail
OUT="${1:-/root/XRAY-RADIOPRINCIPAL-C18-SUPPLEMENT-$(date -u +%Y%m%dT%H%M%SZ).txt}"
exec > >(tee "$OUT") 2>&1
sec(){ echo; printf '%0.s=' {1..100}; echo; echo "$1"; printf '%0.s=' {1..100}; echo; }
statf(){ echo "--- $1 ---"; stat -Lc 'TYPE=%F MODE=%a OWNER=%U:%G SIZE=%s MTIME=%y PATH=%n' "$1" 2>&1 || true; [ -f "$1" ] && sha256sum "$1" 2>/dev/null || true; }

sec 'C18-00 SAFETY / HOST'
echo XRAY=C18-POSTMORTEM-SUPPLEMENT-READONLY
echo UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo HOST="$(hostname -f 2>/dev/null || hostname)"
echo NO_SYSTEMCTL_MUTATION=YES
echo NO_CONFIG_MUTATION=YES
echo NO_MEDIA_MUTATION=YES

sec 'C18-01 CURRENT PRODUCTION STATE'
for u in tps-mediamtx.service nginx.service studiosat-radioboss-sync.service studiosat-media-transfer.service studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service studiosat-radioprincipal-authority-candidate.service studiosat-radioprincipal-mirror-controller.timer studiosat-radioprincipal-v8-control-bridge.service studiosat-radioprincipal-v8-stage.service studiosat-radioprincipal-v8-production.service studiosat-radioprincipal-v8-live-ingress.service; do
  echo "--- $u ---"
  systemctl show "$u" -p ActiveState -p SubState -p UnitFileState -p MainPID -p NRestarts -p Result -p ExecMainStatus -p FragmentPath -p ExecStart 2>&1 || true
done

echo '--- timers ---'
systemctl list-timers --all --no-pager 2>&1 | grep -Ei 'radioprincipal|media-repo' || true

sec 'C18-02 PORTS / PROCESSES / TUNNEL'
ss -ltnp 2>/dev/null | grep -E ':22\b|:1935\b|:8888\b|:9997\b|:8789\b|:8793\b|:18005\b|:18006\b' || true
ss -tnp state established 2>/dev/null | grep -E ':22\b|:1935\b|:8789\b|:8793\b|:18005\b|:18006\b' || true
ps -eo pid,ppid,user,lstart,stat,%cpu,%mem,args --width 500 | grep -Ei 'radioprincipal|radioboss|media-transfer|studiosat-rb-tunnel|liquidsoap|mediamtx' | grep -v grep || true

sec 'C18-03 PUBLIC / SHADOW / TEST PROBES'
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-test radioprincipal-v2-shadow radioprincipal-v2-test; do
 echo "--- $p ---"
 timeout 7 ffprobe -v error -rw_timeout 4000000 -show_entries stream=codec_name,codec_type,sample_rate,channels -of default=nw=1 "rtmp://127.0.0.1:1935/$p" 2>&1 || echo "PROBE_FAIL=$p"
done
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-test; do
 echo "--- MEDIAMTX API $p ---"
 timeout 4 curl -fsS "http://127.0.0.1:9997/v3/paths/get/$p" 2>&1 || true; echo
done

echo '--- HLS ---'
timeout 7 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>&1 | head -35 || true

sec 'C18-04 SELECTOR / SHADOW CURRENT CONFIG'
systemctl cat studiosat-radioprincipal-selector.service 2>&1 || true
systemctl cat studiosat-radioprincipal-shadow-ns1.service 2>&1 || true
statf /etc/studiosat/radioprincipal-selector.liq
sed -n '1,280p' /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true
statf /opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py
statf /opt/studiosat/radio-v2/radioprincipal-shadow/playback-synced-shadow.py

echo '--- selector last 3h ---'
journalctl -u studiosat-radioprincipal-selector.service --since '3 hours ago' --no-pager 2>&1 | tail -1500 || true
echo '--- shadow last 3h ---'
journalctl -u studiosat-radioprincipal-shadow-ns1.service --since '3 hours ago' --no-pager 2>&1 | tail -1500 || true

sec 'C18-05 INCIDENT TIMELINE'
journalctl --since '2026-09-17 23:35:00 UTC' --no-pager 2>/dev/null | grep -Ei 'radioprincipal|radioboss|selector|shadow|mirror|sqlite|mediamtx|liquidsoap|18005|1935|C12|C14' | tail -3000 || true

sec 'C18-06 RADIOBOSS AUTHORITY / QUEUE / FRESHNESS'
python3 - <<'PY' 2>&1 || true
import json,os,time
from pathlib import Path
r=Path('/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current')
for n in ('playlist.json','playback.json','schedule.json','librarymanifest.json','heartbeat.json'):
 p=r/n; print('\n###',n)
 if not p.exists(): print('MISSING'); continue
 d=json.load(open(p,encoding='utf-8')); print('AGE_SEC=%.3f'%(time.time()-p.stat().st_mtime),'REV=',d.get('revision'),'RECEIVED=',d.get('received_at_utc'))
 q=d.get('payload',{}); x=q.get('data',q) if isinstance(q,dict) else {}
 if n=='playback.json':
  c=x.get('current') or {}; z=x.get('next') or {}
  print('STATE=',x.get('state'),'PLAYLISTPOS=',x.get('playlistpos'),'POS_MS=',x.get('pos_ms'),'LEN_MS=',x.get('len_ms'),'ONLINE=',x.get('radioboss_online'))
  print('CURRENT=',c.get('FILENAME') or c.get('TAG',{}).get('FN')); print('CURRENT_TITLE=',c.get('ITEMTITLE') or c.get('CASTTITLE') or c.get('TITLE'))
  print('NEXT=',z.get('FILENAME') or z.get('TAG',{}).get('FN')); print('NEXT_TITLE=',z.get('ITEMTITLE') or z.get('CASTTITLE') or z.get('TITLE'))
PY

S=/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json
[ -r "$S" ] && python3 - "$S" <<'PY' 2>&1 || true
import json,sys,os,time
d=json.load(open(sys.argv[1],encoding='utf-8'))
print('STATUS_AGE_SEC=%.3f'%(time.time()-os.stat(sys.argv[1]).st_mtime))
for k in ('version','status','playlist_revision_id','items','available','missing','unresolved','schedule_revision_id','schedule_events'): print(k.upper(),d.get(k))
print('PLAYBACK',json.dumps(d.get('playback',{}),ensure_ascii=False)); print('FRESHNESS',json.dumps(d.get('freshness',{}),ensure_ascii=False)); print('READINESS',json.dumps(d.get('readiness',{}),ensure_ascii=False))
PY

sec 'C18-07 CANDIDATE SQLITE / C14 FAILURE CONDITIONS'
C=/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica
ls -lah --time-style=full-iso "$C" 2>&1 || true
namei -l "$C/replica.sqlite3" 2>&1 || true
for f in "$C/replica.sqlite3" "$C/replica.sqlite3-wal" "$C/replica.sqlite3-shm"; do statf "$f"; done
[ -r "$C/replica.sqlite3" ] && python3 - "$C/replica.sqlite3" <<'PY' 2>&1 || true
import sqlite3,sys
p=sys.argv[1]
for label,uri,dsn in [('RO_URI',True,'file:'+p+'?mode=ro'),('RW_DEFAULT',False,p)]:
 try:
  c=sqlite3.connect(dsn,uri=uri,timeout=2); print(label,'OPEN=OK','JOURNAL=',c.execute('pragma journal_mode').fetchone()[0]); c.close()
 except Exception as e: print(label,'OPEN=FAIL',repr(e))
PY

sec 'C18-08 PLAYLIST x MEDIA-MAP x CURRENT/NEXT'
python3 - <<'PY' 2>&1 || true
import json,os,unicodedata
from pathlib import Path
rb=Path('/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json')
mm=Path('/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json')
def norm(s): return unicodedata.normalize('NFC',str(s or '')).replace('\\','/').casefold().strip()
def base(s): return os.path.basename(str(s or '').replace('\\','/')).casefold()
B=json.load(open(rb,encoding='utf-8')); M=json.load(open(mm,encoding='utf-8')); q=B.get('payload',{}); x=q.get('data',q); c=x.get('current') or {}; n=x.get('next') or {}
tracks=M.get('tracks') or []
print('MAP_GENERATION=',M.get('generation'),'TRACKS=',len(tracks),'AVAILABLE=',M.get('available_count'),'MISSING=',M.get('missing_count'))
for label,o in [('CURRENT',c),('NEXT',n)]:
 ref=o.get('FILENAME') or o.get('TAG',{}).get('FN') or ''
 exact=[t for t in tracks if norm(t.get('source_windows'))==norm(ref)]; bn=[t for t in tracks if base(t.get('source_windows') or t.get('filename'))==base(ref)]
 z=exact or (bn if len(bn)==1 else [])
 print(label+'_REF=',ref); print(label+'_MATCHES=',len(z)); [print(label+'_MAP=',json.dumps(t,ensure_ascii=False,sort_keys=True)) for t in z[:3]]
PY

sec 'C18-09 MEDIA LIBRARIES / DUPLICATE STORES'
for d in /srv/tpsmedia/repository/channels/radioprincipal /srv/tpsmedia/repository/channels/radioprincipal/mirror-store /var/lib/studiosat/radio-v2/media-transfer /var/lib/studiosat/radio-v2/stations/radioprincipal /var/lib/studiosat/radio-v2-next/radioprincipal; do
 echo "--- $d ---"; [ -e "$d" ] && { du -sh "$d" 2>&1 || true; find "$d" -maxdepth 2 -type d -printf '%p\n' 2>/dev/null | sort | head -250; } || echo MISSING
done
python3 - <<'PY' 2>&1 || true
import os
roots=['/srv/tpsmedia/repository/channels/radioprincipal','/var/lib/studiosat/radio-v2/media-transfer','/var/lib/studiosat/radio-v2/stations/radioprincipal']; exts={'.mp3','.wav','.flac','.m4a','.aac','.ogg','.opus'}
for root in roots:
 if not os.path.isdir(root): continue
 d={}
 for dp,_,fs in os.walk(root):
  n=sum(os.path.splitext(f)[1].lower() in exts for f in fs)
  if n:d[dp]=n
 print('\nROOT=',root,'TOTAL_AUDIO=',sum(d.values()),'DIRS=',len(d))
 for p,n in sorted(d.items(),key=lambda x:(-x[1],x[0]))[:120]:print(n,p)
PY

sec 'C18-10 MEDIA TRANSFER EXACT PROTOCOL / DATABASE'
statf /opt/studiosat/radio-v2/media-transfer/server.py
sed -n '1,390p' /opt/studiosat/radio-v2/media-transfer/server.py 2>/dev/null || true
D=/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3
[ -r "$D" ] && python3 - "$D" <<'PY' 2>&1 || true
import sqlite3,sys
c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
for t in ('assets','sources','repository_index'):
 print('\nTABLE',t,'COUNT',c.execute('select count(*) from '+t).fetchone()[0]); r=c.execute("select sql from sqlite_master where type='table' and name=?",(t,)).fetchone(); print(r[0] if r else 'MISSING')
print('\nRECENT SOURCES')
for r in c.execute('select * from sources order by updated_at_utc desc limit 50'): print(dict(r))
c.close()
PY
journalctl -u studiosat-media-transfer.service --since '3 hours ago' --no-pager 2>&1 | tail -1200 || true

sec 'C18-11 MIRROR GENERATIONS / TIMER / CHURN'
readlink -f /var/lib/studiosat/radio-v2/stations/radioprincipal/current 2>&1 || true
systemctl cat studiosat-radioprincipal-mirror-controller.timer 2>&1 || true
find /var/lib/studiosat/radio-v2/stations/radioprincipal/generations -mindepth 1 -maxdepth 1 -type d -printf '%T@ %TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | sort -nr | head -100 || true
journalctl -u studiosat-radioprincipal-mirror-controller.service --since '2 hours ago' --no-pager 2>&1 | tail -1000 || true

sec 'C18-12 LEGACY/V8 ACTIVE REFERENCES'
for u in studiosat-radioprincipal-v8-control-bridge.service studiosat-radioprincipal-v8-stage.service studiosat-radioprincipal-v8-production.service studiosat-radioprincipal-v8-live-ingress.service tps-radioprincipal-failover.service tps-radioprincipal-playout.service; do systemctl cat "$u" 2>&1 || true; done
ps -eo pid,ppid,user,lstart,args --width 500 | grep -Ei 'radioprincipal|radioboss' | grep -v grep || true

sec 'C18-13 BACKUPS / C12-C14 ARTIFACTS'
find /root/studiosat-backups -maxdepth 2 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort | tail -700 || true
for d in /root/studiosat-backups/C12-* /root/studiosat-backups/C14-*; do [ -d "$d" ] || continue; echo "--- $d ---"; find "$d" -maxdepth 2 -type f -print 2>/dev/null; done

sec 'C18-14 FINAL AUTOMATED SUMMARY'
python3 - <<'PY' 2>&1 || true
import subprocess,json,os
def sh(x):return subprocess.run(x,shell=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True).stdout.strip()
for u in ['tps-mediamtx.service','nginx.service','studiosat-radioboss-sync.service','studiosat-media-transfer.service','studiosat-radioprincipal-selector.service','studiosat-radioprincipal-shadow-ns1.service','studiosat-radioprincipal-authority-candidate.service']:
 print(u+'='+sh('systemctl is-active '+u))
print('HARBOR_18005_LISTEN='+('YES' if ':18005' in sh('ss -ltn') else 'NO'))
for p in ['radioprincipal','radioprincipal-ns1']:
 q=sh("timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0 rtmp://127.0.0.1:1935/"+p)
 print(p.upper()+'_RTMP='+('READY:'+q if q else 'NOT_READY'))
s='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json'
if os.path.isfile(s):
 d=json.load(open(s,encoding='utf-8'));print('AUTHORITY_STATUS='+str(d.get('status')));print('ITEMS='+str(d.get('items'))+' AVAILABLE='+str(d.get('available'))+' MISSING='+str(d.get('missing')));print('QUEUE_ALIGNED='+str((d.get('readiness') or {}).get('queue_aligned')))
PY

echo RESULTADO=C18_SUPPLEMENT_COMPLETE
echo REPORT="$OUT"
