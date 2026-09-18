#!/usr/bin/env python3
# C23 - isolated RadioPrincipal V2 shadow driven by RadioBOSS playback.
# Publishes ONLY to radioprincipal-v2-shadow.
import os,time,json,subprocess,signal,unicodedata
from pathlib import Path

ROOT=Path("/srv/studiosat/radio-principal")
GRADE=ROOT/"grade"
STATE=ROOT/"estado"
PB=Path("/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json")
STREAM=os.environ.get("SS_STREAM","rtmp://127.0.0.1:1935/radioprincipal-v2-shadow")
POLL=float(os.environ.get("SS_POLL","0.5"))
STALE=float(os.environ.get("SS_STALE","10"))
MAX_DRIFT=float(os.environ.get("SS_MAX_DRIFT","4"))
PCM_RATE=48000
PCM_CHANNELS=2
PCM_BPS=PCM_RATE*PCM_CHANNELS*2

stop=False
def sig(*_):
    global stop;stop=True
signal.signal(signal.SIGTERM,sig);signal.signal(signal.SIGINT,sig)

def norm(s):
    return unicodedata.normalize("NFKD",str(s or "")).encode("ascii","ignore").decode().casefold()
def program(ref):
    s=norm(ref)
    if "manha" in s:return "manha"
    if "tarde" in s:return "tarde"
    if "noite" in s:return "noite"
    return None
def basename(ref):
    return os.path.basename(str(ref or "").replace("\\","/")).strip()
def load_pb():
    d=json.load(open(PB,encoding="utf-8"));q=d.get("payload",{});x=q.get("data",q)
    c=x.get("current") or {};n=x.get("next") or {}
    return {
      "age":max(0,time.time()-PB.stat().st_mtime),
      "state":x.get("state"),"playlistpos":x.get("playlistpos"),
      "pos_ms":x.get("pos_ms") or 0,"len_ms":x.get("len_ms") or 0,
      "current_ref":c.get("FILENAME") or (c.get("TAG") or {}).get("FN") or "",
      "current_title":c.get("ITEMTITLE") or c.get("CASTTITLE") or c.get("TITLE") or "",
      "next_ref":n.get("FILENAME") or (n.get("TAG") or {}).get("FN") or "",
      "next_title":n.get("ITEMTITLE") or n.get("CASTTITLE") or n.get("TITLE") or "",
    }
def resolve(ref):
    p=program(ref);fn=basename(ref)
    if not p or not fn:return None,p,fn
    direct=GRADE/p/fn
    if direct.is_file():return direct,p,fn
    # Case/Unicode tolerant fallback by basename only.
    nf=norm(fn)
    for x in (GRADE/p).iterdir():
        if x.is_file() and norm(x.name)==nf:return x,p,fn
    return None,p,fn
def ffdec(path,offset):
    return subprocess.Popen([
      "/usr/bin/ffmpeg","-hide_banner","-loglevel","error","-nostdin",
      "-ss",f"{max(0,offset):.3f}","-i",str(path),"-vn",
      "-f","s16le","-ar",str(PCM_RATE),"-ac",str(PCM_CHANNELS),"pipe:1"
    ],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
def ffpub():
    return subprocess.Popen([
      "/usr/bin/ffmpeg","-hide_banner","-loglevel","warning","-nostdin","-re",
      "-f","s16le","-ar",str(PCM_RATE),"-ac",str(PCM_CHANNELS),"-i","pipe:0",
      "-c:a","aac","-b:a","128k","-ar","48000","-ac","2","-f","flv",STREAM
    ],stdin=subprocess.PIPE,stderr=subprocess.DEVNULL)
def write_status(obj):
    STATE.mkdir(parents=True,exist_ok=True)
    tmp=STATE/".v2-shadow-status.tmp";dst=STATE/"v2-shadow-status.json"
    with open(tmp,"w",encoding="utf-8") as f:
        json.dump(obj,f,ensure_ascii=False,indent=2);f.flush();os.fsync(f.fileno())
    os.replace(tmp,dst)

pub=ffpub();dec=None;key=None;started_mono=0;started_offset=0;current_path=None

while not stop:
    try: pb=load_pb()
    except Exception as e:
        write_status({"status":"PLAYBACK_UNAVAILABLE","error":repr(e),"updated_at":time.time()})
        time.sleep(POLL);continue

    fresh=pb["age"]<=STALE
    path,pr,fn=resolve(pb["current_ref"])
    next_path,next_pr,next_fn=resolve(pb["next_ref"])
    target_offset=max(0,float(pb["pos_ms"])/1000.0 + pb["age"]) if fresh else None

    write_status({
      "status":"FOLLOWING" if fresh and path else ("CURRENT_MISSING" if fresh else "PLAYBACK_STALE"),
      "updated_at":time.time(),"playback_age_sec":pb["age"],"program":pr,
      "playlistpos":pb["playlistpos"],"pos_ms":pb["pos_ms"],
      "current_ref":pb["current_ref"],"current_title":pb["current_title"],
      "current_path":str(path) if path else None,"current_ready":bool(path),
      "next_ref":pb["next_ref"],"next_title":pb["next_title"],
      "next_path":str(next_path) if next_path else None,"next_ready":bool(next_path),
      "stream":STREAM
    })

    if not fresh or not path:
        time.sleep(POLL);continue

    newkey=(str(path),pb["current_ref"])
    predicted=started_offset+(time.monotonic()-started_mono) if key==newkey else -999
    if dec is None or dec.poll() is not None or key!=newkey or abs(predicted-target_offset)>MAX_DRIFT:
        if dec:
            try:dec.kill();dec.wait(timeout=1)
            except Exception:pass
        dec=ffdec(path,target_offset)
        key=newkey;current_path=path;started_offset=target_offset;started_mono=time.monotonic()
        print(f"V2_SHADOW_SYNC program={pr} offset={target_offset:.3f} file={path}",flush=True)

    chunk=dec.stdout.read(PCM_BPS//4) if dec and dec.stdout else b""
    if not chunk:
        time.sleep(POLL);continue
    try:
        if pub.poll() is not None: pub=ffpub()
        pub.stdin.write(chunk)
    except Exception:
        try: pub.kill()
        except Exception:pass
        pub=ffpub()

if dec:
    try:dec.kill()
    except Exception:pass
try:
    if pub.stdin:pub.stdin.close()
except Exception:pass
try:pub.terminate()
except Exception:pass
