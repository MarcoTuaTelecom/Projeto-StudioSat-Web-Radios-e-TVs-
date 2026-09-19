#!/usr/bin/env bash
set -uo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/root/studiosat-xray-${TS}"
REPORT="$OUT/REPORT.txt"
CSV="$OUT/radios.csv"
mkdir -p "$OUT"/{system,services,media,logs,configs,repair}

FINALIZED=0
finalize(){
  local rc=$?
  [ "$FINALIZED" -eq 0 ] || return 0
  FINALIZED=1
  {
    echo
    echo "FINALIZE_RC=$rc"
    echo "XRAY_DIR=$OUT"
  } >>"$REPORT" 2>/dev/null || true
  tar -C /root -czf "${OUT}.tar.gz" "$(basename "$OUT")" 2>/dev/null || true
  cp -f "$REPORT" /root/NS1-XRAY-LATEST.txt 2>/dev/null || true
  ln -sfn "$OUT" /root/NS1-XRAY-LATEST 2>/dev/null || true
  ln -sfn "${OUT}.tar.gz" /root/NS1-XRAY-LATEST.tar.gz 2>/dev/null || true
  echo "XRAY_DIR=$OUT"
  echo "REPORT=/root/NS1-XRAY-LATEST.txt"
  echo "BUNDLE=/root/NS1-XRAY-LATEST.tar.gz"
}
trap finalize EXIT

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
PUBLIC_HOST="https://radio.studiosatweb.com.br"
MTX_API="http://127.0.0.1:9997"

log(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$REPORT"; }
has(){ command -v "$1" >/dev/null 2>&1; }
safe(){ "$@" 2>&1 || true; }

probe_stream(){
  timeout 10 ffprobe -v error -rw_timeout 7000000 \
    -show_entries stream=codec_name,sample_rate,channels,bit_rate \
    -of default=nw=1 "$1" 2>/dev/null
}

media_ready(){
  probe_stream "$1" | grep -q '^codec_name='
}

hls_ready(){
  curl -LfsS --max-time 8 "$1" 2>/dev/null | grep -q '^#EXTM3U'
}

unit_status(){
  local u="$1"
  systemctl show "$u" \
    -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState \
    -p MainPID -p NRestarts -p ExecMainStartTimestamp \
    -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p TasksCurrent \
    -p FragmentPath -p DropInPaths 2>/dev/null || true
}

audio_quality(){
  local ch="$1" url="$2" out="$3"
  :
  timeout 15 ffmpeg -hide_banner -nostats -loglevel info \
    -rw_timeout 7000000 -i "$url" -t 10 -map 0:a:0 \
    -af "ebur128=peak=true" -f null - \
    >"$out.stdout" 2>"$out.stderr"
  local rc=$?
  :
  {
    echo "FFMPEG_RC=$rc"
    grep -E 'I:|LRA:|Peak:|True peak|Invalid data|Non-monoton|corrupt|error|Connection|timed out|Input/output|buffer' \
      "$out.stderr" | tail -n 80 || true
  } >"$out.summary"
  return $rc
}

hls_cadence(){
  local url="$1" out="$2"
  python3 - "$url" "$out" <<'PY'
import sys,time,urllib.request,re,json
url,out=sys.argv[1:3]
rows=[]
for i in range(5):
    try:
        with urllib.request.urlopen(url,timeout=6) as r:
            body=r.read().decode("utf-8","replace")
        seq=re.search(r"#EXT-X-MEDIA-SEQUENCE:(\d+)",body)
        segs=[x.strip() for x in body.splitlines() if x and not x.startswith("#")]
        rows.append({"i":i,"ok":body.startswith("#EXTM3U"),"sequence":int(seq.group(1)) if seq else None,"last":segs[-1] if segs else None})
    except Exception as e:
        rows.append({"i":i,"ok":False,"error":repr(e),"sequence":None,"last":None})
    if i<4: time.sleep(2)
seqs=[r["sequence"] for r in rows if r.get("sequence") is not None]
advance=(len(seqs)>=2 and seqs[-1]>seqs[0])
obj={"samples":rows,"sequence_advance":advance,"unique_sequences":len(set(seqs))}
open(out,"w").write(json.dumps(obj,indent=2))
print("HLS_SEQUENCE_ADVANCE="+("YES" if advance else "NO"))
print("HLS_UNIQUE_SEQUENCES="+str(len(set(seqs))))
PY
}

playlist_count(){
  local ch="$1"
  local p="/srv/tpsmedia/repository/channels/$ch/playlists/playlist.txt"
  if [ -f "$p" ]; then
    grep -vcE '^\s*(#|$)' "$p" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

control_age(){
python3 <<'PY'
import json,os,time
from datetime import datetime,timezone
paths=[
"/run/studiosat-radioprincipal-v8-control/playback.json",
"/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json"
]
def parse(v):
    if not v:return None
    s=str(v)
    if s.endswith("Z"):s=s[:-1]+"+00:00"
    try:
        d=datetime.fromisoformat(s)
        if d.tzinfo is None:d=d.replace(tzinfo=timezone.utc)
        return d.timestamp()
    except:return None
best=None
for p in paths:
    if not os.path.isfile(p): continue
    try:x=json.load(open(p,encoding="utf-8-sig"))
    except:continue
    pay=x.get("payload") or {}
    data=pay.get("data") if isinstance(pay,dict) and isinstance(pay.get("data"),dict) else pay
    cur=(data.get("current") or {}) if isinstance(data,dict) else {}
    ts=parse(x.get("received_at_utc"))
    if isinstance(pay,dict):ts=ts or parse(pay.get("collected_at_utc"))
    age=time.time()-ts if ts else time.time()-os.stat(p).st_mtime
    row=(max(0,age),p,cur.get("FILENAME") or cur.get("filename") or "",data.get("playlistpos") if isinstance(data,dict) else None,data.get("pos_ms") if isinstance(data,dict) else None)
    if best is None or row[0]<best[0]:best=row
if best:
    print(f"CONTROL_AGE_SEC={best[0]:.2f}")
    print("CONTROL_SOURCE="+best[1])
    print("CONTROL_CURRENT="+str(best[2]))
    print("CONTROL_PLAYLISTPOS="+str(best[3]))
    print("CONTROL_POS_MS="+str(best[4]))
else:
    print("CONTROL_AGE_SEC=999999")
    print("CONTROL_SOURCE=NONE")
PY
}

log "XRAY V2 START $TS"

log "1/9 HARDWARE + OS"
{
  echo "=== HOST ==="; hostnamectl 2>/dev/null || true
  echo; echo "=== CPU ==="; lscpu 2>/dev/null || cat /proc/cpuinfo
  echo; echo "=== MEMORY ==="; free -h; cat /proc/meminfo | head -n 25
  echo; echo "=== LOAD ==="; uptime; cat /proc/loadavg
  echo; echo "=== BLOCK ==="; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL 2>/dev/null || true
  echo; echo "=== DISK ==="; df -hT
  echo; echo "=== INODES ==="; df -ih
  echo; echo "=== MOUNTS ==="; findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
  echo; echo "=== DMI ==="; dmidecode -t system -t processor -t memory 2>/dev/null || true
  echo; echo "=== THERMAL ==="; for z in /sys/class/thermal/thermal_zone*/temp; do [ -r "$z" ] && echo "$z=$(cat "$z")"; done
} >"$OUT/system/hardware.txt" 2>&1

log "2/9 SOFTWARE + NETWORK + PORTS"
{
  echo "=== VERSIONS ==="
  uname -a
  for b in ffmpeg ffprobe nginx python3 node npm liquidsoap icecast2 git curl; do
    if has "$b"; then echo "--- $b ---"; "$b" --version 2>&1 | head -n 4 || "$b" -version 2>&1 | head -n 4 || true; fi
  done
  echo; echo "=== IP ==="; ip -br addr 2>/dev/null || true
  echo; echo "=== ROUTE ==="; ip route 2>/dev/null || true
  echo; echo "=== SOCKETS ==="; ss -lntup 2>/dev/null || true
  echo; echo "=== NETWORK COUNTERS ==="; cat /proc/net/dev
} >"$OUT/system/software-network.txt" 2>&1

log "3/9 GLOBAL RESOURCE SAMPLE"
python3 - "$OUT/system/resource-sample.json" <<'PY'
import os,time,json,sys
def cpu():
    x=open('/proc/stat').readline().split()[1:]
    v=list(map(int,x)); idle=v[3]+v[4]; total=sum(v)
    return idle,total
def net():
    d={}
    for ln in open('/proc/net/dev').read().splitlines()[2:]:
        k,v=ln.split(':',1); a=v.split()
        d[k.strip()]={"rx":int(a[0]),"tx":int(a[8])}
    return d
i1,t1=cpu(); n1=net(); t=time.time(); time.sleep(10); i2,t2=cpu(); n2=net(); dt=time.time()-t
usage=100*(1-(i2-i1)/max(1,t2-t1))
out={"sample_sec":dt,"cpu_pct":round(usage,2),"network":{}}
for k in set(n1)&set(n2):
    out["network"][k]={"rx_mbps":round((n2[k]["rx"]-n1[k]["rx"])*8/dt/1e6,3),
                       "tx_mbps":round((n2[k]["tx"]-n1[k]["tx"])*8/dt/1e6,3)}
json.dump(out,open(sys.argv[1],'w'),indent=2)
print(json.dumps(out,indent=2))
PY

log "4/9 SERVICE TOPOLOGY + RESOURCE USE"
{
  systemctl list-units --type=service --all --no-pager | grep -Ei 'studio|tps|media|nginx|icecast|radio|ffmpeg|liquidsoap' || true
  echo
  ps -eo pid,ppid,user,pcpu,pmem,rss,vsz,etimes,stat,args --sort=-pcpu | \
    grep -E 'PID|ffmpeg|liquidsoap|mediamtx|nginx|icecast|radioprincipal|radiopop|radiorock|radioclassicas|radiocountry' || true
} >"$OUT/services/topology.txt"

for u in \
  nginx.service tps-mediamtx.service \
  studiosat-radioboss-sync.service studiosat-media-transfer.service \
  studiosat-radioprincipal-v8-control-bridge.service \
  studiosat-radioprincipal-v32-core.service \
  studiosat-radioprincipal-shadow-ns1.service \
  tps-radioprincipal-playout.service \
  tps-radiopop-playout.service tps-radiorock-playout.service \
  tps-radioclassicas-playout.service tps-radiocountry-playout.service
do
  unit_status "$u" >"$OUT/services/${u}.show.txt"
  systemctl cat "$u" >"$OUT/services/${u}.unit.txt" 2>&1 || true
  journalctl -u "$u" --since '-60 min' --no-pager >"$OUT/logs/${u}.journal.txt" 2>&1 || true
done

log "5/9 MEDIAMTX + NGINX"
curl -fsS --max-time 5 "$MTX_API/v3/paths/list" >"$OUT/media/mediamtx-paths.json" 2>&1 || true
nginx -T >"$OUT/configs/nginx-T.txt" 2>&1 || true
nginx -t >"$OUT/configs/nginx-test.txt" 2>&1 || true

echo 'station,rtmp,hls_local,hls_public,codec,sample_rate,channels,bit_rate,playlist_entries,hls_advances,audio_test_rc' >"$CSV"

log "6/9 RADIO AUDIO XRAY - EACH STATION"
for ch in "${RADIOS[@]}"; do
  log "PROBE $ch"
  D="$OUT/media/$ch"; mkdir -p "$D"
  RTMP="rtmp://127.0.0.1:1935/$ch"
  HLS_LOCAL="http://127.0.0.1:8888/$ch/index.m3u8"
  HLS_PUBLIC="$PUBLIC_HOST/$ch/index.m3u8"

  :
  PROBE="$(probe_stream "$RTMP")"; RTMP_RC=$?
  :
  printf '%s\n' "$PROBE" >"$D/ffprobe.txt"
  RTMP_OK=NO
  if [ "$RTMP_RC" -eq 0 ] && [ -n "$PROBE" ]; then RTMP_OK=YES; fi

  HLSL=NO
  if hls_ready "$HLS_LOCAL"; then HLSL=YES; fi

  HLSP=NO
  if hls_ready "$HLS_PUBLIC"; then HLSP=YES; fi

  log "$ch transport RTMP=$RTMP_OK HLS_LOCAL=$HLSL HLS_PUBLIC=$HLSP"

  CODEC="$(awk -F= '/^codec_name=/{print $2}' "$D/ffprobe.txt" | head -1)"
  SR="$(awk -F= '/^sample_rate=/{print $2}' "$D/ffprobe.txt" | head -1)"
  CHN="$(awk -F= '/^channels=/{print $2}' "$D/ffprobe.txt" | head -1)"
  BR="$(awk -F= '/^bit_rate=/{print $2}' "$D/ffprobe.txt" | head -1)"
  PC="$(playlist_count "$ch")"

  :
  audio_quality "$ch" "$RTMP" "$D/audio"; ARC=$?
  :
  log "$ch audio_probe_rc=$ARC"

  :
  HC="$(hls_cadence "$HLS_LOCAL" "$D/hls-cadence.json" 2>&1)"; HCRC=$?
  :
  printf '%s\n' "$HC" >"$D/hls-cadence.txt"
  HADV="$(awk -F= '/HLS_SEQUENCE_ADVANCE=/{print $2}' "$D/hls-cadence.txt" | tail -1)"
  [ -n "$HADV" ] || HADV=NO
  log "$ch hls_sequence_advance=$HADV"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ch" "$RTMP_OK" "$HLSL" "$HLSP" "${CODEC:-NA}" "${SR:-NA}" "${CHN:-NA}" "${BR:-NA}" "$PC" "$HADV" "$ARC" \
    >>"$CSV"
done

log "7/9 RADIOBOSS CONTROL + PRINCIPAL QUEUE"
control_age | tee "$OUT/media/radioprincipal-control.txt" >>"$REPORT"

for p in \
  /var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playlist.json \
  /var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json \
  /var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/librarymanifest.json \
  /run/studiosat-radioprincipal-v8-control/playback.json \
  /var/lib/studiosat/radio-principal-stable/effective-queue.json \
  /var/lib/studiosat/radio-principal-stable/state.json
do
  if [ -f "$p" ]; then
    stat "$p" >>"$OUT/media/radioprincipal-files.txt" 2>&1 || true
  fi
done

log "8/9 APPLY DETERMINISTIC SAFE REPAIRS"

if ! systemctl is-active --quiet tps-mediamtx.service; then
  log "REPAIR MediaMTX inactive -> restart"
  systemctl restart tps-mediamtx.service
  sleep 3
fi

if ! systemctl is-active --quiet nginx.service; then
  if nginx -t >/dev/null 2>&1; then
    log "REPAIR nginx inactive with valid config -> restart"
    systemctl restart nginx.service
  else
    log "NGINX_CONFIG_INVALID - not restarting"
  fi
fi

for ch in radiopop radiorock radioclassicas radiocountry; do
  RTMP="rtmp://127.0.0.1:1935/$ch"
  if ! media_ready "$RTMP"; then
    U="tps-${ch}-playout.service"
    if systemctl cat "$U" >/dev/null 2>&1; then
      log "REPAIR $ch stream bad -> restart $U once"
      systemctl restart "$U"
      sleep 4
    fi
  fi
done

CTRL_AGE="$(awk -F= '/^CONTROL_AGE_SEC=/{print int($2)}' "$OUT/media/radioprincipal-control.txt" | tail -1)"
[ -n "$CTRL_AGE" ] || CTRL_AGE=999999

if [ "$CTRL_AGE" -gt 30 ] && systemctl cat studiosat-radioprincipal-shadow-ns1.service >/dev/null 2>&1; then
  log "REPAIR radioprincipal stale control ($CTRL_AGE s) -> install stable no-seek shadow"
  curl -fsSL \
    'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/final/INSTALL-RADIOPRINCIPAL-STABLE-SHADOW-NOW.sh' \
    -o "$OUT/repair/INSTALL-RADIOPRINCIPAL-STABLE-SHADOW-NOW.sh"
  chmod 0700 "$OUT/repair/INSTALL-RADIOPRINCIPAL-STABLE-SHADOW-NOW.sh"
  bash -n "$OUT/repair/INSTALL-RADIOPRINCIPAL-STABLE-SHADOW-NOW.sh"
  :
  bash "$OUT/repair/INSTALL-RADIOPRINCIPAL-STABLE-SHADOW-NOW.sh" \
    >"$OUT/repair/stable-shadow.out" 2>&1
  SHRC=$?
  :
  cat "$OUT/repair/stable-shadow.out" >>"$REPORT"
  echo "STABLE_SHADOW_REPAIR_RC=$SHRC" | tee -a "$REPORT"
fi

log "9/9 POST-REPAIR ACCEPTANCE"

echo 'station,rtmp,hls_local,hls_public' >"$OUT/post-repair.csv"
FAIL=0
for ch in "${RADIOS[@]}"; do
  R=NO
  if media_ready "rtmp://127.0.0.1:1935/$ch"; then R=YES; fi
  L=NO
  if hls_ready "http://127.0.0.1:8888/$ch/index.m3u8"; then L=YES; fi
  P=NO
  if hls_ready "$PUBLIC_HOST/$ch/index.m3u8"; then P=YES; fi
  echo "$ch,$R,$L,$P" >>"$OUT/post-repair.csv"
  if [ "$R" != YES ] || [ "$L" != YES ]; then FAIL=$((FAIL+1)); fi
done

{
  echo
  echo "================ FINAL SUMMARY ================"
  echo "XRAY_DIR=$OUT"
  echo "RADIO_METRICS_CSV=$CSV"
  echo "POST_REPAIR=$OUT/post-repair.csv"
  echo "FAILED_LOCAL_RADIOS=$FAIL"
  echo
  echo "--- INITIAL RADIO METRICS ---"
  column -s, -t "$CSV" 2>/dev/null || cat "$CSV"
  echo
  echo "--- POST REPAIR ---"
  column -s, -t "$OUT/post-repair.csv" 2>/dev/null || cat "$OUT/post-repair.csv"
  echo
  echo "--- TOP CPU ---"
  ps -eo pid,pcpu,pmem,rss,etimes,args --sort=-pcpu | head -n 20
  echo
  echo "--- MEMORY ---"
  free -h
  echo
  echo "--- DISK ---"
  df -hT
  echo
  if [ "$FAIL" -eq 0 ]; then
    echo "RESULTADO=NS1_XRAY_REPAIR_LOCAL_MEDIA_PASS"
  else
    echo "RESULTADO=NS1_XRAY_REPAIR_HAS_FAILURES"
  fi
} | tee -a "$REPORT"

echo "XRAY_COMPLETED=YES" | tee -a "$REPORT"
