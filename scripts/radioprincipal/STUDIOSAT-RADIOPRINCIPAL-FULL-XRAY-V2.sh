#!/usr/bin/env bash
# Nome: STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh
# Versão: V2 / registro canônico 2026-09-17
# Owner: Rádio
# Safety class: read-only
# Change ID: RADIOPRINCIPAL-NS1-C03
# Propósito: coletar baseline/forense da Rádio Principal no NS1 sem alterar serviços de produção.
# Pré-condições: executar como root no NS1; manter o RadioBOSS tocando normalmente; não operar Next/Pause/Stop durante a observação.
# Rollback/remoção: remover este arquivo; o script não instala, reinicia, habilita ou desabilita serviços.
# Origem: arquivo fornecido pelo operador em 2026-09-17; corpo funcional preservado, apenas este cabeçalho de governança foi acrescentado.

set -uo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="/root/XRAY-RADIOPRINCIPAL-NS1-V2-$STAMP.txt"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-90}"
API="http://127.0.0.1:9997/v3/paths/list"

BASE="/var/lib/studiosat/radio-v2/stations/radioprincipal"
SYNC="/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current"
STATE="$BASE/state"
CURRENT="$BASE/current"
MEDIA="$CURRENT/media-map.json"
PB_SYNC="$SYNC/playback.json"
PB_V8="/run/studiosat-radioprincipal-v8-control/playback.json"
RT="$STATE/v8-production-runtime.json"
HC="$BASE/hora-certa-runtime"
REPO="/srv/tpsmedia/repository/channels/radioprincipal"
MIRROR="/opt/studiosat/radio-v2/radioprincipal-mirror"
V8DIR="/opt/studiosat/radio-v2/radioprincipal-v8"
DB="/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3"

UNITS=(
  studiosat-radioboss-sync.service
  studiosat-media-transfer.service
  studiosat-media-repo-index.service
  studiosat-media-repo-index.timer
  studiosat-radioprincipal-mirror-controller.service
  studiosat-radioprincipal-mirror-controller.timer
  studiosat-radioprincipal-rb-monitor.service
  studiosat-radioprincipal-shadow-ns1.service
  studiosat-radioprincipal-selector.service
  studiosat-radioprincipal-v8-control-bridge.service
  studiosat-radioprincipal-v8-production.service
  studiosat-radioprincipal-v8-stage.service
  studiosat-radioprincipal-v8-live-ingress.service
  studiosat-radioprincipal-healthguard-final.service
  studiosat-radioprincipal-healthguard-final.timer
  tps-mediamtx.service
  nginx.service
)

exec > >(tee "$REPORT") 2>&1

sec(){ echo; printf '=%.0s' {1..110}; echo; echo "$1"; printf '=%.0s' {1..110}; echo; }
run(){ echo "+ $*"; "$@" 2>&1 || echo "COMMAND_RC=$?"; }
safe_sha(){ [ -f "$1" ] && sha256sum "$1" 2>/dev/null || true; }
safe_stat(){ [ -e "$1" ] && stat -c 'PATH=%n TYPE=%F MODE=%a OWNER=%U:%G SIZE=%s MTIME=%y INODE=%i' "$1" 2>/dev/null || echo "MISSING=$1"; }

redact(){
  sed -E \
    -e 's/((pass(word)?|secret|token|authorization|api[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'\''']+/\1<REDACTED>/Ig' \
    -e 's#(://[^:/[:space:]]+:)[^@/[:space:]]+@#\1<REDACTED>@#g'
}

path_one(){
python3 - "$API" "$1" <<'PY'
import json,sys,urllib.request
name=sys.argv[2]
try:
    with urllib.request.urlopen(sys.argv[1],timeout=3) as r:d=json.load(r)
except Exception as e:
    print("PATH_API_ERROR="+repr(e)); raise SystemExit(0)
x=next((x for x in d.get("items",[]) if x.get("name")==name),None)
print(json.dumps(x,ensure_ascii=False,sort_keys=True) if x else "PATH_NOT_FOUND="+name)
PY
}

json_summary(){
python3 - "$1" <<'PY'
import json,os,sys,time,hashlib
p=sys.argv[1]
if not os.path.isfile(p):
    print("MISSING="+p); raise SystemExit
try:
    b=open(p,'rb').read()
    d=json.loads(b.decode('utf-8-sig'))
except Exception as e:
    print("JSON_ERROR="+repr(e)); raise SystemExit
print("PATH="+p)
print("AGE_SECONDS=%.3f"%(time.time()-os.stat(p).st_mtime))
print("SHA256="+hashlib.sha256(b).hexdigest())
for k in ("revision","generation","received_at_utc","updated_at_utc","station_id","kind","mode","source_generation","track_count","available_count","missing_count"):
    if k in d: print(k.upper()+"="+str(d.get(k)))
pl=d.get("payload")
if isinstance(pl,dict):
    for k in ("revision","received_at_utc","station_id","kind"):
        if k in pl: print("PAYLOAD_"+k.upper()+"="+str(pl.get(k)))
    data=pl.get("data")
    if isinstance(data,dict):
        for k in ("revision","state","playlistpos","pos_ms","len_ms","timestamp","collected_at_utc","radioboss_online","station_id","machine","agent_version"):
            if k in data: print("DATA_"+k.upper()+"="+str(data.get(k)))
        cur=data.get("current") or {}
        if isinstance(cur,dict):
            print("CURRENT_FILENAME="+str(cur.get("FILENAME") or cur.get("filename") or ""))
            print("CURRENT_TITLE="+str(cur.get("ITEMTITLE") or cur.get("TITLE") or cur.get("title") or ""))
for key in ("tracks","items","playlist"):
    v=d.get(key)
    if isinstance(v,list):
        print(key.upper()+"_COUNT="+str(len(v)))
PY
}

echo "# STUDIOSAT RADIOPRINCIPAL - FULL XRAY NS1 V2"
echo "UTC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "MODE=READ_ONLY_EXCEPT_REPORT_AND_TMP_HTTP_BODIES"
echo "FOCUS=RADIOBOSS_INGEST__PLAYLIST_MIRROR__MIRROR_CONTROLLER__PLAYOUT__LIVE_18005"
echo "OBSERVE_SECONDS=$OBSERVE_SECONDS"
echo "REPORT=$REPORT"

sec "01. HOST / CLOCK / RESOURCE / IO"
run hostnamectl
run uptime
run timedatectl
run free -h
run df -h /
run df -ih /
run uname -a
command -v vmstat >/dev/null && run vmstat 1 3
command -v iostat >/dev/null && run iostat -xz 1 2

sec "02. ALL RELEVANT SYSTEMD UNITS / TIMERS"
systemctl list-units --all --no-pager 2>&1 | grep -Ei 'radioprincipal|radioboss|media-transfer|media-repo|mediamtx|nginx' || true
echo
systemctl list-unit-files --no-pager 2>&1 | grep -Ei 'radioprincipal|radioboss|media-transfer|media-repo|mediamtx|nginx' || true
echo
systemctl list-timers --all --no-pager 2>&1 | grep -Ei 'radioprincipal|media-repo' || true

sec "03. EXACT SERVICE STATES"
for u in "${UNITS[@]}"; do
  echo "--- $u ---"
  systemctl show "$u" --no-pager \
    -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState \
    -p MainPID -p NRestarts -p Result -p ExecMainStatus -p ExecMainCode \
    -p User -p Group -p ExecStart -p FragmentPath \
    -p ActiveEnterTimestamp -p ActiveExitTimestamp \
    -p StateChangeTimestamp -p InvocationID \
    -p MemoryCurrent -p CPUUsageNSec \
    -p TriggeredBy -p Triggers 2>&1 || true
done

sec "04. UNIT CONTENTS - CONTROL / MIRROR / SELECTOR / V8 / LIVE"
for u in \
  studiosat-radioboss-sync.service \
  studiosat-media-transfer.service \
  studiosat-radioprincipal-mirror-controller.service \
  studiosat-radioprincipal-mirror-controller.timer \
  studiosat-radioprincipal-rb-monitor.service \
  studiosat-radioprincipal-shadow-ns1.service \
  studiosat-radioprincipal-selector.service \
  studiosat-radioprincipal-v8-control-bridge.service \
  studiosat-radioprincipal-v8-production.service \
  studiosat-radioprincipal-v8-live-ingress.service
do
  echo "--- systemctl cat $u ---"
  systemctl cat "$u" --no-pager 2>&1 | redact || true
done

sec "05. REAL PROCESSES / TREES"
ps -eo pid,ppid,user,lstart,etimes,stat,%cpu,%mem,rss,vsz,cmd --sort=pid 2>&1 |
  grep -Ei '[r]adioboss|[r]adioprincipal|[m]irror|[s]tage-core|[c]ontrol-bridge|[l]iquidsoap|[m]ediamtx|[f]fmpeg|[m]edia-transfer|[n]ginx' || true
for u in studiosat-radioprincipal-shadow-ns1.service studiosat-radioprincipal-selector.service studiosat-radioprincipal-v8-production.service studiosat-radioprincipal-v8-live-ingress.service; do
  pid="$(systemctl show -p MainPID --value "$u" 2>/dev/null || true)"
  echo "--- TREE $u PID=${pid:-0} ---"
  if command -v pstree >/dev/null 2>&1 && [[ "${pid:-}" =~ ^[0-9]+$ ]] && ((pid>0)); then pstree -aps "$pid" 2>&1 || true; fi
done

sec "06. NETWORK / SSH TUNNEL / HARBOR / RTMP"
ss -lntup 2>&1 | grep -E ':(443|1935|8888|8793|8794|9001|9997|9998|18005|18006|28005|28006)\b' || true
echo
ss -ntp 2>&1 | grep -E ':(18005|18006|1935|8793|8794|9997|28005|28006)\b' || true
echo "NOTE_18005=ESTABLISHED proves TCP transport to Harbor, not that the selector has chosen it."
echo "NOTE_18006_2800X=may be staging/test only."

sec "07. RADIOBOSS SYNC CURRENT DIRECTORY - EXACT INVENTORY"
run ls -lah --time-style=full-iso "$SYNC"
for f in playlist.json schedule.json librarymanifest.json playback.json heartbeat.json; do
  echo "--- $SYNC/$f ---"
  safe_stat "$SYNC/$f"
  safe_sha "$SYNC/$f"
  [ -r "$SYNC/$f" ] && json_summary "$SYNC/$f"
done

sec "08. RADIOBOSS SNAPSHOT PAYLOAD DETAILS"
python3 - "$SYNC" <<'PY'
import json,sys,os,time
from pathlib import Path
S=Path(sys.argv[1])
def load(n):
    p=S/n
    try:return json.load(open(p,encoding="utf-8-sig"))
    except Exception as e:
        print(n+"_ERROR="+repr(e));return {}
def data(d):
    p=d.get("payload",d)
    return p.get("data",p) if isinstance(p,dict) else {}
for n in ("playlist.json","schedule.json","librarymanifest.json","playback.json","heartbeat.json"):
    d=load(n); x=data(d)
    print("###",n)
    print("TOP_KEYS="+",".join(sorted(map(str,d.keys()))) if isinstance(d,dict) else "")
    print("DATA_KEYS="+",".join(sorted(map(str,x.keys()))) if isinstance(x,dict) else "")
    for key in ("revision","collected_at_utc","timestamp","radioboss_online","station_id","machine","agent_version","state","playlistpos","pos_ms","len_ms"):
        if isinstance(x,dict) and key in x: print(key.upper()+"="+str(x.get(key)))
    for key in ("items","tracks","playlist","entries","events","files"):
        v=x.get(key) if isinstance(x,dict) else None
        if isinstance(v,list): print(key.upper()+"_COUNT="+str(len(v)))
    if n=="playlist.json" and isinstance(x,dict):
        arr=next((x.get(k) for k in ("items","tracks","playlist","entries") if isinstance(x.get(k),list)),[])
        for i,it in enumerate(arr[:8]):
            if isinstance(it,dict):
                print("PLAYLIST_HEAD|%d|%s"%(i,str(it.get("FILENAME") or it.get("filename") or it.get("source") or it.get("ITEMTITLE") or it)[:500]))
        for i,it in list(enumerate(arr))[-5:]:
            if isinstance(it,dict):
                print("PLAYLIST_TAIL|%d|%s"%(i,str(it.get("FILENAME") or it.get("filename") or it.get("source") or it.get("ITEMTITLE") or it)[:500]))
PY

sec "09. V8 CONTROL BRIDGE PLAYBACK - FRESHNESS / CONTENT"
for f in "$PB_V8" "$RT"; do
  echo "--- $f ---"
  safe_stat "$f"
  safe_sha "$f"
  [ -r "$f" ] && json_summary "$f"
  [ -r "$f" ] && python3 - "$f" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1],encoding="utf-8-sig"))
except Exception as e: print("ERR="+repr(e)); raise SystemExit
print(json.dumps(d,ensure_ascii=False,indent=2)[:40000])
PY
done

sec "10. MIRROR CONTROLLER / SOURCE CODE / HASHES / PERMISSIONS"
for p in \
  "$MIRROR" \
  "$MIRROR/mirror-sync.py" \
  "$MIRROR/mirror-playout.py" \
  "$MIRROR/radioboss-live-monitor.py" \
  "$V8DIR" \
  "$V8DIR/control-bridge-v3.2.py" \
  "$V8DIR/stage-core-v4.2.py" \
  "$V8DIR/stage-core-v4.8-live.py" \
  "$V8DIR/stage-core-v4.9-live.py"
do
  safe_stat "$p"
  safe_sha "$p"
done
echo "--- MIRROR-SYNC IMPORTANT CODE ---"
[ -r "$MIRROR/mirror-sync.py" ] && grep -nE 'playlist|schedule|librarymanifest|media-map|generation|current|replace|rename|symlink|sqlite|missing|available|sha|lock|flock|except|traceback|sys.exit' "$MIRROR/mirror-sync.py" | head -280 || true
echo "--- MIRROR-PLAYOUT IMPORTANT CODE ---"
[ -r "$MIRROR/mirror-playout.py" ] && grep -nE 'media-map|generation|playlist|current|reload|mtime|sleep|sha|ffmpeg|position|index|except|traceback' "$MIRROR/mirror-playout.py" | head -240 || true
echo "--- PATH PERMISSIONS ---"
for p in "$SYNC" "$BASE" "$BASE/generations" "$CURRENT" "$MEDIA" "$REPO" "$REPO/mirror-store"; do
  echo "--- namei $p ---"; command -v namei >/dev/null && namei -l "$p" 2>&1 || true
done

sec "11. CURRENT MEDIA MAP / GENERATIONS / ATOMIC POINTER"
safe_stat "$MEDIA"
safe_sha "$MEDIA"
readlink -f "$CURRENT" 2>/dev/null || true
run ls -ld "$CURRENT" "$BASE/generations"
run ls -lat "$BASE/generations"
python3 - "$MEDIA" <<'PY'
import json,sys,os,time,hashlib
p=sys.argv[1]
if not os.path.isfile(p):
    print("MEDIA_MAP=MISSING");raise SystemExit
d=json.load(open(p,encoding="utf-8-sig"))
tracks=d.get("tracks") or d.get("items") or []
print("GENERATION="+str(d.get("generation","")))
print("SOURCE_GENERATION="+str(d.get("source_generation","")))
print("MEDIA_TOTAL="+str(len(tracks)))
print("MEDIA_AVAILABLE_FIELD="+str(d.get("available_count","")))
print("MEDIA_MISSING_FIELD="+str(d.get("missing_count","")))
avail=0;missing=[]
for i,t in enumerate(tracks):
    if not isinstance(t,dict): continue
    path=t.get("path") or t.get("local_path")
    logical=str(t.get("source") or t.get("filename") or "").lower().startswith("saytime=")
    ok=logical or (bool(path) and os.path.isfile(path) and os.access(path,os.R_OK))
    if ok: avail+=1
    else: missing.append((i,t.get("filename"),path,t.get("sha256")))
print("MEDIA_OPENABLE_OR_LOGICAL="+str(avail))
print("MEDIA_NOT_OPENABLE="+str(len(missing)))
for x in missing[:30]: print("MEDIA_BAD|"+repr(x))
for i,t in enumerate(tracks[:8]):
    if isinstance(t,dict): print("MEDIA_HEAD|%d|%s|%s|%s"%(i,t.get("filename",""),t.get("sha256",""),t.get("path","")))
for i,t in list(enumerate(tracks))[-5:]:
    if isinstance(t,dict): print("MEDIA_TAIL|%d|%s|%s|%s"%(i,t.get("filename",""),t.get("sha256",""),t.get("path","")))
PY

sec "12. PLAYLIST INPUT vs MEDIA-MAP ORDER / DIVERGENCE"
python3 - "$SYNC/playlist.json" "$MEDIA" <<'PY'
import json,sys,os,re
def load(p):
    try:return json.load(open(p,encoding="utf-8-sig"))
    except Exception as e: print("LOAD_ERROR",p,repr(e));return {}
def payload(d):
    p=d.get("payload",d)
    return p.get("data",p) if isinstance(p,dict) else {}
def arr_playlist(d):
    x=payload(d)
    for k in ("items","tracks","playlist","entries"):
        if isinstance(x,dict) and isinstance(x.get(k),list):return x[k]
    return []
def name(x):
    if not isinstance(x,dict):return str(x)
    return str(x.get("FILENAME") or x.get("filename") or x.get("source") or x.get("ITEMTITLE") or x.get("title") or "")
def base(x):return name(x).replace("\\","/").split("/")[-1].casefold()
pl=arr_playlist(load(sys.argv[1]))
md=load(sys.argv[2]); mt=md.get("tracks") or md.get("items") or []
print("INPUT_PLAYLIST_COUNT="+str(len(pl)))
print("MEDIA_MAP_COUNT="+str(len(mt)))
n=max(len(pl),len(mt)); dif=[]
for i in range(n):
    a=base(pl[i]) if i<len(pl) else "<missing>"
    b=base(mt[i]) if i<len(mt) else "<missing>"
    if a!=b:dif.append((i,a,b))
print("ORDER_FILENAME_DIFF_COUNT="+str(len(dif)))
for x in dif[:60]:print("DIFF|%d|INPUT=%s|MEDIA=%s"%x)
PY

sec "13. MEDIA TRANSFER SQLITE - READ ONLY"
if [ -r "$DB" ]; then
  safe_stat "$DB"; safe_sha "$DB"
  python3 - "$DB" <<'PY'
import sqlite3,sys,os
p=sys.argv[1]
try:
    con=sqlite3.connect("file:"+p+"?mode=ro",uri=True,timeout=3)
    con.execute("PRAGMA query_only=ON")
    tabs=[r[0] for r in con.execute("select name from sqlite_master where type='table' order by name")]
    print("TABLES="+",".join(tabs))
    for t in tabs:
        try:
            n=con.execute('select count(*) from "'+t.replace('"','""')+'"').fetchone()[0]
            print("TABLE_COUNT|%s|%s"%(t,n))
        except Exception as e: print("TABLE_COUNT_ERROR|%s|%r"%(t,e))
    con.close()
except Exception as e: print("SQLITE_READ_ERROR="+repr(e))
PY
else echo "DB=MISSING"; fi

sec "14. MIRROR / SYNC JOURNALS - LAST 90 MINUTES"
for u in \
 studiosat-radioboss-sync.service \
 studiosat-media-transfer.service \
 studiosat-radioprincipal-mirror-controller.service \
 studiosat-radioprincipal-mirror-controller.timer \
 studiosat-radioprincipal-shadow-ns1.service \
 studiosat-radioprincipal-rb-monitor.service \
 studiosat-radioprincipal-v8-control-bridge.service
do
  echo "--- JOURNAL $u ---"
  journalctl -u "$u" --since "90 minutes ago" --no-pager 2>&1 | tail -500 || true
done

sec "15. INGEST HTTP EVIDENCE - NGINX ACCESS"
for f in /var/log/nginx/access.log /var/log/nginx/*access*.log; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  grep -E '/api/radioboss-sync/v1/ingest/radioprincipal/(playlist|schedule|librarymanifest|playback|heartbeat)' "$f" | tail -400 || true
done
echo "--- INGEST COUNTS LAST LOG TAIL ---"
python3 - <<'PY'
import glob,re,collections,os
pat=re.compile(r'/api/radioboss-sync/v1/ingest/radioprincipal/(playlist|schedule|librarymanifest|playback|heartbeat).*?" ([0-9]{3}) ')
c=collections.Counter()
last={}
for f in sorted(set(glob.glob('/var/log/nginx/*access*.log')+['/var/log/nginx/access.log'])):
    if not os.path.isfile(f):continue
    try:
        lines=open(f,errors='replace').read().splitlines()[-10000:]
    except:continue
    for line in lines:
        m=pat.search(line)
        if m:
            c[(m.group(1),m.group(2))]+=1;last[m.group(1)]=line
for k,v in sorted(c.items()):print("INGEST_COUNT|%s|HTTP=%s|N=%s"%(k[0],k[1],v))
for k,v in sorted(last.items()):print("INGEST_LAST|%s|%s"%(k,v))
PY

sec "16. SELECTOR / HARBOR 18005 CONNECT-DISCONNECT FORENSICS"
echo "--- SELECTOR JOURNAL 90 MIN ---"
journalctl -u studiosat-radioprincipal-selector.service --since "90 minutes ago" --no-pager 2>&1 |
  grep -E 'radioprincipal_rb_harbor|Switch to|Feeding|Decoding|Content type|New metadata|Error|Timed out|connected|disconnect' |
  tail -700 || true
echo "--- LIVE INGRESS JOURNAL 90 MIN ---"
journalctl -u studiosat-radioprincipal-v8-live-ingress.service --since "90 minutes ago" --no-pager 2>&1 |
  tail -500 || true
echo "--- CURRENT TCP 18005 ---"
ss -ltnp 2>&1 | grep ':18005' || true
ss -tnp 2>&1 | grep ':18005' || true

sec "17. V8 PRODUCTION / FAILED CUTOVER FORENSICS"
for u in studiosat-radioprincipal-v8-production.service studiosat-radioprincipal-v8-stage.service studiosat-radioprincipal-v8-live-ingress.service; do
  echo "--- JOURNAL $u 90 MIN ---"
  journalctl -u "$u" --since "90 minutes ago" --no-pager 2>&1 | tail -600 || true
done
echo "--- V8 FILES ---"
find "$V8DIR" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %m %u:%g %s %p\n' 2>/dev/null | sort || true
for f in "$V8DIR"/stage-core*.py "$V8DIR"/control-bridge*.py; do [ -f "$f" ] && sha256sum "$f"; done

sec "18. MEDIAMTX CONFIG / PATHS / PUBLISHER OWNERSHIP"
if [ -r /etc/tpsmedia/mediamtx/mediamtx.yml ]; then
  sed -E 's/(pass(word)?[[:space:]]*:[[:space:]]*).*/\1<REDACTED>/I' /etc/tpsmedia/mediamtx/mediamtx.yml
fi
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-test; do
  echo "--- PATH $p ---"; path_one "$p"
done
echo "--- MEDIAMTX JOURNAL 90 MIN ---"
journalctl -u tps-mediamtx.service --since "90 minutes ago" --no-pager 2>&1 |
  grep -Ei 'radioprincipal|RTMP|HLS|error|warn|closed|opened|publish|read' | tail -800 || true

sec "19. AUDIO PROBES / HLS ADVANCEMENT"
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb radioprincipal-test; do
  echo "--- RTMP $p ---"
  timeout 8 ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name,codec_type,sample_rate,channels,channel_layout \
    -of default=nw=1 "rtmp://127.0.0.1:1935/$p" 2>&1 || echo "PROBE_FAIL=$p"
done
python3 - <<'PY'
import urllib.request,urllib.parse,time,re
u="https://www.radio.studiosatweb.com.br/hls/radioprincipal/index.m3u8"
def get(x):
    req=urllib.request.Request(x,headers={"User-Agent":"StudioSat-XRAY-V2/1"})
    with urllib.request.urlopen(req,timeout=10) as r:return r.geturl(),r.read().decode("utf-8","replace")
def last():
    f,b=get(u);ls=[x.strip() for x in b.splitlines() if x.strip()]
    for i,x in enumerate(ls):
        if x.startswith("#EXT-X-STREAM-INF") and i+1<len(ls):
            f,b=get(urllib.parse.urljoin(f,ls[i+1]));break
    seq=re.search(r"#EXT-X-MEDIA-SEQUENCE:(\d+)",b)
    seg=[x for x in b.splitlines() if x and not x.startswith("#")]
    return (seq.group(1) if seq else "NA",seg[-1] if seg else "NA")
try:
    a=last(); print("HLS_SAMPLE_1="+repr(a)); time.sleep(6); b=last(); print("HLS_SAMPLE_2="+repr(b))
    print("HLS_ADVANCE="+("SIM" if a!=b else "NAO"))
except Exception as e:print("HLS_ERROR="+repr(e))
PY

sec "20. NGINX CONFIG / ERRORS RELEVANT TO RADIO / API"
nginx -T 2>&1 | grep -nE 'radioboss-sync|/hls/|server_name .*radio\.studiosatweb|proxy_pass|client_max_body_size' | head -500 || true
echo "--- ERROR LOG ---"
[ -f /var/log/nginx/error.log ] && tail -300 /var/log/nginx/error.log || true

sec "21. 90-SECOND LIVE DATA-PLANE OBSERVATION - NO COMMANDS SENT"
echo "OBSERVE_SECONDS=$OBSERVE_SECONDS"
echo "DO_NOT_PRESS_NEXT_PAUSE_STOP. Apenas deixe o RadioBOSS rodando normalmente durante esta janela."
python3 - "$SYNC" "$MEDIA" "$PB_V8" "$RT" "$OBSERVE_SECONDS" <<'PY'
import json,sys,time,os,hashlib,subprocess
sync,media,pbv8,rt,dur=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],max(30,int(sys.argv[5]))
paths={
 "PL":os.path.join(sync,"playlist.json"),
 "SC":os.path.join(sync,"schedule.json"),
 "LM":os.path.join(sync,"librarymanifest.json"),
 "PBS":os.path.join(sync,"playback.json"),
 "PBV8":pbv8,
 "MEDIA":media,
 "RT":rt
}
def j(p):
    try:return json.load(open(p,encoding="utf-8-sig"))
    except:return {}
def h(p):
    try:
        b=open(p,'rb').read();return hashlib.sha256(b).hexdigest()[:12]
    except:return "-"
def age(p):
    try:return round(time.time()-os.stat(p).st_mtime,1)
    except:return -1
def payload(d):
    p=d.get("payload",d)
    return p.get("data",p) if isinstance(p,dict) else {}
def plinfo():
    d=j(paths["PL"]);x=payload(d)
    arr=[]
    if isinstance(x,dict):
        for k in ("items","tracks","playlist","entries"):
            if isinstance(x.get(k),list):arr=x[k];break
    return len(arr),d.get("revision",x.get("revision") if isinstance(x,dict) else None)
def pbinfo(p):
    x=payload(j(p));c=x.get("current") or {} if isinstance(x,dict) else {}
    return (x.get("state"),x.get("playlistpos"),x.get("pos_ms"),str(c.get("FILENAME") or c.get("filename") or "").replace("\\","/").split("/")[-1])
def minfo():
    d=j(paths["MEDIA"]);tr=d.get("tracks") or d.get("items") or []
    return d.get("generation"),len(tr),d.get("available_count"),d.get("missing_count")
def rtinfo():
    d=j(paths["RT"]);return d.get("generation"),d.get("index"),d.get("filename"),d.get("mode"),d.get("reason")
def tcp():
    try:
        out=subprocess.check_output(["ss","-tnH"],text=True,stderr=subprocess.DEVNULL)
        return 1 if ":18005" in out and "ESTAB" in out else 0
    except:return -1
end=time.time()+dur;last=None
while time.time()<end:
    pi=plinfo();ps=pbinfo(paths["PBS"]);pv=pbinfo(paths["PBV8"]);mi=minfo();ri=rtinfo()
    key=(h(paths["PL"]),h(paths["MEDIA"]),ps[0],ps[1],ps[3],pv[0],pv[1],pv[3],mi[0],ri[3],tcp())
    now=time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())
    if key!=last:
        print("OBS|%s|PL_age=%s PL_sha=%s PL_count=%s PL_rev=%s|PBS_age=%s state=%s idx=%s file=%s|PBV8_age=%s state=%s idx=%s file=%s|MEDIA_age=%s sha=%s gen=%s count=%s avail=%s miss=%s|RT_age=%s mode=%s reason=%s file=%s|TCP18005=%s"%
          (now,age(paths["PL"]),h(paths["PL"]),pi[0],pi[1],age(paths["PBS"]),ps[0],ps[1],ps[3],
           age(paths["PBV8"]),pv[0],pv[1],pv[3],age(paths["MEDIA"]),h(paths["MEDIA"]),mi[0],mi[1],mi[2],mi[3],
           age(paths["RT"]),ri[3],ri[4],ri[2],key[-1]),flush=True)
        last=key
    time.sleep(1)
PY

sec "22. POST-OBSERVATION SNAPSHOTS / JOURNAL DELTA"
for f in playlist.json schedule.json librarymanifest.json playback.json heartbeat.json; do
  echo "--- FINAL $SYNC/$f ---"; [ -r "$SYNC/$f" ] && json_summary "$SYNC/$f"
done
echo "--- FINAL MEDIA ---"; [ -r "$MEDIA" ] && json_summary "$MEDIA"
echo "--- FINAL V8 PB ---"; [ -r "$PB_V8" ] && json_summary "$PB_V8"
echo "--- FINAL RUNTIME ---"; [ -r "$RT" ] && json_summary "$RT"
echo "--- MIRROR CONTROLLER LAST 15 MIN ---"
journalctl -u studiosat-radioprincipal-mirror-controller.service --since "15 minutes ago" --no-pager 2>&1 | tail -400 || true
echo "--- RADIOBOSS SYNC LAST 15 MIN ---"
journalctl -u studiosat-radioboss-sync.service --since "15 minutes ago" --no-pager 2>&1 | tail -400 || true
echo "--- SHADOW LAST 15 MIN ---"
journalctl -u studiosat-radioprincipal-shadow-ns1.service --since "15 minutes ago" --no-pager 2>&1 | tail -400 || true

sec "23. CONSISTENCY SUMMARY - FACTS ONLY"
python3 - "$SYNC/playlist.json" "$MEDIA" "$PB_SYNC" "$PB_V8" "$RT" <<'PY'
import json,sys,os,time,hashlib
pl,mm,pbs,pbv8,rt=sys.argv[1:]
def load(p):
    try:return json.load(open(p,encoding="utf-8-sig"))
    except:return {}
def age(p):
    try:return time.time()-os.stat(p).st_mtime
    except:return 1e99
def payload(d):
    p=d.get("payload",d)
    return p.get("data",p) if isinstance(p,dict) else {}
def countpl(d):
    x=payload(d)
    for k in ("items","tracks","playlist","entries"):
        if isinstance(x,dict) and isinstance(x.get(k),list):return len(x[k])
    return 0
P=load(pl);M=load(mm);BS=payload(load(pbs));BV=payload(load(pbv8));R=load(rt)
mt=M.get("tracks") or M.get("items") or []
print("PLAYLIST_INPUT_AGE_SECONDS=%.3f"%age(pl))
print("PLAYLIST_INPUT_COUNT="+str(countpl(P)))
print("MEDIA_MAP_AGE_SECONDS=%.3f"%age(mm))
print("MEDIA_MAP_GENERATION="+str(M.get("generation","")))
print("MEDIA_MAP_COUNT="+str(len(mt)))
print("SYNC_PLAYBACK_AGE_SECONDS=%.3f"%age(pbs))
print("V8_PLAYBACK_AGE_SECONDS=%.3f"%age(pbv8))
print("V8_RUNTIME_AGE_SECONDS=%.3f"%age(rt))
print("SYNC_RB_ONLINE="+str(BS.get("radioboss_online")))
print("SYNC_AGENT_VERSION="+str(BS.get("agent_version")))
print("V8_RB_ONLINE="+str(BV.get("radioboss_online")))
print("V8_AGENT_VERSION="+str(BV.get("agent_version")))
print("V8_RUNTIME_MODE="+str(R.get("mode")))
print("V8_RUNTIME_REASON="+str(R.get("reason")))
print("PLAYLIST_TO_MEDIA_COUNT_MATCH="+("YES" if countpl(P)==len(mt) else "NO"))
PY
echo "PROD_STATE=$(systemctl is-active studiosat-radioprincipal-v8-production.service 2>/dev/null || true)"
echo "SELECTOR_STATE=$(systemctl is-active studiosat-radioprincipal-selector.service 2>/dev/null || true)"
echo "SHADOW_STATE=$(systemctl is-active studiosat-radioprincipal-shadow-ns1.service 2>/dev/null || true)"
echo "MIRROR_TIMER_STATE=$(systemctl is-active studiosat-radioprincipal-mirror-controller.timer 2>/dev/null || true)"
echo "MIRROR_SERVICE_STATE=$(systemctl is-active studiosat-radioprincipal-mirror-controller.service 2>/dev/null || true)"
echo "BRIDGE_STATE=$(systemctl is-active studiosat-radioprincipal-v8-control-bridge.service 2>/dev/null || true)"
echo "LIVE_INGRESS_STATE=$(systemctl is-active studiosat-radioprincipal-v8-live-ingress.service 2>/dev/null || true)"
echo "MEDIAMTX_STATE=$(systemctl is-active tps-mediamtx.service 2>/dev/null || true)"
echo "REPORT=$REPORT"
echo "XRAY_NS1_COMPLETE=YES"
echo "RESULTADO=XRAY_RADIOPRINCIPAL_NS1_V2_OK"
