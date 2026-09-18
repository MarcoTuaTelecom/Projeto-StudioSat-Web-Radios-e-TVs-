#!/usr/bin/env python3
import argparse
import difflib
import json
import os
import re
import selectors
import sqlite3
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime, timezone

STATION="radioprincipal"
SYNC=Path(os.environ.get("STUDIOSAT_V5_SYNC","/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current"))
PLAYLIST=SYNC/"playlist.json"
PLAYBACK=SYNC/"playback.json"
SCHEDULE=SYNC/"schedule.json"
MANIFEST=SYNC/"librarymanifest.json"

BASE=Path(os.environ.get("STUDIOSAT_V5_BASE","/var/lib/studiosat/radio-principal-v5"))
INDEX=BASE/"library-index.json"
QUEUE=BASE/"effective-queue.json"
STATE=BASE/"state.json"
RTMP=os.environ.get("STUDIOSAT_V5_RTMP","rtmp://127.0.0.1:1935/radioprincipal")

ROOTS=[
    Path(x) for x in os.environ.get(
        "STUDIOSAT_V5_ROOTS",
        "/srv/studiosat/radio-principal"
        + os.pathsep +
        "/srv/tpsmedia/repository/channels/radioprincipal/mirror-store"
        + os.pathsep +
        "/srv/tpsmedia/repository/channels/radioprincipal/ready"
    ).split(os.pathsep) if x
]
EXTS={".mp3",".m4a",".aac",".wav",".flac",".ogg",".opus"}

RUN=True
CHUNK=3840
SILENCE=b"\x00"*CHUNK
CONTROL_FRESH_SEC=float(os.environ.get("STUDIOSAT_V5_CONTROL_FRESH_SEC","15"))
MEDIA_DB=Path(os.environ.get("STUDIOSAT_V5_MEDIA_DB","/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3"))

def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())} {msg}",flush=True)

def norm(s):
    s=str(s or "").replace("\\","/")
    s=unicodedata.normalize("NFKD",s)
    s="".join(c for c in s if not unicodedata.combining(c))
    s=s.casefold().strip()
    return re.sub(r"\s+"," ",s)

def norm_key(s):
    s=norm(s)
    s=os.path.basename(s)
    s=re.sub(r"\.(mp3|m4a|aac|wav|flac|ogg|opus)$","",s,flags=re.I)
    s=re.sub(r"^\s*\d+\s*[-_. ]+\s*","",s)
    s=re.sub(r"[^a-z0-9]+"," ",s)
    return re.sub(r"\s+"," ",s).strip()

def atomic_json(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix(path.suffix+".tmp")
    tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding="utf-8")
    os.replace(tmp,path)

def load_json(path):
    with open(path,encoding="utf-8-sig") as f:
        return json.load(f)

def unwrap_payload(d):
    if not isinstance(d,dict):
        return d
    p=d.get("payload",d)
    if isinstance(p,dict):
        for k in ("data","payload"):
            if k in p and isinstance(p[k],dict):
                return p[k]
    return p

def find_xml(obj,root_name):
    candidates=[]
    def walk(v):
        if isinstance(v,str):
            t=v.lstrip()
            if t.startswith("<") and root_name.casefold() in t[:300].casefold():
                candidates.append(v)
        elif isinstance(v,dict):
            for x in v.values():
                walk(x)
        elif isinstance(v,list):
            for x in v:
                walk(x)
    walk(obj)
    if not candidates:
        raise ValueError(f"no XML {root_name} found")
    return max(candidates,key=len)

def track_attr(t,key):
    want=key.casefold()
    for k,v in t.attrib.items():
        if k.casefold()==want:
            return v or ""
    for child in list(t):
        if child.tag.casefold()==want and (child.text or "").strip():
            return (child.text or "").strip()
        if child.tag.casefold()=="tag":
            for k,v in child.attrib.items():
                if k.casefold()==want:
                    return v or ""
    return ""

def parse_playlist():
    raw=load_json(PLAYLIST)
    xml=find_xml(raw,"Playlist")
    root=ET.fromstring(xml)
    tracks=root.findall(".//TRACK")
    out=[]
    for i,t in enumerate(tracks):
        src=(track_attr(t,"FILENAME") or track_attr(t,"FN") or
             track_attr(t,"FILE") or track_attr(t,"PATH") or "")
        artist=track_attr(t,"ARTIST") or track_attr(t,"Artist")
        title=track_attr(t,"TITLE") or track_attr(t,"Title")
        itemtitle=track_attr(t,"ITEMTITLE") or track_attr(t,"CASTTITLE")
        duration=track_attr(t,"DURATION") or track_attr(t,"Duration")
        low=src.casefold().strip()
        virtual=low.startswith("saytime=") or low.startswith("command=")
        kind="saytime" if low.startswith("saytime=") else ("virtual" if virtual else "media")
        out.append({
            "index":i,
            "playlistpos":i,
            "kind":kind,
            "virtual":virtual,
            "source_path":src,
            "source_basename":os.path.basename(src.replace("\\","/")),
            "artist":artist,
            "title":title,
            "itemtitle":itemtitle,
            "duration":duration
        })
    return out,raw

def parse_playback():
    raw=load_json(PLAYBACK)
    d=unwrap_payload(raw)
    if not isinstance(d,dict):
        raise ValueError("playback payload is not object")
    return d,raw

def scan_library():
    entries=[]
    seen=set()
    for root in ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            try:
                if not p.is_file() or p.suffix.casefold() not in EXTS:
                    continue
                # Preserve the visible alias name. Do not resolve symlinks here.
                # Human grade entries often point to SHA-named mirror-store files.
                rp=str(p.absolute())
                if rp in seen:
                    continue
                seen.add(rp)
                st=p.stat()
                entries.append({
                    "path":rp,
                    "real_path":str(p.resolve()),
                    "basename":p.name,
                    "stem_key":norm_key(p.name),
                    "basename_key":norm(p.name),
                    "size":st.st_size,
                    "mtime":st.st_mtime,
                    "root":str(root),
                    "is_symlink":p.is_symlink(),
                    "sha_from_filename": p.stem.casefold() if re.fullmatch(r"[0-9a-fA-F]{64}",p.stem) else "",
                })
            except (OSError,PermissionError):
                continue
    db_aliases=db_alias_entries()
    entries.extend(db_aliases)
    entries.sort(key=lambda x:(x.get("source_full_key",""),x["path"],x["basename"]))
    idx={
        "schema":"studiosat.library-index.v2",
        "generated_at_utc":datetime.now(timezone.utc).isoformat(),
        "roots":[str(x) for x in ROOTS],
        "count":len(entries),
        "symlink_aliases":sum(1 for x in entries if x.get("is_symlink")),
        "db_aliases":sum(1 for x in entries if x.get("db_alias")),
        "files":entries,
    }
    atomic_json(INDEX,idx)
    return idx

def manifest_entries():
    try:
        raw=load_json(MANIFEST)
    except Exception:
        return []
    root=unwrap_payload(raw)
    out=[]
    def walk(v):
        if isinstance(v,dict):
            sha=str(v.get("sha256") or v.get("sha") or v.get("hash") or "").casefold()
            refs=[]
            for k in ("source_path","path","filename","file","logical_path","windows_path"):
                val=v.get(k)
                if isinstance(val,str) and val.strip():
                    refs.append(val.strip())
            if re.fullmatch(r"[0-9a-f]{64}",sha):
                for ref in refs:
                    out.append((ref,sha))
            for x in v.values():
                walk(x)
        elif isinstance(v,list):
            for x in v:
                walk(x)
    walk(root)
    return out

def manifest_maps():
    full={}
    base={}
    for ref,sha in manifest_entries():
        full.setdefault(norm(ref),set()).add(sha)
        base.setdefault(norm(os.path.basename(ref.replace("\\","/"))),set()).add(sha)
    return full,base
def db_alias_entries():
    out=[]
    if not MEDIA_DB.is_file():
        return out
    try:
        c=sqlite3.connect(f"file:{MEDIA_DB}?mode=ro",uri=True,timeout=5)
        c.row_factory=sqlite3.Row
    except Exception:
        return out
    try:
        queries=[
            """SELECT s.source_path AS source_path, s.sha256 AS sha256,
                      COALESCE(a.object_path,'') AS object_path,
                      COALESCE(s.filename,'') AS filename
               FROM sources s LEFT JOIN assets a ON a.sha256=s.sha256""",
            """SELECT r.source_path AS source_path, r.sha256 AS sha256,
                      COALESCE(a.object_path,r.source_path) AS object_path,
                      COALESCE(r.filename,'') AS filename
               FROM repository_index r LEFT JOIN assets a ON a.sha256=r.sha256"""
        ]
        for sql in queries:
            try:
                rows=c.execute(sql).fetchall()
            except Exception:
                continue
            for r in rows:
                src=str(r["source_path"] or "")
                obj=str(r["object_path"] or "")
                if not obj or not os.path.isfile(obj):
                    continue
                base=os.path.basename(src.replace("\\","/")) or str(r["filename"] or "") or os.path.basename(obj)
                try:
                    st=os.stat(obj)
                except OSError:
                    continue
                out.append({
                    "path":obj,
                    "real_path":obj,
                    "basename":base,
                    "stem_key":norm_key(base),
                    "basename_key":norm(base),
                    "source_full_key":norm(src),
                    "size":st.st_size,
                    "mtime":st.st_mtime,
                    "root":"media-transfer-db",
                    "is_symlink":False,
                    "sha_from_filename":str(r["sha256"] or "").casefold(),
                    "db_alias":True,
                })
    finally:
        c.close()
    return out

def build_maps(index):
    exact={}
    stems={}
    by_sha={}
    by_source_full={}
    for e in index.get("files",[]):
        exact.setdefault(e["basename_key"],[]).append(e)
        stems.setdefault(e["stem_key"],[]).append(e)
        sha=e.get("sha_from_filename") or ""
        if sha:
            by_sha.setdefault(sha,[]).append(e)
        sf=e.get("source_full_key") or ""
        if sf:
            by_source_full.setdefault(sf,[]).append(e)
    return exact,stems,by_sha,by_source_full

def score_candidate(e,item):
    p=e["path"]
    score=0
    if "/srv/studiosat/radio-principal/" in p:
        score+=50
    if "/grade/" in p:
        score+=20
    if norm(e["basename"])==norm(item.get("source_basename","")):
        score+=100
    k=norm_key((item.get("artist","")+" "+item.get("title","")).strip())
    if k and e["stem_key"]==k:
        score+=80
    return score

def fuzzy_candidate(item,index):
    targets=[]
    for v in (
        item.get("source_basename",""),
        (item.get("artist","")+" - "+item.get("title","")).strip(" -"),
        item.get("itemtitle",""),
        item.get("title",""),
    ):
        k=norm_key(v)
        if k and k not in targets:
            targets.append(k)
    if not targets:
        return None,0.0,0.0
    scored=[]
    for e in index.get("files",[]):
        ek=e.get("stem_key","")
        if not ek:
            continue
        ratio=max(difflib.SequenceMatcher(None,t,ek).ratio() for t in targets)
        if ratio>=0.72:
            scored.append((ratio,score_candidate(e,item),e))
    if not scored:
        return None,0.0,0.0
    scored.sort(key=lambda x:(-x[0],-x[1],x[2]["path"]))
    best=scored[0]
    second=scored[1][0] if len(scored)>1 else 0.0
    if best[0]>=0.90 or (best[0]>=0.86 and best[0]-second>=0.05):
        return best[2],best[0],second
    return None,best[0],second

def resolve_item(item,maps,index,mmanifest):
    if item["virtual"]:
        item.update({"available":True,"local_path":"","resolution":"virtual","candidates":0})
        return item
    exact,stems,by_sha,by_source_full=maps
    mfull,mbase=mmanifest
    c=[]
    bkey=norm(item.get("source_basename",""))
    skey=norm_key(item.get("source_basename",""))
    srcfull=norm(item.get("source_path",""))

    if srcfull and srcfull in by_source_full:
        c.extend(by_source_full[srcfull])

    if not c and bkey and bkey in exact:
        c.extend(exact[bkey])

    # Manifest SHA bridge: Windows RadioBOSS path -> canonical SHA object on NS1.
    if not c:
        shas=set()
        shas.update(mfull.get(srcfull,set()))
        shas.update(mbase.get(bkey,set()))
        for sha in sorted(shas):
            c.extend(by_sha.get(sha,[]))

    if not c and skey and skey in stems:
        c.extend(stems[skey])

    at_key=norm_key((item.get("artist","")+" "+item.get("title","")).strip())
    if not c and at_key and at_key in stems:
        c.extend(stems[at_key])

    uniq={x["path"]:x for x in c}
    c=list(uniq.values())
    c.sort(key=lambda e:(-score_candidate(e,item),e["path"]))

    if c:
        method="db-source-path" if c[0].get("db_alias") and c[0].get("source_full_key")==srcfull else ("manifest-sha" if any((e.get("sha_from_filename") or "") for e in c) and not (bkey in exact) else "local-exact")
        item.update({
            "available":True,
            "local_path":c[0]["path"],
            "real_path":c[0].get("real_path",c[0]["path"]),
            "resolution":method,
            "candidates":len(c),
            "match_score":1.0,
        })
        return item

    e,best,second=fuzzy_candidate(item,index)
    if e:
        item.update({
            "available":True,
            "local_path":e["path"],
            "real_path":e.get("real_path",e["path"]),
            "resolution":"local-fuzzy",
            "candidates":1,
            "match_score":round(best,4),
            "second_score":round(second,4),
        })
    else:
        item.update({
            "available":False,
            "local_path":"",
            "resolution":"missing",
            "candidates":0,
            "match_score":round(best,4),
            "second_score":round(second,4),
        })
    return item

def find_queue_current(queue,pb):
    current=pb.get("current") or {}
    fn=str(current.get("FILENAME") or current.get("filename") or "")
    pos=pb.get("playlistpos")
    candidates=[]
    if isinstance(pos,int):
        for j in (pos,pos-1,pos+1):
            if 0<=j<len(queue):
                candidates.append(queue[j])
    fnk=norm_key(fn)
    for q in candidates:
        if fnk and norm_key(q.get("source_path"))==fnk:
            return q
    if fnk:
        for q in queue:
            if norm_key(q.get("source_path"))==fnk:
                return q
    if isinstance(pos,int) and 0<=pos<len(queue):
        return queue[pos]
    return None

def find_queue_next(queue,pb,cur_index):
    n=pb.get("next") or {}
    fn=str(n.get("FILENAME") or n.get("filename") or "")
    fnk=norm_key(fn)
    if fnk and cur_index is not None:
        for j in range(cur_index+1,min(len(queue),cur_index+6)):
            if norm_key(queue[j].get("source_path"))==fnk:
                return queue[j]
    if fnk:
        for q in queue:
            if norm_key(q.get("source_path"))==fnk:
                return q
    if cur_index is not None and cur_index+1<len(queue):
        return queue[cur_index+1]
    return None

def build_queue(index):
    tracks,playlist_raw=parse_playlist()
    maps=build_maps(index)
    mmanifest=manifest_maps()
    resolved=[resolve_item(dict(t),maps,index,mmanifest) for t in tracks]
    pb,pb_raw=parse_playback()
    cur=find_queue_current(resolved,pb)
    cur_index=cur["index"] if cur else None
    nxt=find_queue_next(resolved,pb,cur_index)
    for q in resolved:
        q["current"]=bool(cur and q["index"]==cur_index)
        q["next"]=bool(nxt and q["index"]==nxt["index"])
    media=[q for q in resolved if not q["virtual"]]
    missing=[q for q in media if not q["available"]]
    queue={
        "schema":"studiosat.effective-queue.v2",
        "generated_at_utc":datetime.now(timezone.utc).isoformat(),
        "playlist_revision":playlist_raw.get("revision") if isinstance(playlist_raw,dict) else None,
        "track_count":len(resolved),
        "media_count":len(media),
        "virtual_count":sum(1 for q in resolved if q["virtual"]),
        "available_count":sum(1 for q in media if q["available"]),
        "missing_count":len(missing),
        "coverage_pct":round(100*(len(media)-len(missing))/max(1,len(media)),2),
        "playback":{
            "state":pb.get("state"),
            "playlistpos":pb.get("playlistpos"),
            "pos_ms":pb.get("pos_ms"),
            "len_ms":pb.get("len_ms"),
            "timestamp":pb.get("timestamp"),
            "current":pb.get("current"),
            "next":pb.get("next"),
        },
        "current_index":cur_index,
        "current":cur,
        "next":nxt,
        "missing":[
            {
                "index":q["index"],
                "source_path":q["source_path"],
                "artist":q["artist"],
                "title":q["title"]
            }
            for q in missing
        ],
        "queue":resolved,
    }
    atomic_json(QUEUE,queue)
    return queue

def report_check(q):
    idx=load_json(INDEX)
    print(f"LIBRARY_FILES={idx.get('count',0)}")
    print(f"SYMLINK_ALIASES={idx.get('symlink_aliases',0)}")
    print(f"DB_ALIASES={idx.get('db_aliases',0)}")
    print(f"QUEUE_TRACKS={q['track_count']}")
    print(f"MEDIA_COUNT={q['media_count']}")
    print(f"VIRTUAL_COUNT={q['virtual_count']}")
    print(f"AVAILABLE_COUNT={q['available_count']}")
    print(f"MISSING_COUNT={q['missing_count']}")
    print(f"COVERAGE_PCT={q['coverage_pct']}")
    cur=q.get("current") or {}
    nxt=q.get("next") or {}
    print("CURRENT_SOURCE="+str(cur.get("source_path","")))
    print("CURRENT_LOCAL="+str(cur.get("local_path","")))
    print("CURRENT_READY="+("YES" if cur and (cur.get("virtual") or cur.get("available")) else "NO"))
    print("NEXT_SOURCE="+str(nxt.get("source_path","")))
    print("NEXT_LOCAL="+str(nxt.get("local_path","")))
    print("NEXT_READY="+("YES" if nxt and (nxt.get("virtual") or nxt.get("available")) else "NO"))
    return bool(
        cur and (cur.get("virtual") or cur.get("available"))
        and nxt and (nxt.get("virtual") or nxt.get("available"))
    )

def safe_term(p):
    if not p:
        return
    try:
        if p.poll() is None:
            p.terminate()
            p.wait(timeout=2)
    except Exception:
        try:
            p.kill()
        except Exception:
            pass

class Playout:
    def __init__(self):
        self.pub=None
        self.dec=None
        self.sel=selectors.DefaultSelector()
        self.buf=bytearray()
        self.queue=None
        self.index=None
        self.current_index=None
        self.decoder_started_at=0.0
        self.decoder_seek=0.0
        self.last_queue_refresh=0.0
        self.last_index_refresh=0.0
        self.mode="boot"
        self.last_audio=0.0

    def pub_start(self):
        safe_term(self.pub)
        cmd=[
            "/usr/bin/ffmpeg","-hide_banner","-loglevel","warning","-nostdin","-re",
            "-f","s16le","-ar","48000","-ac","2","-i","pipe:0",
            "-c:a","aac","-b:a","128k","-ar","48000","-ac","2",
            "-f","flv",RTMP
        ]
        self.pub=subprocess.Popen(
            cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,bufsize=0
        )
        time.sleep(.3)
        if self.pub.poll() is not None:
            raise RuntimeError("publisher failed")

    def dec_stop(self):
        if self.dec and self.dec.stdout:
            try:
                self.sel.unregister(self.dec.stdout)
            except Exception:
                pass
        safe_term(self.dec)
        self.dec=None
        self.buf.clear()

    def dec_start(self,path,seek=0.0,index=None):
        self.dec_stop()
        cmd=["/usr/bin/ffmpeg","-hide_banner","-loglevel","error","-nostdin","-re"]
        if seek>0:
            cmd+=["-ss",f"{seek:.3f}"]
        cmd += [
            "-i",path,
            "-map","0:a:0","-vn",
            "-ac","2","-ar","48000",
            "-f","s16le","pipe:1"
        ]
        self.dec=subprocess.Popen(
            cmd,stdout=subprocess.PIPE,stdin=subprocess.DEVNULL,bufsize=0
        )
        os.set_blocking(self.dec.stdout.fileno(),False)
        self.sel.register(self.dec.stdout,selectors.EVENT_READ)
        self.current_index=index
        self.decoder_started_at=time.monotonic()
        self.decoder_seek=seek
        log(f"PLAYOUT_DECODER path={path} seek={seek:.3f} index={index}")

    def refresh(self,force=False):
        now=time.monotonic()
        if force or now-self.last_index_refresh>30:
            self.index=scan_library()
            self.last_index_refresh=now
        if force or now-self.last_queue_refresh>1:
            self.queue=build_queue(self.index)
            self.last_queue_refresh=now

    def desired(self):
        self.refresh()
        q=self.queue
        pb=q.get("playback") or {}
        cur=q.get("current")
        age=max(0,time.time()-PLAYBACK.stat().st_mtime)
        if age<=CONTROL_FRESH_SEC and cur:
            self.mode="hot-sync"
            seek=max(0,float(pb.get("pos_ms") or 0)/1000.0 + age)
            return cur,seek,age
        self.mode="autonomous"
        if self.current_index is not None and 0<=self.current_index<len(q["queue"]):
            return q["queue"][self.current_index],None,age
        return cur,0.0,age

    def next_playable(self,after):
        qq=self.queue["queue"]
        for offset in range(1,len(qq)+1):
            q=qq[(after+offset)%len(qq)]
            if q.get("virtual"):
                continue
            if q.get("available") and q.get("local_path"):
                return q
        return None

    def ensure_decoder(self):
        cur,seek,age=self.desired()
        if not cur:
            return
        if cur.get("virtual"):
            return
        if not cur.get("available"):
            return
        target=cur["index"]
        need=self.dec is None or self.dec.poll() is not None or self.current_index!=target
        if not need and self.mode=="hot-sync" and seek is not None:
            local_pos=self.decoder_seek+(time.monotonic()-self.decoder_started_at)
            if abs(local_pos-seek)>3.0:
                need=True
        if need:
            self.dec_start(cur["local_path"],seek or 0.0,target)

    def write_state(self):
        q=self.queue or {}
        cur=None
        if (
            self.current_index is not None
            and q.get("queue")
            and 0<=self.current_index<len(q["queue"])
        ):
            cur=q["queue"][self.current_index]
        atomic_json(STATE,{
            "schema":"studiosat.playout-v5.state.v1",
            "updated_at_utc":datetime.now(timezone.utc).isoformat(),
            "mode":self.mode,
            "current_index":self.current_index,
            "current":cur,
            "queue_coverage_pct":q.get("coverage_pct"),
            "queue_missing_count":q.get("missing_count"),
            "publisher_pid":self.pub.pid if self.pub and self.pub.poll() is None else None,
            "decoder_pid":self.dec.pid if self.dec and self.dec.poll() is None else None,
            "last_audio_age_sec":None if not self.last_audio else round(time.monotonic()-self.last_audio,3),
        })

    def run(self):
        self.refresh(True)
        self.pub_start()
        self.ensure_decoder()
        next_tick=time.monotonic()
        next_state=0.0
        while RUN:
            if self.pub.poll() is not None:
                self.pub_start()
            self.ensure_decoder()
            if self.dec and self.dec.poll() is not None:
                if self.mode=="autonomous" and self.current_index is not None:
                    n=self.next_playable(self.current_index)
                    if n:
                        self.dec_start(n["local_path"],0.0,n["index"])
                else:
                    self.dec_stop()

            if self.dec:
                ev=self.sel.select(timeout=.005)
                if ev:
                    try:
                        data=os.read(self.dec.stdout.fileno(),65536)
                    except (OSError,BlockingIOError):
                        data=b""
                    if data:
                        self.buf.extend(data)
                        if len(self.buf)>CHUNK*20:
                            del self.buf[:-CHUNK*20]
                        self.last_audio=time.monotonic()

            now=time.monotonic()
            if now>=next_tick:
                next_tick+=.02
                if len(self.buf)>=CHUNK:
                    data=bytes(self.buf[:CHUNK])
                    del self.buf[:CHUNK]
                else:
                    data=SILENCE
                try:
                    self.pub.stdin.write(data)
                    self.pub.stdin.flush()
                except (BrokenPipeError,OSError):
                    self.pub_start()
                if now-next_tick>.5:
                    next_tick=now+.02

            if now>=next_state:
                next_state=now+1
                self.write_state()

        self.dec_stop()
        safe_term(self.pub)

def selftest():
    global ROOTS, INDEX, MEDIA_DB
    old_roots=ROOTS
    old_index=INDEX
    old_db=MEDIA_DB
    try:
        with tempfile.TemporaryDirectory(prefix="studiosat-v41-selftest-") as td:
            root=Path(td)/"radio-principal"
            store=Path(td)/"mirror-store"
            grade=root/"grade"/"manha"
            grade.mkdir(parents=True)
            store.mkdir(parents=True)

            target=store/"0123456789abcdef.mp3"
            target.write_bytes(b"not-real-audio-selftest")
            alias=grade/"10 ELIS REGINA - ALÔ ALÔ MARCIANO.mp3"
            alias.symlink_to(target)

            ROOTS=[root,store]
            INDEX=Path(td)/"library-index.json"
            idx=scan_library()
            aliases=[x for x in idx["files"] if x["path"]==str(alias.absolute())]
            assert aliases, "symlink alias path was lost"
            assert aliases[0]["basename"].startswith("10 ELIS REGINA"), "alias basename lost"

            t=ET.Element("TRACK")
            c=ET.SubElement(t,"FILENAME")
            c.text=r"C:\RadioStudioSatWeb\Seg_Sex_0730_1200\10 ELIS REGINA - ALO ALO MARCIANO.mp3"
            assert track_attr(t,"FILENAME").startswith("C:"), "child-text parser failed"

            item={
                "virtual":False,
                "source_basename":"10 ELIS REGINA - ALO ALO MARCIANO.mp3",
                "artist":"Elis Regina",
                "title":"Alô Alô Marciano",
                "itemtitle":"Elis Regina - Alô Alô Marciano",
            }
            resolved=resolve_item(dict(item),build_maps(idx),idx,({},{}))
            assert resolved["available"], "exact normalized alias resolution failed"
            assert resolved["local_path"]==str(alias.absolute()), "wrong alias selected"

            fuzzy=dict(item)
            fuzzy["source_basename"]="10 ELIS REGINA ALO-ALO MARCIANO (RADIO).mp3"
            fuzzy["title"]="Alo Alo Marciano"
            resolved2=resolve_item(fuzzy,build_maps(idx),idx,({},{}))
            assert resolved2["available"], "fuzzy resolution failed"

            # Manifest-only resolution: no human alias, only SHA object.
            sha="a"*64
            shaobj=store/(sha+".mp3")
            shaobj.write_bytes(b"manifest-object")
            idx2=scan_library()
            man_item=dict(item)
            man_item["source_basename"]="99 UNIQUE MANIFEST SONG.mp3"
            man_item["source_path"]=r"C:\RadioStudioSatWeb\Seg_Sex_0730_1200\99 UNIQUE MANIFEST SONG.mp3"
            mr=resolve_item(
                man_item,
                build_maps(idx2),
                idx2,
                (
                    {norm(man_item["source_path"]):{sha}},
                    {norm(man_item["source_basename"]):{sha}}
                )
            )
            assert mr["available"], "manifest SHA resolution failed"
            assert mr["resolution"]=="manifest-sha", "manifest SHA method not reported"

            # Exact source_path resolution through existing media-transfer SQLite schema.
            dbp=Path(td)/"index.sqlite3"
            import sqlite3 as _sqlite3
            dc=_sqlite3.connect(dbp)
            dc.executescript("""
            CREATE TABLE assets(sha256 TEXT PRIMARY KEY, object_path TEXT NOT NULL, filename TEXT NOT NULL, size_bytes INTEGER NOT NULL, extension TEXT NOT NULL, media_class TEXT NOT NULL, verified_at_utc TEXT NOT NULL);
            CREATE TABLE sources(source_path TEXT PRIMARY KEY, sha256 TEXT NOT NULL, filename TEXT NOT NULL, media_class TEXT NOT NULL, updated_at_utc TEXT NOT NULL);
            CREATE TABLE repository_index(source_path TEXT PRIMARY KEY, sha256 TEXT NOT NULL, filename TEXT NOT NULL, size_bytes INTEGER NOT NULL, extension TEXT NOT NULL, mtime_ns INTEGER NOT NULL, indexed_at_utc TEXT NOT NULL);
            """)
            dbsha="b"*64
            dbobj=store/(dbsha+".mp3")
            dbobj.write_bytes(b"db-object")
            dbsrc=r"C:\RadioStudioSatWeb\Seg_Sex_0730_1200\77 DB SONG.mp3"
            dc.execute("INSERT INTO assets VALUES(?,?,?,?,?,?,?)",(dbsha,str(dbobj),"77 DB SONG.mp3",dbobj.stat().st_size,".mp3","MUSIC","now"))
            dc.execute("INSERT INTO sources VALUES(?,?,?,?,?)",(dbsrc,dbsha,"77 DB SONG.mp3","MUSIC","now"))
            dc.commit();dc.close()
            MEDIA_DB=dbp
            idx3=scan_library()
            db_item=dict(item)
            db_item["source_path"]=dbsrc
            db_item["source_basename"]="77 DB SONG.mp3"
            db_item["artist"]="DB"
            db_item["title"]="SONG"
            dr=resolve_item(db_item,build_maps(idx3),idx3,({},{}))
            assert dr["available"], "DB source_path resolution failed"
            assert dr["resolution"]=="db-source-path", "DB resolver method not reported"
            assert dr["local_path"]==str(dbobj), "DB resolver wrong object path"

            virt={
                "virtual":True,
                "source_basename":"saytime=HoraCertaSegSextManha",
                "artist":"","title":"","itemtitle":""
            }
            rv=resolve_item(virt,build_maps(idx),idx,({},{}))
            assert rv["available"] and rv["resolution"]=="virtual", "virtual item handling failed"

        print("SELFTEST=PASS")
        return 0
    except Exception as exc:
        print("SELFTEST=FAIL")
        print("SELFTEST_ERROR="+repr(exc))
        return 90
    finally:
        ROOTS=old_roots
        INDEX=old_index
        MEDIA_DB=old_db

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--check",action="store_true")
    ap.add_argument("--selftest",action="store_true")
    args=ap.parse_args()
    if args.selftest:
        sys.exit(selftest())
    BASE.mkdir(parents=True,exist_ok=True)
    idx=scan_library()
    q=build_queue(idx)
    if args.check:
        ok=report_check(q)
        sys.exit(0 if ok else 20)
    sh=Playout()
    sh.index=idx
    sh.queue=q
    sh.last_index_refresh=time.monotonic()
    sh.last_queue_refresh=time.monotonic()
    sh.run()

def stop(sig,frame):
    global RUN
    RUN=False

signal.signal(signal.SIGTERM,stop)
signal.signal(signal.SIGINT,stop)

if __name__=="__main__":
    main()
