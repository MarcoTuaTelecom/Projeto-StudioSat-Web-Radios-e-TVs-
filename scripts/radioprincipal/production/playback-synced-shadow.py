#!/usr/bin/env python3
# Studio Sat RadioPrincipal - playback-synced shadow
# C14 / 2026-09-17
import os,sys,time,json,sqlite3,subprocess,signal,unicodedata
from pathlib import Path

STATUS=Path(os.environ.get("SS_STATUS","/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json"))
DB=Path(os.environ.get("SS_DB","/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/replica.sqlite3"))
STREAM=os.environ.get("SS_STREAM","rtmp://127.0.0.1:1935/radioprincipal-ns1")
POLL=float(os.environ.get("SS_POLL","0.5"))
MAX_DRIFT=float(os.environ.get("SS_MAX_DRIFT","4.0"))
STALE=float(os.environ.get("SS_STALE","10.0"))
BYTES_PER_SECOND=48000*2*2

def norm(s):
    return unicodedata.normalize("NFC",str(s or "")).replace("\\","/").casefold().strip()
def base(s): return os.path.basename(str(s or "").replace("\\","/")).casefold()
def load_status():
    with STATUS.open(encoding="utf-8") as f:return json.load(f)
def dbro():
    return sqlite3.connect("file:"+str(DB)+"?mode=ro",uri=True,timeout=2)
def row_for_ref(rev, ref):
    con=dbro()
    try:
        rn=norm(ref)
        row=con.execute("""select p.n,p.source_ref,p.asset_id,x.path
                           from playlist_items p left join presence x on x.asset_id=p.asset_id and x.present=1
                           where p.rev=? and p.ref_norm=? limit 1""",(rev,rn)).fetchone()
        if row:return row
        bn=base(ref)
        rows=con.execute("""select p.n,p.source_ref,p.asset_id,x.path
                            from playlist_items p left join presence x on x.asset_id=p.asset_id and x.present=1
                            where p.rev=? order by p.n""",(rev,)).fetchall()
        cand=[r for r in rows if base(r[1])==bn]
        return cand[0] if len(cand)==1 else None
    finally: con.close()
def row_by_n(rev,n):
    con=dbro()
    try:return con.execute("""select p.n,p.source_ref,p.asset_id,x.path
                              from playlist_items p left join presence x on x.asset_id=p.asset_id and x.present=1
                              where p.rev=? and p.n=? limit 1""",(rev,n)).fetchone()
    finally:con.close()

class Publisher:
    def __init__(self): self.p=None
    def start(self):
        self.stop()
        self.p=subprocess.Popen([
          "/usr/bin/ffmpeg","-hide_banner","-loglevel","warning","-nostdin","-re",
          "-f","s16le","-ar","48000","-ac","2","-i","pipe:0",
          "-c:a","aac","-b:a","128k","-ar","48000","-ac","2","-f","flv",STREAM
        ],stdin=subprocess.PIPE,bufsize=0)
    def stop(self):
        if self.p:
            try:
                if self.p.stdin:self.p.stdin.close()
            except Exception: pass
            try:self.p.terminate(); self.p.wait(timeout=2)
            except Exception:
                try:self.p.kill()
                except Exception:pass
        self.p=None
    def write(self,b):
        if not self.p or self.p.poll() is not None:self.start()
        try:self.p.stdin.write(b)
        except (BrokenPipeError,OSError):
            self.start(); self.p.stdin.write(b)

def decoder(path,offset):
    return subprocess.Popen([
      "/usr/bin/ffmpeg","-hide_banner","-loglevel","error","-nostdin",
      "-ss",f"{max(0.0,offset):.3f}","-i",path,
      "-vn","-f","s16le","-ar","48000","-ac","2","pipe:1"
    ],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)

def source_age(st):
    try:return float(st.get("freshness",{}).get("playback_age_sec"))
    except Exception:return 999999.0

pub=Publisher()
stop=False
def sig(*_):
    global stop;stop=True
signal.signal(signal.SIGTERM,sig);signal.signal(signal.SIGINT,sig)
pub.start()

current_key=None
dec=None
started_mono=0.0
started_offset=0.0
current_n=None
current_rev=None

while not stop:
    try: st=load_status()
    except Exception:
        time.sleep(POLL);continue
    rev=st.get("playlist_revision_id")
    pb=st.get("playback") or {}
    ref=pb.get("current_ref") or ""
    pos_ms=pb.get("pos_ms")
    fresh=source_age(st)<=STALE and bool(ref)
    target=None; target_offset=0.0

    if fresh:
        row=row_for_ref(rev,ref)
        if row and row[3] and os.path.isfile(row[3]):
            target=row
            try: target_offset=max(0.0,float(pos_ms or 0)/1000.0 + source_age(st))
            except Exception: target_offset=0.0
    elif current_rev and current_n is not None:
        target=row_by_n(current_rev,current_n)
        target_offset=started_offset+(time.monotonic()-started_mono)

    if not target:
        time.sleep(POLL);continue

    key=(rev,target[0],target[3])
    predicted=started_offset+(time.monotonic()-started_mono) if current_key==key else -999
    reseek=(current_key!=key or dec is None or dec.poll() is not None or (fresh and abs(predicted-target_offset)>MAX_DRIFT))
    if reseek:
        if dec:
            try:dec.kill();dec.wait(timeout=1)
            except Exception:pass
        dec=decoder(target[3],target_offset)
        current_key=key;current_rev=rev;current_n=int(target[0]);started_offset=target_offset;started_mono=time.monotonic()
        print(f"SHADOW_SYNC rev={rev} n={current_n} offset={target_offset:.3f} fresh={fresh} ref={target[1]}",flush=True)

    chunk=dec.stdout.read(BYTES_PER_SECOND//4) if dec and dec.stdout else b""
    if chunk:
        pub.write(chunk)
        continue

    if dec and dec.poll() is not None:
        current_n=int(current_n)+1
        nxt=row_by_n(current_rev,current_n)
        if nxt and nxt[3] and os.path.isfile(nxt[3]):
            dec=decoder(nxt[3],0.0)
            current_key=(current_rev,current_n,nxt[3]);started_offset=0.0;started_mono=time.monotonic()
            print(f"SHADOW_CONTINUE rev={current_rev} n={current_n} ref={nxt[1]}",flush=True)
        else:
            time.sleep(POLL)

pub.stop()
