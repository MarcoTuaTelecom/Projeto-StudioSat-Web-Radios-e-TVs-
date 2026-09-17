#!/usr/bin/env python3
# Nome: authority-replica-candidate.py
# Versão: 0.3.1-candidate / 2026-09-17
# Owner: Rádio | Safety: candidate-write-isolated | Change: RADIOPRINCIPAL-NS1-C04
# Escreve somente em /var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica.
import argparse,hashlib,json,os,re,sqlite3,sys,tempfile,time,unicodedata
from datetime import datetime,timezone
from pathlib import Path
import xml.etree.ElementTree as ET
V='0.3.1-candidate'
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
CAND='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica'
STORE='/srv/tpsmedia/repository/channels/radioprincipal/mirror-store'
INDEX='/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3'
def now(): return datetime.now(timezone.utc).isoformat()
def norm(x): return unicodedata.normalize('NFC',str(x or '')).replace('\\','/').casefold().strip()
def base(x): return os.path.basename(str(x or '').replace('\\','/'))
def sj(x): return json.dumps(x,sort_keys=True,ensure_ascii=False,separators=(',',':'))
def sh(x): return hashlib.sha256(sj(x).encode()).hexdigest()
def load(p): return json.loads(Path(p).read_text(encoding='utf-8'))
def doc_age(d):
 s=d.get('received_at_utc') if isinstance(d,dict) else None
 if not s:return None
 try:
  x=datetime.fromisoformat(str(s).replace('Z','+00:00'))
  if x.tzinfo is None:x=x.replace(tzinfo=timezone.utc)
  return max(0.0,(datetime.now(timezone.utc)-x.astimezone(timezone.utc)).total_seconds())
 except Exception:return None
def data(d):
 x=d.get('payload',d) if isinstance(d,dict) else d
 return x.get('data',x) if isinstance(x,dict) else x
def pathval(d):
 if not isinstance(d,dict): return ''
 for k in ('filename','file','path','source_path','source','fn','FILENAME','FILE','PATH','SOURCE_PATH','FN'):
  if isinstance(d.get(k),str) and d[k].strip(): return d[k].strip()
 for k,v in d.items():
  if isinstance(v,str) and ('path' in k.casefold() or 'file' in k.casefold()) and v.strip(): return v.strip()
 return ''
def xmlstr(o,hint=None):
 out=[]
 def r(x):
  if isinstance(x,str):
   s=x.strip()
   if s.startswith('<') and (not hint or '<'+hint in s or '<'+hint.upper() in s): out.append(s)
  elif isinstance(x,dict):
   for v in x.values(): r(v)
  elif isinstance(x,list):
   for v in x:r(v)
 r(o); return max(out,key=len) if out else None
def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values(): yield from walk(v)
 elif isinstance(x,list):
  for v in x: yield from walk(v)
def manifest(doc):
 out=[];seen=set()
 for d in walk(data(doc)):
  sha=''
  for k,v in d.items():
   if k.casefold() in ('sha256','sha','hash_sha256','hash') and isinstance(v,str) and re.fullmatch(r'[0-9a-fA-F]{64}',v.strip()): sha=v.strip().lower();break
  if not sha: continue
  for k,v in d.items():
   if not any(t in k.casefold() for t in ('path','file','source','name','fn')): continue
   vals=[v] if isinstance(v,str) else (v if isinstance(v,list) else [])
   for z in vals:
    if isinstance(z,str) and z.strip():
     q=(sha,norm(z));
     if q not in seen: seen.add(q);out.append((sha,z.strip()))
 return out
def playlist(doc):
 x=xmlstr(doc,'Playlist')
 if x:
  root=ET.fromstring(x); tracks=[]
  for i,t in enumerate(root.findall('.//TRACK')):
   a={str(k):str(v) for k,v in t.attrib.items()}; a.update({c.tag:(c.text or '') for c in list(t) if c.tag not in a})
   tracks.append({'n':i,'ref':pathval(a),'a':a})
  return dict(root.attrib),tracks,'xml'
 lists=[]
 def r(x,k=''):
  if isinstance(x,list) and x and all(isinstance(z,dict) for z in x):
   score=sum(bool(pathval(z)) for z in x)
   if score: lists.append((score,len(x),k,x))
  elif isinstance(x,dict):
   for a,b in x.items():r(b,a)
 r(data(doc))
 if not lists:return {},[],'unknown'
 _,_,k,L=max(lists,key=lambda z:(z[0],z[1]));return {'source_key':k},[{'n':i,'ref':pathval(z),'a':z} for i,z in enumerate(L)],'json'
def schedule(doc):
 x=xmlstr(doc,'Schedule') or xmlstr(doc); out=[]
 if x:
  try:
   root=ET.fromstring(x);out=[{'n':i,'a':dict(e.attrib)} for i,e in enumerate(root.findall('.//item'))]
   if out:return out
  except ET.ParseError:pass
 lists=[]
 def r(x):
  if isinstance(x,list) and x and all(isinstance(z,dict) for z in x):lists.append(x)
  elif isinstance(x,dict):
   for v in x.values():r(v)
 r(data(doc));L=max(lists,key=len) if lists else [];return [{'n':i,'a':z} for i,z in enumerate(L)]
def playback(doc):
 d=data(doc);d=d if isinstance(d,dict) else {};cur=d.get('current') if isinstance(d.get('current'),dict) else {};nxt=d.get('next') if isinstance(d.get('next'),dict) else {}
 return {'state':d.get('state'),'playlistpos':d.get('playlistpos'),'pos_ms':d.get('pos_ms'),'len_ms':d.get('len_ms'),'timestamp':d.get('timestamp'),'current_ref':pathval(cur),'next_ref':pathval(nxt),'current':cur,'next':nxt}
def db(p):
 Path(p).parent.mkdir(parents=True,exist_ok=True);c=sqlite3.connect(p);c.execute('pragma journal_mode=wal');c.executescript('''
create table if not exists playlist_revisions(id text primary key,sem text unique,source_rev text,received text,program text,format text,item_count int,created text);
create table if not exists playlist_items(id text primary key,rev text,n int,source_ref text,ref_norm text,sha text,asset_id text,attrs text,unique(rev,n));
create table if not exists schedule_revisions(id text primary key,sem text unique,source_rev text,received text,event_count int,created text);
create table if not exists schedule_events(id text primary key,rev text,n int,attrs text,unique(rev,n));
create table if not exists assets(id text primary key,sha text unique,filename text,first_seen text,last_seen text);
create table if not exists presence(asset_id text primary key,path text,present int,checked text);
create table if not exists transfer_jobs(id text primary key,asset_id text,source_ref text,sha text,status text,priority int,created text,last_seen text);
create table if not exists playback_checkpoints(id integer primary key,captured text,received text,state text,playlistpos int,pos_ms int,len_ms int,current_ref text,current_asset_id text,current_sha text,next_ref text,raw text);
create table if not exists runs(id integer primary key,started text,finished text,status text,playlist_changed int,schedule_changed int,error text);
create table if not exists current_state(k text primary key,v text,updated text);
''');return c
def resolver(mdoc,idx):
 P={};B={}
 for sha,p in manifest(mdoc):P.setdefault(norm(p),set()).add(sha);B.setdefault(norm(base(p)),set()).add(sha)
 if Path(idx).is_file():
  try:
   c=sqlite3.connect(f'file:{idx}?mode=ro',uri=True)
   for p,sha,fn in c.execute('select source_path,sha256,filename from repository_index'):
    if sha:
     if p:P.setdefault(norm(p),set()).add(str(sha).lower())
     if fn:B.setdefault(norm(fn),set()).add(str(sha).lower())
   c.close()
  except Exception:pass
 def f(ref):
  s=P.get(norm(ref),set())
  if len(s)!=1:s=B.get(norm(base(ref)),set())
  return next(iter(s)) if len(s)==1 else ''
 return f
def local(store,sha):
 m=sorted(p for p in Path(store).glob(sha+'.*') if p.is_file()) if sha and Path(store).is_dir() else []
 return m[0] if m else None
def sync_once(a):
 src=Path(a.sync);out=Path(a.out);out.mkdir(parents=True,exist_ok=True);names=['playlist.json','schedule.json','librarymanifest.json','playback.json','heartbeat.json']
 miss=[n for n in names if not (src/n).is_file()]
 if miss:raise RuntimeError('snapshots ausentes: '+','.join(miss))
 D={n:load(src/n) for n in names}; c=db(a.db or out/'replica.sqlite3');started=now();rid=c.execute("insert into runs(started,status,playlist_changed,schedule_changed) values(?,'RUNNING',0,0)",(started,)).lastrowid
 try:
  ra,T,fmt=playlist(D['playlist.json']);S=schedule(D['schedule.json']);R=resolver(D['librarymanifest.json'],a.index);t=now();resolved=[]
  for x in T:
   sha=R(x['ref']) if x['ref'] else '';aid='sha256:'+sha if sha else ('source-ref:'+sh(norm(x['ref']))[:32] if x['ref'] else '') ;lp=local(a.store,sha);present=int(bool(lp));y={**x,'sha':sha,'asset':aid};resolved.append(y)
   if aid:
    c.execute('insert into assets values(?,?,?,?,?) on conflict(id) do update set last_seen=excluded.last_seen',(aid,sha or None,base(x['ref']) or None,t,t));c.execute('insert into presence values(?,?,?,?) on conflict(asset_id) do update set path=excluded.path,present=excluded.present,checked=excluded.checked',(aid,str(lp) if lp else None,present,t))
    if not present:
     jid='xfer_'+sh([aid,x['ref']])[:24];c.execute('insert into transfer_jobs values(?,?,?,?,?,?,?,?) on conflict(id) do update set last_seen=excluded.last_seen',(jid,aid,x['ref'],sha or None,'QUEUED',50,t,t))
  sem=sh({'root':ra,'items':[{'n':x['n'],'ref':norm(x['ref']),'a':x['a']} for x in resolved]});pr='sspr_'+sem[:24];exists=c.execute('select 1 from playlist_revisions where sem=?',(sem,)).fetchone();pch=0 if exists else 1
  program=next((str(ra[k]) for k in ('NAME','Name','name','TITLE','Title','title','FILENAME','filename') if ra.get(k)), '')
  if not exists:
   c.execute('insert into playlist_revisions values(?,?,?,?,?,?,?,?)',(pr,sem,str(D['playlist.json'].get('revision','')),D['playlist.json'].get('received_at_utc'),program,fmt,len(resolved),t))
   for x in resolved:c.execute('insert into playlist_items values(?,?,?,?,?,?,?,?)',('sspi_'+sh([sem,x['n'],norm(x['ref']),x['sha']])[:24],pr,x['n'],x['ref'],norm(x['ref']),x['sha'] or None,x['asset'] or None,sj(x['a'])))
  else:pr=c.execute('select id from playlist_revisions where sem=?',(sem,)).fetchone()[0]
  ssem=sh(S);sr='sssr_'+ssem[:24];sex=c.execute('select 1 from schedule_revisions where sem=?',(ssem,)).fetchone();sch=0 if sex else 1
  if not sex:
   c.execute('insert into schedule_revisions values(?,?,?,?,?,?)',(sr,ssem,str(D['schedule.json'].get('revision','')),D['schedule.json'].get('received_at_utc'),len(S),t))
   for e in S:c.execute('insert into schedule_events values(?,?,?,?)',('ssse_'+sh([ssem,e])[:24],sr,e['n'],sj(e['a'])))
  else:sr=c.execute('select id from schedule_revisions where sem=?',(ssem,)).fetchone()[0]
  p=playback(D['playback.json']);cs=R(p['current_ref']) if p['current_ref'] else '';ca='sha256:'+cs if cs else ('source-ref:'+sh(norm(p['current_ref']))[:32] if p['current_ref'] else None);cp=local(a.store,cs);c.execute('insert into playback_checkpoints(captured,received,state,playlistpos,pos_ms,len_ms,current_ref,current_asset_id,current_sha,next_ref,raw) values(?,?,?,?,?,?,?,?,?,?,?)',(t,D['playback.json'].get('received_at_utc'),p['state'],p['playlistpos'],p['pos_ms'],p['len_ms'],p['current_ref'],ca,cs or None,p['next_ref'],sj(p)))
  avail=sum(bool(local(a.store,x['sha'])) for x in resolved);unres=sum(not bool(x['sha']) for x in resolved);missing=len(resolved)-avail
  replica_complete=bool(resolved) and missing==0 and unres==0
  current_ready=bool(cp)
  hb=data(D['heartbeat.json']); hb=hb if isinstance(hb,dict) else {}
  hb_age=doc_age(D['heartbeat.json']); pb_age=doc_age(D['playback.json']); pl_age=doc_age(D['playlist.json']); sc_age=doc_age(D['schedule.json']); lm_age=doc_age(D['librarymanifest.json'])
  playback_fresh=pb_age is not None and pb_age <= a.playback_max_age
  hb_online=bool(hb.get('online')) and hb_age is not None and hb_age <= a.heartbeat_max_age
  pb_payload=D['playback.json'].get('payload',{}) if isinstance(D['playback.json'],dict) else {}
  pb_declared=pb_payload.get('radioboss_online') if isinstance(pb_payload,dict) else None
  source_online=bool(playback_fresh and pb_declared is not False)
  pos=p.get('playlistpos'); cur_match=False; next_match=False
  try:
   pos=int(pos)
   if 0 <= pos < len(resolved): cur_match=bool(p['current_ref']) and norm(resolved[pos]['ref'])==norm(p['current_ref'])
   if not p['next_ref']: next_match=True
   elif 0 <= pos+1 < len(resolved): next_match=norm(resolved[pos+1]['ref'])==norm(p['next_ref'])
  except Exception: pass
  queue_aligned=cur_match and next_match
  if replica_complete and current_ready and source_online and playback_fresh and queue_aligned: status='HOT_READY'
  elif replica_complete and current_ready and (not source_online or not playback_fresh): status='REPLICA_READY_SOURCE_STALE'
  elif replica_complete and current_ready and source_online and playback_fresh and not queue_aligned: status='SOURCE_ONLINE_QUEUE_DIVERGED'
  else: status='NOT_READY'
  state={'version':V,'updated_at':t,'playlist_revision_id':pr,'program_hint':program,'items':len(resolved),'available':avail,'missing':missing,'unresolved':unres,'schedule_revision_id':sr,'schedule_events':len(S),'playback':{**p,'current_asset_id':ca,'current_sha256':cs,'current_ready':current_ready},'heartbeat':hb,'freshness':{'heartbeat_age_sec':hb_age,'playback_age_sec':pb_age,'playlist_age_sec':pl_age,'schedule_age_sec':sc_age,'librarymanifest_age_sec':lm_age,'heartbeat_max_age_sec':a.heartbeat_max_age,'playback_max_age_sec':a.playback_max_age,'heartbeat_online':hb_online,'source_online':source_online,'playback_fresh':playback_fresh},'readiness':{'replica_complete':replica_complete,'current_item_ready':current_ready,'current_matches_playlistpos':cur_match,'next_matches_playlistpos_plus_1':next_match,'queue_aligned':queue_aligned},'editorial_noop':not bool(pch or sch),'status':status}
  for k,v in [('latest',sj(state)),('status',status),('playlist_revision_id',pr),('schedule_revision_id',sr)]:c.execute('insert into current_state values(?,?,?) on conflict(k) do update set v=excluded.v,updated=excluded.updated',(k,v,t))
  c.execute("update runs set finished=?,status='OK',playlist_changed=?,schedule_changed=? where id=?",(now(),pch,sch,rid));c.commit();tmp=out/'status.json.tmp';tmp.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');os.replace(tmp,out/'status.json');print(f'RESULT=OK STATUS={status} PROGRAM={program!r} PLAYLIST_REV={pr} ITEMS={len(resolved)} AVAILABLE={avail} MISSING={missing} UNRESOLVED={unres} PLAYLIST_CHANGED={pch} SCHEDULE_CHANGED={sch} CURRENT={base(p["current_ref"])} POS_MS={p["pos_ms"]} DB={a.db or out/"replica.sqlite3"}');return state
 except Exception as e:
  c.rollback();
  try:c.execute("update runs set finished=?,status='ERROR',error=? where id=?",(now(),repr(e),rid));c.commit()
  except Exception:pass
  raise
 finally:c.close()
def selftest():
 with tempfile.TemporaryDirectory() as td:
  r=Path(td);s=r/'s';o=r/'o';st=r/'store';s.mkdir();st.mkdir();blob=b'abc';sha=hashlib.sha256(blob).hexdigest();(st/(sha+'.mp3')).write_bytes(blob)
  def w(n,x):(s/n).write_text(json.dumps(x),encoding='utf-8')
  pl='<Playlist NAME="Tarde Studio Sat Principal"><TRACK FILENAME="C:\\M\\A.mp3"/><TRACK FILENAME="C:\\M\\B.mp3"/></Playlist>';wrap=lambda k,d,rev=1:{'kind':k,'revision':rev,'received_at_utc':now(),'payload':{'data':d}}
  w('playlist.json',{'kind':'playlist','revision':1,'received_at_utc':now(),'payload':{'xml':pl}});w('schedule.json',wrap('schedule',{'events':[{'time':'17:00:00'}]}));w('librarymanifest.json',wrap('librarymanifest',{'files':[{'sha256':sha,'path':'C:\\M\\A.mp3'},{'sha256':'f'*64,'path':'C:\\M\\B.mp3'}]}));w('playback.json',wrap('playback',{'state':'play','playlistpos':0,'pos_ms':1000,'len_ms':10000,'current':{'FILENAME':'C:\\M\\A.mp3'},'next':{'FILENAME':'C:\\M\\B.mp3'}}));w('heartbeat.json',wrap('heartbeat',{'online':True}));a=argparse.Namespace(sync=str(s),out=str(o),db=None,index=str(r/'none'),store=str(st),watch=False,interval=5,heartbeat_max_age=15,playback_max_age=10);x=sync_once(a);assert x['items']==2 and x['available']==1 and x['missing']==1;p=load(s/'playlist.json');p['revision']=2;p['received_at_utc']=now();w('playlist.json',p);y=sync_once(a);assert y['playlist_revision_id']==x['playlist_revision_id'] and y['editorial_noop'];p['payload']['xml']=pl.replace('A.mp3"/><TRACK FILENAME="C:\\M\\B','B.mp3"/><TRACK FILENAME="C:\\M\\A');w('playlist.json',p);z=sync_once(a);assert z['playlist_revision_id']!=x['playlist_revision_id'];print('SELF_TEST=PASS')
def main():
 p=argparse.ArgumentParser();p.add_argument('--sync',default=SYNC);p.add_argument('--out',default=CAND);p.add_argument('--db');p.add_argument('--index',default=INDEX);p.add_argument('--store',default=STORE);p.add_argument('--watch',action='store_true');p.add_argument('--interval',type=float,default=5);p.add_argument('--heartbeat-max-age',type=float,default=15);p.add_argument('--playback-max-age',type=float,default=10);p.add_argument('--self-test',action='store_true');a=p.parse_args()
 if a.self_test:selftest();return 0
 while True:
  try:sync_once(a)
  except Exception as e:
   print('RESULT=ERROR',repr(e),file=sys.stderr)
   if not a.watch:return 1
  if not a.watch:return 0
  time.sleep(max(1,a.interval))
if __name__=='__main__':raise SystemExit(main())
