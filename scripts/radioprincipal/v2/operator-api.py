#!/usr/bin/env python3
import json,os,time,subprocess
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

ROOT=Path("/srv/studiosat/radio-principal")
GRADE=ROOT/"grade"
STATE=ROOT/"estado"
RB=Path("/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json")
HOST="127.0.0.1";PORT=8810

def jload(p):
    try:return json.load(open(p,encoding="utf-8"))
    except Exception:return {}
def service(u):
    try:return subprocess.run(["systemctl","is-active",u],capture_output=True,text=True,timeout=2).stdout.strip()
    except Exception:return "unknown"
def counts():
    out={}
    for p in ("manha","tarde","noite"):
        d=GRADE/p
        out[p]=sum(1 for x in d.iterdir() if x.is_file() and x.suffix.lower() in (".mp3",".wav",".flac",".m4a",".aac",".ogg",".opus")) if d.exists() else 0
    return out
def status():
    return {
      "station":"Rádio Principal","system":"Studio Sat",
      "repositories":{"root":str(ROOT),"grade":{p:str(GRADE/p) for p in ("manha","tarde","noite")},"counts":counts()},
      "sync":jload(STATE/"repositorios.json"),
      "radioboss":jload(RB),
      "production":{"selector":service("studiosat-radioprincipal-selector.service"),"shadow":service("studiosat-radioprincipal-shadow-ns1.service"),"mediamtx":service("tps-mediamtx.service"),"nginx":service("nginx.service")},
      "policy":{"production_control_enabled":False,"reason":"rebuild-no-downtime"}
    }
class H(BaseHTTPRequestHandler):
    def sendj(self,code,obj):
        b=json.dumps(obj,ensure_ascii=False,indent=2).encode();self.send_response(code);self.send_header("Content-Type","application/json; charset=utf-8");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
    def do_GET(self):
        p=urlparse(self.path).path
        if p in ("/","/api/v1/status"):return self.sendj(200,status())
        if p=="/api/v1/programas":return self.sendj(200,{"programas":counts(),"root":str(GRADE)})
        if p.startswith("/api/v1/programas/"):
            n=p.rsplit("/",1)[-1]
            if n not in ("manha","tarde","noite"):return self.sendj(404,{"error":"programa_invalido"})
            d=GRADE/n
            files=[{"name":x.name,"size":x.stat().st_size,"mtime":x.stat().st_mtime} for x in sorted(d.iterdir()) if x.is_file()] if d.exists() else []
            return self.sendj(200,{"programa":n,"path":str(d),"files":files})
        return self.sendj(404,{"error":"not_found"})
    def do_POST(self):
        # During rebuild, API cannot start/stop/restart public audio.
        p=urlparse(self.path).path
        if p.startswith("/api/v1/producao/"):return self.sendj(423,{"error":"production_locked","message":"controle de producao bloqueado durante reconstrucao sem downtime"})
        if p=="/api/v1/operacao/nota":
            try:
                n=int(self.headers.get("Content-Length","0"));body=json.loads(self.rfile.read(n) or b"{}")
            except Exception:return self.sendj(400,{"error":"invalid_json"})
            rec={"at":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"note":body.get("note","")}
            f=STATE/"notas-operacao.jsonl";f.parent.mkdir(parents=True,exist_ok=True)
            with open(f,"a",encoding="utf-8") as h:h.write(json.dumps(rec,ensure_ascii=False)+"\n")
            return self.sendj(201,{"ok":True,"record":rec})
        return self.sendj(404,{"error":"not_found"})
    def log_message(self,fmt,*args):pass
ThreadingHTTPServer((HOST,PORT),H).serve_forever()
