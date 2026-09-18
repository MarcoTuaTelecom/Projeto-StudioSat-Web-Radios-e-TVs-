#!/usr/bin/env python3
import os, json, time, sqlite3, subprocess, signal, unicodedata, xml.etree.ElementTree as ET
from pathlib import Path

SYNC=Path("/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current")
PLAYLIST=SYNC/"playlist.json"
PLAYBACK=SYNC/"playback.json"
DB=Path("/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3")
HUMAN=Path("/srv/studiosat/radio-principal/grade")
STATE=Path("/srv/studiosat/radio-principal/estado")
STREAM=os.environ.get("SS_STREAM","rtmp://127.0.0.1:1935/radioprincipal-v2-shadow-hotfix")
POLL=float(os.environ.get("SS_POLL","0.25"))
STALE=float(os.environ.get("SS_STALE","10"))
MAX_DRIFT=float(os.environ.get("SS_MAX_DRIFT","4"))
PCM_RATE=48000
PCM_CHANNELS=2
PCM_BPS=PCM_RATE*PCM_CHANNELS*2
AUDIO_EXT={".mp3",".wav",".flac",".m4a",".aac",".ogg",".opus"}

stop=False
def sig(*_):
    global stop
    stop=True
signal.signal(signal.SIGTERM,sig)
signal.signal(signal.SIGINT,sig)

def norm(s):
    return unicodedata.normalize("NFKC",str(s or "")).replace("\\","/").casefold().strip()

def basename(s):
    return os.path.basename(str(s or "").replace("\\","/")).strip()

def is_virtual(ref):
    s=str(ref or "").strip()
    if not s: return True
    if s.casefold().startswith("saytime="): return True
    return Path(s.replace("\\","/")).suffix.lower() not in AUDIO_EXT

def program_from_ref(ref):
    s=unicodedata.normalize("NFKD",str(ref or "")).encode("ascii","ignore").decode().casefold()
    if "manha" in s or "0730_1200" in s or "0730as1200" in s: return "manha"
    if "tarde" in s: return "tarde"
    if "noite" in s: return "noite"
    return None

def load_json(path):
    with open(path,encoding="utf-8") as f:
        return json.load(f)

def payload_data(doc):
    q=doc.get("payload",{}) if isinstance(doc,dict) else {}
    return q.get("data",q) if isinstance(q,dict) else {}

def path_value(d):
    if not isinstance(d,dict): return ""
    for k in ("FILENAME","filename","FILE","file","FN","fn","PATH","path","SOURCE_PATH","source_path","source"):
        v=d.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
    tag=d.get("TAG")
    if isinstance(tag,dict):
        for k in ("FN","FILENAME","PATH"):
            v=tag.get(k)
            if isinstance(v,str) and v.strip(): return v.strip()
    return ""

def find_xml(obj,out):
    if isinstance(obj,str) and "<Playlist" in obj:
        out.append(obj)
    elif isinstance(obj,dict):
        for v in obj.values(): find_xml(v,out)
    elif isinstance(obj,list):
        for v in obj: find_xml(v,out)

def parse_playlist(doc):
    xmls=[]
    find_xml(doc,xmls)
    if xmls:
        root=ET.fromstring(max(xmls,key=len))
        items=[]
        for i,t in enumerate(root.findall(".//TRACK")):
            a={str(k):str(v) for k,v in t.attrib.items()}
            for c in list(t):
                if c.tag not in a:
                    a[c.tag]=c.text or ""
            ref=path_value(a)
            items.append({"index":i,"ref":ref,"virtual":is_virtual(ref),"raw":a})
        return items
    candidates=[]
    def walk(x):
        if isinstance(x,list) and x and all(isinstance(z,dict) for z in x):
            score=sum(bool(path_value(z)) for z in x)
            if score: candidates.append((score,len(x),x))
        elif isinstance(x,dict):
            for v in x.values(): walk(v)
    walk(payload_data(doc))
    if not candidates: return []
    _,_,lst=max(candidates,key=lambda x:(x[0],x[1]))
    return [{"index":i,"ref":path_value(z),"virtual":is_virtual(path_value(z)),"raw":z} for i,z in enumerate(lst)]

def playback(doc):
    d=payload_data(doc)
    d=d if isinstance(d,dict) else {}
    c=d.get("current") if isinstance(d.get("current"),dict) else {}
    n=d.get("next") if isinstance(d.get("next"),dict) else {}
    return {
        "state":d.get("state"),
        "playlistpos":d.get("playlistpos"),
        "pos_ms":d.get("pos_ms") or 0,
        "len_ms":d.get("len_ms") or 0,
        "current_ref":path_value(c),
        "next_ref":path_value(n),
        "current_title":c.get("ITEMTITLE") or c.get("CASTTITLE") or c.get("TITLE") or "",
        "next_title":n.get("ITEMTITLE") or n.get("CASTTITLE") or n.get("TITLE") or "",
        "age":max(0.0,time.time()-PLAYBACK.stat().st_mtime)
    }

def db_maps():
    by_path={}
    by_base={}
    if not DB.is_file(): return by_path,by_base
    c=sqlite3.connect("file:"+str(DB)+"?mode=ro",uri=True,timeout=3)
    c.row_factory=sqlite3.Row
    try:
        for table in ("sources","repository_index"):
            try:
                rows=c.execute(f"""select x.source_path,x.sha256,x.filename,a.object_path
                                   from {table} x join assets a on a.sha256=x.sha256
                                   where a.object_path is not null""")
            except sqlite3.Error:
                continue
            for r in rows:
                p=str(r["object_path"] or "")
                if not p or not os.path.isfile(p): continue
                ref=str(r["source_path"] or "")
                by_path.setdefault(norm(ref),p)
                b=norm(r["filename"] or basename(ref))
                if b: by_base.setdefault(b,[]).append(p)
    finally:
        c.close()
    return by_path,by_base

def resolve(ref,maps):
    by_path,by_base=maps
    p=by_path.get(norm(ref))
    if p and os.path.isfile(p): return p
    b=norm(basename(ref))
    cand=[]
    for x in by_base.get(b,[]):
        if os.path.isfile(x) and x not in cand: cand.append(x)
    if len(cand)==1: return cand[0]
    pr=program_from_ref(ref)
    if pr:
        d=HUMAN/pr
        direct=d/basename(ref)
        if direct.is_file(): return str(direct)
        if d.is_dir():
            matches=[str(x) for x in d.iterdir() if x.is_file() and norm(x.name)==b]
            if len(matches)==1:return matches[0]
    return None

def select_index(items,pb):
    try:
        pos=int(pb.get("playlistpos"))
        if 0 <= pos < len(items) and norm(items[pos].get("ref"))==norm(pb.get("current_ref")):
            return pos
    except Exception:
        pass
    nr=norm(pb.get("current_ref"))
    exact=[x["index"] for x in items if nr and norm(x.get("ref"))==nr]
    if len(exact)==1:return exact[0]
    b=norm(basename(pb.get("current_ref")))
    bybase=[x["index"] for x in items if b and norm(basename(x.get("ref")))==b]
    return bybase[0] if len(bybase)==1 else None

def decoder(path,offset):
    return subprocess.Popen([
        "/usr/bin/ffmpeg","-hide_banner","-loglevel","error","-nostdin",
        "-ss",f"{max(0.0,offset):.3f}","-i",str(path),"-vn",
        "-f","s16le","-ar",str(PCM_RATE),"-ac",str(PCM_CHANNELS),"pipe:1"
    ],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)

def publisher():
    return subprocess.Popen([
        "/usr/bin/ffmpeg","-hide_banner","-loglevel","warning","-nostdin","-re",
        "-f","s16le","-ar",str(PCM_RATE),"-ac",str(PCM_CHANNELS),"-i","pipe:0",
        "-c:a","aac","-b:a","128k","-ar","48000","-ac","2","-f","flv",STREAM
    ],stdin=subprocess.PIPE,stderr=subprocess.DEVNULL)

def write_status(obj):
    STATE.mkdir(parents=True,exist_ok=True)
    tmp=STATE/".ordered-shadow-status.tmp"
    dst=STATE/"ordered-shadow-status.json"
    with open(tmp,"w",encoding="utf-8") as f:
        json.dump(obj,f,ensure_ascii=False,indent=2)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp,dst)

def next_physical(items,start,maps):
    skipped=[]
    for i in range(start,len(items)):
        it=items[i]
        if it["virtual"]:
            skipped.append({"index":i,"ref":it.get("ref"),"reason":"virtual"})
            continue
        p=resolve(it.get("ref"),maps)
        if p:return i,p,skipped
        skipped.append({"index":i,"ref":it.get("ref"),"reason":"missing"})
    return None,None,skipped

pub=publisher()
dec=None
maps=db_maps()
maps_refreshed=time.monotonic()
queue=[]
queue_mtime=0
current_idx=None
current_path=None
started_offset=0.0
started_mono=0.0
have_checkpoint=False

while not stop:
    try:
        mt=PLAYLIST.stat().st_mtime
        if mt!=queue_mtime:
            queue=parse_playlist(load_json(PLAYLIST))
            queue_mtime=mt
            print(f"ORDERED_QUEUE_RELOAD items={len(queue)}",flush=True)
    except Exception as e:
        write_status({"status":"PLAYLIST_UNAVAILABLE","error":repr(e),"stream":STREAM,"updated_at":time.time()})
        time.sleep(POLL); continue

    if time.monotonic()-maps_refreshed>5:
        maps=db_maps();maps_refreshed=time.monotonic()

    try:
        pb=playback(load_json(PLAYBACK))
    except Exception:
        pb=None

    if pb and pb["age"]<=STALE and queue:
        idx=select_index(queue,pb)
        if idx is None:
            write_status({"status":"CURRENT_NOT_IN_QUEUE","playback":pb,"stream":STREAM,"updated_at":time.time()})
            time.sleep(POLL);continue
        path=resolve(queue[idx].get("ref"),maps)
        if not path:
            write_status({"status":"CURRENT_MISSING","index":idx,"ref":queue[idx].get("ref"),"playback":pb,"stream":STREAM,"updated_at":time.time()})
            time.sleep(POLL);continue
        target=max(0.0,float(pb.get("pos_ms") or 0)/1000.0 + float(pb.get("age") or 0))
        predicted=started_offset+(time.monotonic()-started_mono) if current_idx==idx and current_path==path else -999
        if dec is None or dec.poll() is not None or current_idx!=idx or current_path!=path or abs(predicted-target)>MAX_DRIFT:
            if dec:
                try:dec.kill();dec.wait(timeout=1)
                except Exception:pass
            dec=decoder(path,target)
            current_idx=idx;current_path=path;started_offset=target;started_mono=time.monotonic();have_checkpoint=True
            print(f"ORDERED_SYNC index={idx} offset={target:.3f} ref={queue[idx].get('ref')}",flush=True)
    elif not have_checkpoint:
        write_status({"status":"WAITING_FOR_FRESH_PLAYBACK","playback":pb,"stream":STREAM,"updated_at":time.time()})
        time.sleep(POLL);continue

    if dec is None:
        time.sleep(POLL);continue

    chunk=dec.stdout.read(PCM_BPS//4) if dec.stdout else b""
    if chunk:
        try:
            if pub.poll() is not None: pub=publisher()
            pub.stdin.write(chunk)
        except Exception:
            try:pub.kill()
            except Exception:pass
            pub=publisher()
        write_status({
            "status":"FOLLOWING" if pb and pb["age"]<=STALE else "CONTINUING_FROM_CHECKPOINT",
            "stream":STREAM,"queue_items":len(queue),"index":current_idx,
            "ref":queue[current_idx].get("ref") if current_idx is not None and current_idx<len(queue) else None,
            "path":current_path,"program":program_from_ref(queue[current_idx].get("ref")) if current_idx is not None and current_idx<len(queue) else None,
            "playback":pb,"updated_at":time.time()
        })
        continue

    if dec.poll() is not None and current_idx is not None:
        ni,np,skipped=next_physical(queue,current_idx+1,maps)
        for x in skipped:
            print(f"ORDERED_SKIP index={x['index']} reason={x['reason']} ref={x['ref']}",flush=True)
        if ni is None:
            write_status({"status":"END_OF_QUEUE","index":current_idx,"stream":STREAM,"updated_at":time.time()})
            time.sleep(POLL);continue
        dec=decoder(np,0.0)
        current_idx=ni;current_path=np;started_offset=0.0;started_mono=time.monotonic()
        print(f"ORDERED_CONTINUE index={ni} ref={queue[ni].get('ref')}",flush=True)

try:
    if dec: dec.kill()
except Exception: pass
try:
    if pub.stdin: pub.stdin.close()
except Exception: pass
try: pub.terminate()
except Exception: pass
