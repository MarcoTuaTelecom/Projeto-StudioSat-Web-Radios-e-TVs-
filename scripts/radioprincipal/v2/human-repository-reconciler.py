#!/usr/bin/env python3
# C22 - Studio Sat Radio Principal human repository reconciler
# Reads media-transfer DB + current legacy map and populates /srv/studiosat/radio-principal/grade/*
# Does not touch selector/shadow/MediaMTX/Nginx/Harbor.
import os, sqlite3, json, time, hashlib, shutil, tempfile, unicodedata
from pathlib import Path

ROOT=Path("/srv/studiosat/radio-principal")
GRADE=ROOT/"grade"
STATE=ROOT/"estado"
DB=Path("/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3")
MAP=Path("/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json")
PROGRAMS=("manha","tarde","noite")
AUDIO_EXT={".mp3",".wav",".flac",".m4a",".aac",".ogg",".opus"}

def norm(s):
    return unicodedata.normalize("NFKD",str(s or "")).encode("ascii","ignore").decode().casefold()
def detect_program(ref):
    s=norm(ref)
    if "manha" in s:return "manha"
    if "tarde" in s:return "tarde"
    if "noite" in s:return "noite"
    return None
def sha256(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
    return h.hexdigest()
def atomic_json(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+".",suffix=".tmp",dir=str(path.parent))
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(obj,f,ensure_ascii=False,indent=2); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        try:os.unlink(tmp)
        except FileNotFoundError:pass
def ensure():
    for p in PROGRAMS:
        d=GRADE/p; d.mkdir(parents=True,exist_ok=True)
        try:os.chmod(d,0o2775)
        except PermissionError:pass
    STATE.mkdir(parents=True,exist_ok=True)
def safe_filename(x):
    return os.path.basename(str(x or "").replace("\\","/")).strip()
def materialize(program, filename, expected_sha, object_path, source_path, source):
    if not program or not filename or not object_path or not os.path.isfile(object_path):
        return {"status":"missing_source","program":program,"filename":filename,"source_path":source_path,"source":source}
    dst=GRADE/program/filename
    if dst.exists():
        try:
            got=sha256(dst)
        except Exception as e:
            return {"status":"error","program":program,"filename":filename,"error":repr(e),"source":source}
        if expected_sha and got.lower()==expected_sha.lower():
            return {"status":"exists","program":program,"filename":filename,"source_path":source_path,"source":source}
        return {"status":"conflict","program":program,"filename":filename,"existing_sha256":got,"expected_sha256":expected_sha,"source_path":source_path,"source":source}
    try:
        os.link(object_path,dst)
        mode="hardlink"
    except OSError:
        shutil.copy2(object_path,dst); mode="copy"
    try: os.chmod(dst,0o664)
    except PermissionError: pass
    return {"status":"linked","mode":mode,"program":program,"filename":filename,"source_path":source_path,"source":source}

def db_rows():
    if not DB.is_file(): return []
    c=sqlite3.connect("file:"+str(DB)+"?mode=ro",uri=True,timeout=3)
    c.row_factory=sqlite3.Row
    rows=[]
    try:
        # source_path mapping already confirmed by media-transfer DB
        for r in c.execute("""
            select s.source_path,s.sha256,s.filename,a.object_path,'sources' as origin
            from sources s join assets a on a.sha256=s.sha256
            where a.object_path is not null
        """):
            rows.append(dict(r))
        # wider indexed repository coverage
        for r in c.execute("""
            select r.source_path,r.sha256,r.filename,a.object_path,'repository_index' as origin
            from repository_index r join assets a on a.sha256=r.sha256
            where a.object_path is not null
        """):
            rows.append(dict(r))
    finally:
        c.close()
    return rows

def map_rows():
    out=[]
    if not MAP.is_file(): return out
    try:m=json.load(open(MAP,encoding="utf-8"))
    except Exception:return out
    for t in m.get("tracks") or []:
        out.append({
          "source_path":t.get("source_windows") or "",
          "sha256":t.get("sha256") or "",
          "filename":t.get("filename") or safe_filename(t.get("source_windows")),
          "object_path":t.get("path") or "",
          "origin":"media_map"
        })
    return out

def manual_counts():
    d={}
    for p in PROGRAMS:
        d[p]=sum(1 for x in (GRADE/p).iterdir() if x.is_file() and x.suffix.lower() in AUDIO_EXT)
    return d

def run():
    ensure()
    rows=db_rows()+map_rows()
    seen=set(); results=[]
    for r in rows:
        source_path=str(r.get("source_path") or "")
        pr=detect_program(source_path)
        if not pr: continue
        fn=safe_filename(r.get("filename") or source_path)
        key=(pr,str(r.get("sha256") or "").lower(),fn.casefold())
        if key in seen: continue
        seen.add(key)
        results.append(materialize(pr,fn,str(r.get("sha256") or "").lower(),str(r.get("object_path") or ""),source_path,str(r.get("origin") or "")))
    counts=manual_counts()
    status={
      "schema":"studiosat.human-repo-reconcile.v1",
      "updated_at_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
      "db_rows":len(rows),
      "candidates":len(seen),
      "counts":counts,
      "linked":sum(x["status"]=="linked" for x in results),
      "exists":sum(x["status"]=="exists" for x in results),
      "conflicts":[x for x in results if x["status"]=="conflict"],
      "missing_source":[x for x in results if x["status"]=="missing_source"],
      "errors":[x for x in results if x["status"]=="error"],
    }
    atomic_json(STATE/"repositorio-sync.json",status)
    print(json.dumps(status,ensure_ascii=False))
if __name__=="__main__":
    run()
