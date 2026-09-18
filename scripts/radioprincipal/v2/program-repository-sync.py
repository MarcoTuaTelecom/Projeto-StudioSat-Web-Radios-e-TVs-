#!/usr/bin/env python3
# Studio Sat Rádio Principal V2 - Program Repository Sync
# Safety: writes only /srv/tpsmedia/repository/channels/radioprincipal/programacoes
#         and its own status under /var/lib/studiosat/radio-v2-next/radioprincipal.
# It does NOT touch selector, shadow, MediaMTX, Nginx, Harbor or public paths.
import os, sys, json, time, hashlib, shutil, tempfile, unicodedata
from pathlib import Path

MAP=Path(os.environ.get("SS_MAP","/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json"))
PLAYBACK=Path(os.environ.get("SS_PLAYBACK","/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json"))
BASE=Path(os.environ.get("SS_PROGRAM_BASE","/srv/tpsmedia/repository/channels/radioprincipal/programacoes"))
STATE=Path(os.environ.get("SS_STATE","/var/lib/studiosat/radio-v2-next/radioprincipal/program-repositories"))
INTERVAL=float(os.environ.get("SS_INTERVAL","5"))

PROGRAMS=("manha","tarde","noite")

def norm(s):
    return unicodedata.normalize("NFKD",str(s or "")).encode("ascii","ignore").decode().casefold()

def program_from_ref(ref):
    s=norm(ref)
    if "manha" in s:
        return "manha"
    if "tarde" in s:
        return "tarde"
    if "noite" in s:
        return "noite"
    return None

def atomic_json(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+".",suffix=".tmp",dir=str(path.parent))
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(obj,f,ensure_ascii=False,indent=2)
            f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        try: os.unlink(tmp)
        except FileNotFoundError: pass

def atomic_text(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+".",suffix=".tmp",dir=str(path.parent))
    try:
        with os.fdopen(fd,"w",encoding="utf-8",newline="\n") as f:
            f.write(text); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        try: os.unlink(tmp)
        except FileNotFoundError: pass

def sha256_file(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):
            h.update(b)
    return h.hexdigest()

def ensure_dirs():
    BASE.mkdir(parents=True,exist_ok=True)
    STATE.mkdir(parents=True,exist_ok=True)
    for p in PROGRAMS:
        d=BASE/p
        d.mkdir(parents=True,exist_ok=True)
        try:
            os.chmod(d,0o2775)
        except PermissionError:
            pass

def load(path):
    with open(path,encoding="utf-8") as f:return json.load(f)

def playback_ref(doc):
    q=doc.get("payload",{}) if isinstance(doc,dict) else {}
    d=q.get("data",q) if isinstance(q,dict) else {}
    c=d.get("current") if isinstance(d.get("current"),dict) else {}
    n=d.get("next") if isinstance(d.get("next"),dict) else {}
    return {
        "state":d.get("state"),"playlistpos":d.get("playlistpos"),
        "pos_ms":d.get("pos_ms"),"len_ms":d.get("len_ms"),
        "current_ref":c.get("FILENAME") or (c.get("TAG") or {}).get("FN") or "",
        "next_ref":n.get("FILENAME") or (n.get("TAG") or {}).get("FN") or "",
        "current_title":c.get("ITEMTITLE") or c.get("CASTTITLE") or c.get("TITLE") or "",
        "next_title":n.get("ITEMTITLE") or n.get("CASTTITLE") or n.get("TITLE") or "",
    }

def safe_name(name):
    name=os.path.basename(str(name or "").replace("\\","/")).strip()
    return name or None

def materialize_program(program, media_map, pb):
    d=BASE/program
    tracks=media_map.get("tracks") or []
    selected=[]
    linked=0
    conflicts=[]
    unavailable=[]

    for t in tracks:
        srcwin=t.get("source_windows") or ""
        # Only copy tracks explicitly belonging to this program.
        if program_from_ref(srcwin) != program:
            continue
        fn=safe_name(t.get("filename") or srcwin)
        src=t.get("path") or ""
        sha=str(t.get("sha256") or "").lower()
        item={
            "index":t.get("index"),"filename":fn,"sha256":sha,
            "source_windows":srcwin,"source_store":src,
            "artist":t.get("artist"),"title":t.get("title"),
            "available":bool(t.get("available")) and bool(src) and os.path.isfile(src),
        }
        selected.append(item)
        if not item["available"] or not fn:
            unavailable.append(item)
            continue

        dst=d/fn
        if dst.exists():
            try:
                if sha and sha256_file(dst)==sha:
                    continue
            except Exception:
                pass
            conflicts.append({"filename":fn,"expected_sha256":sha,"existing":str(dst)})
            continue

        try:
            os.link(src,dst)
        except OSError:
            shutil.copy2(src,dst)
        try: os.chmod(dst,0o664)
        except PermissionError: pass
        linked+=1

    m3u="#EXTM3U\n" + "".join(f"{x['filename']}\n" for x in selected if x.get("available") and x.get("filename"))
    atomic_text(d/"playlist.current.m3u8",m3u)
    atomic_json(d/"manifest.current.json",{
        "schema":"studiosat.program-repository.v1",
        "program":program,
        "generated_at_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
        "map_generation":media_map.get("generation"),
        "playback":pb,
        "tracks":selected,
        "linked_this_run":linked,
        "conflicts":conflicts,
        "unavailable":unavailable,
    })
    return {"program":program,"tracks":len(selected),"linked":linked,"conflicts":len(conflicts),"unavailable":len(unavailable)}

def update_current_symlink(program):
    if not program:return
    link=BASE/"atual"
    tmp=BASE/".atual.new"
    target=BASE/program
    try:
        if tmp.exists() or tmp.is_symlink(): tmp.unlink()
    except FileNotFoundError: pass
    os.symlink(str(target),str(tmp))
    os.replace(str(tmp),str(link))

def once():
    ensure_dirs()
    if not MAP.is_file() or not PLAYBACK.is_file():
        raise RuntimeError("media-map/playback ausente")
    mm=load(MAP); pb=playback_ref(load(PLAYBACK))
    program=program_from_ref(pb.get("current_ref")) or program_from_ref(pb.get("next_ref"))
    results=[]
    # Keep every known program refreshed from the current map, if entries for it exist.
    for p in PROGRAMS:
        results.append(materialize_program(p,mm,pb))
    if program:
        update_current_symlink(program)
    status={
        "schema":"studiosat.program-repository-status.v1",
        "updated_at_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
        "active_program":program,
        "current_ref":pb.get("current_ref"),
        "next_ref":pb.get("next_ref"),
        "playlistpos":pb.get("playlistpos"),
        "pos_ms":pb.get("pos_ms"),
        "map_generation":mm.get("generation"),
        "map_tracks":len(mm.get("tracks") or []),
        "map_available":mm.get("available_count"),
        "map_missing":mm.get("missing_count"),
        "repositories":results,
    }
    atomic_json(STATE/"status.json",status)
    print("PROGRAM_REPO_SYNC=OK ACTIVE=%s MAP=%s TRACKS=%s AVAILABLE=%s MISSING=%s" % (
        program,mm.get("generation"),len(mm.get("tracks") or []),mm.get("available_count"),mm.get("missing_count")
    ),flush=True)
    for x in results:
        print("REPO=%s TRACKS=%s LINKED=%s CONFLICTS=%s UNAVAILABLE=%s" % (
            x["program"],x["tracks"],x["linked"],x["conflicts"],x["unavailable"]
        ),flush=True)

if __name__=="__main__":
    watch="--watch" in sys.argv
    while True:
        try:
            once()
        except Exception as e:
            print("PROGRAM_REPO_SYNC=ERROR %r"%e,flush=True)
        if not watch: break
        time.sleep(INTERVAL)
