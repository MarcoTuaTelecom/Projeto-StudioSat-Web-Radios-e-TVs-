#!/usr/bin/env python3
import base64, hashlib, http.client, json, os, re, sqlite3, xml.etree.ElementTree as ET
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

HOST="127.0.0.1"
PORT=8796
STATION="radioprincipal"
SYNC=Path("/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current")
MEDIA_DB=Path("/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3")
TOKEN_FILE=Path("/etc/studiosat/radio-v2/radioboss-sync-tokens.json")
UPSTREAM_HOST="127.0.0.1"
UPSTREAM_PORT=8794
AUDIO_EXT={".mp3",".wav",".m4a",".aac",".flac",".ogg",".opus"}

TOKEN=json.load(open(TOKEN_FILE,encoding="utf-8")).get(STATION)
if not TOKEN:
    raise RuntimeError("token radioprincipal ausente")

def norm(s):
    return str(s or "").replace("\\","/").strip().casefold()

def pathval(d):
    if not isinstance(d,dict): return ""
    for k in ("path","source","fn","FILENAME","FILE","PATH","SOURCE_PATH","FN"):
        v=d.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
    for k,v in d.items():
        if isinstance(v,str) and ("path" in k.casefold() or "file" in k.casefold()) and v.strip():
            return v.strip()
    return ""

def data(doc):
    q=doc.get("payload",{}) if isinstance(doc,dict) else {}
    return q.get("data",q) if isinstance(q,dict) else {}

def xmlstr(o):
    out=[]
    def r(x):
        if isinstance(x,str) and "<Playlist" in x:
            out.append(x)
        elif isinstance(x,dict):
            for v in x.values(): r(v)
        elif isinstance(x,list):
            for v in x:r(v)
    r(o)
    return max(out,key=len) if out else None

def playlist_items(doc):
    x=xmlstr(doc)
    if x:
        root=ET.fromstring(x)
        out=[]
        for i,t in enumerate(root.findall(".//TRACK")):
            a={str(k):str(v) for k,v in t.attrib.items()}
            for c in list(t):
                if c.tag not in a: a[c.tag]=c.text or ""
            out.append({"n":i,"ref":pathval(a),"attrs":a})
        return out
    lists=[]
    def r(x):
        if isinstance(x,list) and x and all(isinstance(z,dict) for z in x):
            score=sum(bool(pathval(z)) for z in x)
            if score: lists.append((score,len(x),x))
        elif isinstance(x,dict):
            for v in x.values():r(v)
    r(data(doc))
    if not lists:return []
    _,_,L=max(lists,key=lambda z:(z[0],z[1]))
    return [{"n":i,"ref":pathval(z),"attrs":z} for i,z in enumerate(L)]

def playback(doc):
    d=data(doc); d=d if isinstance(d,dict) else {}
    c=d.get("current") if isinstance(d.get("current"),dict) else {}
    n=d.get("next") if isinstance(d.get("next"),dict) else {}
    return {
      "state":d.get("state"),"playlistpos":d.get("playlistpos"),
      "pos_ms":d.get("pos_ms"),"len_ms":d.get("len_ms"),
      "current_ref":pathval(c),"next_ref":pathval(n)
    }

def program(ref):
    s=norm(ref)
    if "manha" in s or "0730_1200" in s or "0730as1200" in s:return "manha"
    if "tarde" in s:return "tarde"
    if "noite" in s:return "noite"
    return ""

def is_virtual(ref):
    s=str(ref or "").strip()
    if not s:return True
    if s.casefold().startswith("saytime="):return True
    ext=os.path.splitext(s.replace("\\","/"))[1].lower()
    return ext not in AUDIO_EXT

def dbmaps():
    bypath={}
    if not MEDIA_DB.is_file():return bypath
    c=sqlite3.connect("file:"+str(MEDIA_DB)+"?mode=ro",uri=True,timeout=3)
    c.row_factory=sqlite3.Row
    try:
        for r in c.execute("select source_path,sha256,filename from sources"):
            bypath[norm(r["source_path"])]=dict(r)
        for r in c.execute("select source_path,sha256,filename from repository_index"):
            bypath.setdefault(norm(r["source_path"]),dict(r))
    finally:c.close()
    return bypath

def object_present(sha):
    if not sha or not MEDIA_DB.is_file():return False
    c=sqlite3.connect("file:"+str(MEDIA_DB)+"?mode=ro",uri=True,timeout=3)
    try:
        r=c.execute("select object_path from assets where sha256=?",(sha,)).fetchone()
        return bool(r and os.path.isfile(r[0]))
    finally:c.close()

def plan():
    pd=json.load(open(SYNC/"playlist.json",encoding="utf-8"))
    bd=json.load(open(SYNC/"playback.json",encoding="utf-8"))
    items=playlist_items(pd); pb=playback(bd); m=dbmaps()
    cur=norm(pb["current_ref"]); nxt=norm(pb["next_ref"])
    out=[]
    for x in items:
        ref=x["ref"]; nr=norm(ref)
        rec=m.get(nr) or {}
        sha=str(rec.get("sha256") or "").lower()
        present=object_present(sha)
        pri=50
        if nr and nr==cur:pri=0
        elif nr and nr==nxt:pri=1
        else:
            try:
                p=int(pb.get("playlistpos"))
                pri=max(2,2+abs(int(x["n"])-p))
            except Exception: pri=50+int(x["n"])
        out.append({
          "n":x["n"],"source_path":ref,"filename":os.path.basename(ref.replace("\\","/")) if ref else "",
          "program":program(ref),"virtual":is_virtual(ref),"priority":pri,
          "known_sha256":sha or None,"present":present
        })
    out.sort(key=lambda z:(z["virtual"],z["present"],z["priority"],z["n"]))
    return {"ok":True,"station":STATION,"playback":pb,"count":len(out),"items":out}

class H(BaseHTTPRequestHandler):
    server_version="StudioSatEdgeBridge/1.0"
    def log_message(self,fmt,*args): pass
    def sendj(self,status,obj):
        b=json.dumps(obj,ensure_ascii=False).encode()
        self.send_response(status);self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",str(len(b)));self.send_header("Cache-Control","no-store")
        self.end_headers();self.wfile.write(b)
    def do_GET(self):
        p=urlparse(self.path).path
        if p=="/health":
            self.sendj(200,{"ok":True,"service":"studiosat-edge-bridge","version":1,"station":STATION})
            return
        if p==f"/v1/plan/{STATION}":
            try:self.sendj(200,plan())
            except Exception as e:self.sendj(500,{"ok":False,"error":"plan_failed","detail":repr(e)})
            return
        self.sendj(404,{"error":"not_found"})
    def do_PUT(self):
        p=urlparse(self.path).path
        if p!=f"/v1/upload/{STATION}":
            self.sendj(404,{"error":"not_found"});return
        try:size=int(self.headers.get("Content-Length","-1"))
        except Exception:size=-1
        if size<0:
            self.sendj(411,{"error":"content_length_required"});return

        headers={
          "Authorization":"Bearer "+TOKEN,
          "Content-Length":str(size),
          "X-SHA256":self.headers.get("X-SHA256",""),
          "X-Filename-B64":self.headers.get("X-Filename-B64",""),
          "X-SourcePath-B64":self.headers.get("X-SourcePath-B64",""),
          "X-Media-Class":self.headers.get("X-Media-Class","ACTIVE_PLAYLIST")
        }
        conn=http.client.HTTPConnection(UPSTREAM_HOST,UPSTREAM_PORT,timeout=120)
        try:
            conn.putrequest("PUT",f"/v1/upload/{STATION}")
            for k,v in headers.items():conn.putheader(k,v)
            conn.endheaders()
            remaining=size
            while remaining:
                chunk=self.rfile.read(min(1024*1024,remaining))
                if not chunk:break
                conn.send(chunk);remaining-=len(chunk)
            if remaining:
                self.sendj(422,{"error":"client_upload_interrupted","remaining":remaining});return
            resp=conn.getresponse();body=resp.read()
            self.send_response(resp.status)
            ctype=resp.getheader("Content-Type") or "application/json; charset=utf-8"
            self.send_header("Content-Type",ctype);self.send_header("Content-Length",str(len(body)))
            self.end_headers();self.wfile.write(body)
        except Exception as e:
            self.sendj(502,{"error":"upstream_failed","detail":repr(e)})
        finally:
            try:conn.close()
            except Exception:pass

if __name__=="__main__":
    print(f"StudioSat Edge Bridge listening on {HOST}:{PORT}",flush=True)
    ThreadingHTTPServer((HOST,PORT),H).serve_forever()
