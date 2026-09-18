#!/usr/bin/env python3
import os,json,time,hashlib,shutil,tempfile,unicodedata
from pathlib import Path

ROOT=Path("/srv/studiosat/radio-principal")
GRADE=ROOT/"grade"
STATE=ROOT/"estado"
CURRENT_MAP=Path("/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json")
PLAYBACK=Path("/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json")
GENERATIONS=Path("/var/lib/studiosat/radio-v2/stations/radioprincipal/generations")
PROGRAMS=("manha","tarde","noite")

def norm(s):
    return unicodedata.normalize("NFKD",str(s or "")).encode("ascii","ignore").decode().casefold()
def program(ref):
    s=norm(ref)
    if "manha" in s:return "manha"
    if "tarde" in s:return "tarde"
    if "noite" in s:return "noite"
    return None
def safe_name(x):
    return os.path.basename(str(x or "").replace("\\","/")).strip()
def load(p):
    with open(p,encoding="utf-8") as f:return json.load(f)
def sha(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
    return h.hexdigest()
def atomic(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+".",suffix=".tmp",dir=str(path.parent))
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(obj,f,ensure_ascii=False,indent=2);f.flush();os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        try:os.unlink(tmp)
        except FileNotFoundError:pass
def ensure():
    for p in [ROOT,GRADE,STATE,ROOT/"elementos"/"comerciais",ROOT/"elementos"/"vinhetas",ROOT/"elementos"/"hora-certa",ROOT/"elementos"/"temperatura",ROOT/"operacao"/"importar",ROOT/"operacao"/"quarentena"]:
        p.mkdir(parents=True,exist_ok=True)
        try:os.chmod(p,0o2775)
        except PermissionError:pass
    for p in PROGRAMS:
        (GRADE/p).mkdir(parents=True,exist_ok=True)
        try:os.chmod(GRADE/p,0o2775)
        except PermissionError:pass

def link_track(t,origin):
    ref=t.get("source_windows") or ""
    pr=program(ref)
    if not pr:return None
    src=t.get("path") or ""
    if not src or not os.path.isfile(src):return {"program":pr,"status":"missing","ref":ref,"origin":origin}
    fn=safe_name(t.get("filename") or ref)
    if not fn:return None
    dst=GRADE/pr/fn
    expected=str(t.get("sha256") or "").lower()
    if dst.exists():
        if expected:
            try:
                if sha(dst)==expected:return {"program":pr,"status":"exists","file":fn,"origin":origin}
            except Exception:pass
        return {"program":pr,"status":"conflict","file":fn,"origin":origin}
    try:os.link(src,dst)
    except OSError:shutil.copy2(src,dst)
    try:os.chmod(dst,0o664)
    except PermissionError:pass
    return {"program":pr,"status":"linked","file":fn,"origin":origin}

def active_program():
    try:
        d=load(PLAYBACK);q=d.get("payload",{});x=q.get("data",q)
        c=x.get("current") or {};n=x.get("next") or {}
        cref=c.get("FILENAME") or (c.get("TAG") or {}).get("FN") or ""
        nref=n.get("FILENAME") or (n.get("TAG") or {}).get("FN") or ""
        return program(cref) or program(nref),{"state":x.get("state"),"playlistpos":x.get("playlistpos"),"pos_ms":x.get("pos_ms"),"current_ref":cref,"next_ref":nref}
    except Exception as e:return None,{"error":repr(e)}

def set_current(pr):
    if not pr:return
    l=GRADE/"ATUAL";tmp=GRADE/".ATUAL.new"
    try:
        if tmp.exists() or tmp.is_symlink():tmp.unlink()
    except FileNotFoundError:pass
    os.symlink(str(GRADE/pr),str(tmp));os.replace(tmp,l)

def maps(include_history=False):
    out=[]
    if CURRENT_MAP.is_file():out.append(("current",CURRENT_MAP))
    if include_history and GENERATIONS.is_dir():
        for p in sorted(GENERATIONS.glob("*/media-map.json"),key=lambda x:x.stat().st_mtime,reverse=True)[:500]:
            out.append((p.parent.name,p))
    return out

def run(include_history=False):
    ensure();events=[];seen=set()
    for origin,p in maps(include_history):
        try:m=load(p)
        except Exception:continue
        for t in m.get("tracks") or []:
            key=(str(t.get("sha256") or ""),str(t.get("source_windows") or ""))
            if key in seen:continue
            seen.add(key)
            r=link_track(t,origin)
            if r:events.append(r)
    pr,pb=active_program();set_current(pr)
    counts={}
    for p in PROGRAMS:
        files=[x for x in (GRADE/p).iterdir() if x.is_file() and x.suffix.lower() in (".mp3",".wav",".flac",".m4a",".aac",".ogg",".opus")]
        counts[p]=len(files)
    status={"updated_at_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"active_program":pr,"playback":pb,"counts":counts,
            "linked":sum(e["status"]=="linked" for e in events),"conflicts":[e for e in events if e["status"]=="conflict"],
            "missing":[e for e in events if e["status"]=="missing"],"history_seed":include_history}
    atomic(STATE/"repositorios.json",status)
    print(json.dumps(status,ensure_ascii=False))
if __name__=="__main__":
    import sys
    run("--history" in sys.argv)
