#!/usr/bin/env bash
set -u -o pipefail
export LC_ALL=C

V=1.1
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
ROOT=/srv/tpsmedia/repository/channels
MTX=/opt/tpsmedia/mediamtx/current/mediamtx
CFG=/etc/tpsmedia/mediamtx/mediamtx.yml
API=http://127.0.0.1:9997
HLS=http://127.0.0.1:8888
REPO=/root/Projeto-StudioSat-Web-Radios-e-TVs-
P=0 W=0 F=0
hr(){ printf '\n===== %s =====\n' "$*"; }
pass(){ P=$((P+1)); echo "PASS $*"; }
warn(){ W=$((W+1)); echo "WARN $*"; }
fail(){ F=$((F+1)); echo "FAIL $*"; }
http(){ curl -sS -L --max-time 8 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
count(){ [[ -d "$1" ]] && find "$1" -maxdepth 1 -type f 2>/dev/null | wc -l || echo 0; }
media_count(){ [[ -d "$1" ]] && find "$1" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.mp4' \) 2>/dev/null | wc -l || echo 0; }
playlist_stats(){ python3 - "$1" <<'PY'
import os,sys
p=sys.argv[1]; total=missing=0
if os.path.isfile(p):
  for raw in open(p,encoding='utf-8',errors='replace'):
    s=raw.strip()
    if not s.startswith('file '): continue
    total+=1; x=s[5:].strip()
    if len(x)>=2 and x[0]==x[-1]=="'": x=x[1:-1].replace("'\\''", "'")
    elif len(x)>=2 and x[0]==x[-1]=='"': x=x[1:-1]
    if not os.path.isfile(x): missing+=1
print(f"items={total} missing={missing}")
PY
}

[[ "${1:-}" == --selftest ]] && { bash -n "$0"; echo SELFTEST=PASS; exit 0; }

hr "STUDIOSAT RAY-X READ-ONLY v$V"
echo "UTC=$(date -u -Is) LOCAL=$(date -Is) HOST=$(hostname -f 2>/dev/null || hostname)"
echo 'READ_ONLY=YES NO_RESTART=YES NO_RELOAD=YES'

hr "HOST"
echo "CPUS=$(nproc)"; uptime; free -h; df -hT / "$ROOT" 2>/dev/null || true; df -ih / 2>/dev/null || true

hr "CORE"
for s in nginx.service bind9.service tps-mediamtx.service; do st=$(systemctl is-active "$s" 2>/dev/null || true); echo "$s=$st"; [[ "$st" == active ]] && pass "$s" || fail "$s=$st"; done
nginx -t >/dev/null 2>&1 && pass nginx_config || fail nginx_config
if [[ -x "$MTX" ]]; then echo "MEDIAMTX_VERSION=$($MTX --version 2>&1 | head -1)"; "$MTX" --validate-conf="$CFG" >/dev/null 2>&1 && pass mediamtx_config || fail mediamtx_config; else fail mediamtx_binary; fi
[[ -f "$CFG" ]] && sha256sum "$CFG"
ss -lntup 2>/dev/null | grep -E ':(53|80|443|1935|8888|9997)\b' || true
if command -v dig >/dev/null; then dig @127.0.0.1 studiosatweb.com.br SOA +noall +answer; dig @127.0.0.1 studiosatweb.com.br SOA +short | grep -q . && pass dns_local || fail dns_local; fi

hr "5 RADIOS ON-AIR"
R_OK=1
for ch in "${RADIOS[@]}"; do
  u=tps-${ch}-playout.service; st=$(systemctl is-active "$u" 2>/dev/null || true); en=$(systemctl is-enabled "$u" 2>/dev/null || true); pid=$(systemctl show -p MainPID --value "$u" 2>/dev/null || true); code=$(http "$HLS/$ch/index.m3u8"); prof=$(timeout 15 ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0:s='|' "$HLS/$ch/index.m3u8" 2>/dev/null | head -1)
  echo "$ch service=$st enabled=$en pid=$pid HLS=$code profile=${prof:-NONE}"
  [[ "$st" == active && "$code" == 200 && "$prof" == 'aac|48000|2' ]] && pass "$ch" || { fail "$ch"; R_OK=0; }
done
[[ $R_OK -eq 1 ]] && echo ALL_5_RADIOS_ONAIR=PASS || echo ALL_5_RADIOS_ONAIR=FAIL
ps -eo pid,pcpu,pmem,rss,etimes,args --sort=-pcpu | grep -E '[m]ediamtx|[f]fmpeg.*radio(principal|pop|rock|classicas|country)' || true
ps -eo pcpu=,rss=,args= | awk '/mediamtx|ffmpeg.*radio(principal|pop|rock|classicas|country)/{c+=$1;r+=$2}END{printf "RADIO_CPU_SUM=%.1f%% RADIO_RSS=%.1f_MiB\n",c,r/1024}'

hr "PLAYLISTS / MUSICAS"
PL_OK=1
for ch in "${RADIOS[@]}"; do p="$ROOT/$ch/playlists/playlist.txt"; if [[ -f "$p" ]]; then s=$(playlist_stats "$p"); echo "$ch $s SHA=$(sha256sum "$p"|awk '{print $1}') MTIME=$(stat -c '%y' "$p")"; grep -q 'missing=0' <<<"$s" && grep -Eq 'items=[1-9]' <<<"$s" && pass "$ch playlist" || { fail "$ch playlist"; PL_OK=0; }; else fail "$ch playlist_missing"; PL_OK=0; fi; done
[[ $PL_OK -eq 1 ]] && echo RADIO_PLAYLISTS=PASS || echo RADIO_PLAYLISTS=FAIL

hr "COMERCIAL / HORA CERTA / PLAYLOG"
C_OK=1; ADS=0; HOURS=0; SCHED=0; REALLOG=0
for ch in "${RADIOS[@]}"; do
  b="$ROOT/$ch/commercial"; echo "-- $ch --"
  for d in ads jingles calls voice hour schedules generated playlogs; do n=$(count "$b/$d"); echo "$d=$n"; [[ -d "$b/$d" ]] || C_OK=0; done
  a=$(media_count "$b/ads"); h=$(media_count "$b/hour"); sc=$(count "$b/schedules"); rl=$(find "$b/playlogs" -maxdepth 1 -type f ! -name planned-commercial-v0.tsv 2>/dev/null | wc -l)
  ADS=$((ADS+a)); HOURS=$((HOURS+h)); SCHED=$((SCHED+sc)); REALLOG=$((REALLOG+rl))
  [[ -f "$b/generated/playlist-commercial-v0.ffconcat" ]] && echo "candidate_events=$(grep -c '^file ' "$b/generated/playlist-commercial-v0.ffconcat") candidate_sha=$(sha256sum "$b/generated/playlist-commercial-v0.ffconcat"|awk '{print $1}')" || echo candidate=ABSENT
  [[ -f "$b/generated/playlist-commercial-v0.json" ]] && grep -E '"(music|jingles|ads|calls|voices|hours|breaks|events)"' "$b/generated/playlist-commercial-v0.json" || true
done
[[ $C_OK -eq 1 ]] && pass commercial_layout || fail commercial_layout
echo "COMMERCIAL_MEDIA=$ADS HOUR_MEDIA=$HOURS SCHEDULE_FILES=$SCHED REAL_PLAYLOG_FILES=$REALLOG"
if [[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]]; then sha256sum /usr/local/sbin/tps-commercial-scheduler-v0; python3 - /usr/local/sbin/tps-commercial-scheduler-v0 <<'PY' && pass scheduler_v0_syntax || fail scheduler_v0_syntax
import ast,sys
ast.parse(open(sys.argv[1],encoding='utf-8').read())
PY
else fail scheduler_v0_absent; fi
[[ $HOURS -gt 0 ]] && pass hora_certa_assets || warn hora_certa_NOT_READY
[[ $SCHED -gt 0 ]] && pass commercial_schedule || warn commercial_schedule_NOT_READY
[[ $REALLOG -gt 0 ]] && pass real_playlog || warn real_playlog_NOT_READY

hr "COMMERCIAL LAB RESIDUE"
ls=$(systemctl is-active tps-radioprincipal-commercial-test.service 2>/dev/null || true); lc=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$API/v3/config/paths/get/radioprincipal-commercial-test" 2>/dev/null || true); echo "LAB_UNIT=$ls LAB_PATH_HTTP=$lc"; [[ "$ls" != active && "$lc" != 200 ]] && pass lab_clean || warn lab_runtime_present; grep -Eq '^  radioprincipal-commercial-test:' "$CFG" 2>/dev/null && warn lab_persisted_in_config || pass lab_not_persisted

hr "MEDIAMTX 9 PATHS"
json=$(curl -fsS --max-time 5 "$API/v3/paths/list" 2>/dev/null || true)
if [[ -n "$json" ]]; then
  python3 - <<'PY' <<<"$json"
import json,sys
w=['radioprincipal','radiopop','radiorock','radioclassicas','radiocountry','tvkids','tvteens','tvviva','tvmaisjovem']
d=json.load(sys.stdin); m={x.get('name'):x for x in d.get('items',[])}
for n in w: print(f"{n:20} ready={m.get(n,{}).get('ready',False)}")
PY
  pass mediamtx_api
else fail mediamtx_api; fi

hr "TV STATUS SUMMARY"
for tv in "${TVS[@]}"; do echo "$tv service=$(systemctl is-active tps-${tv}-playout.service 2>/dev/null || true) HLS=$(http "$HLS/$tv/index.m3u8")"; done
journalctl --since '-30 min' --no-pager 2>/dev/null | grep -Ei 'tvkids|tvteens|tvviva|tvmaisjovem' | grep -Ei 'non-monotonic|dts|error|fail' | tail -30 || true

hr "NGINX OWNERS / WEBROOTS"
nginx -T 2>/dev/null | grep -nE 'server_name .*radio|server_name .*tv(kids|teens|viva|maisjovem)' | tail -80 || true
for p in /var/www/studiosat-radio-portal /var/www/studiosat-radio-player /var/www/studiosat-tv/current /var/www/portais/www.tvkidsweb.studiosatweb.com.br; do [[ -e "$p" ]] && echo "$p=YES" || echo "$p=NO"; done

hr "BACKUPS"
find /var/backups/studiosat -maxdepth 2 \( -type f -o -type d \) \( -iname '*commercial*' -o -iname '*tvkids*' -o -iname '*CHG-TV*' \) 2>/dev/null | sort | tail -40 || true

hr "REPO / GOVERNANCE"
if [[ -d "$REPO/.git" ]]; then
  LH=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true); RH=$(git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null|awk '{print $1}'|head -1); D=$(git -C "$REPO" status --porcelain|wc -l)
  echo "BRANCH=$(git -C "$REPO" branch --show-current) LOCAL=$LH REMOTE=${RH:-UNAVAILABLE} DIRTY=$D"
  [[ -n "$RH" && "$LH" == "$RH" ]] && pass repo_sync || warn repo_not_sync
  [[ $D -eq 0 ]] && pass repo_clean || warn repo_dirty
  git -C "$REPO" log -n 15 --date=iso --pretty='format:%h %ad %s' || true; echo
  for f in README.md docs/30-execucao/CHANGE_QUEUE.md candidates/CHG-RCOMM01/tps-commercial-lab-orchestrator-v0.2.3.sh; do [[ -f "$REPO/$f" ]] && echo "PRESENT=$f" || echo "ABSENT=$f"; done
else fail repo_missing; fi

hr "PROJECT GATES"
[[ $R_OK -eq 1 ]] && echo GATE_ONAIR_5_RADIOS=PASS || echo GATE_ONAIR_5_RADIOS=FAIL
[[ $PL_OK -eq 1 ]] && echo GATE_MUSIC_PLAYLISTS=PASS || echo GATE_MUSIC_PLAYLISTS=FAIL
[[ $C_OK -eq 1 ]] && echo GATE_COMMERCIAL_LAYOUT=PASS || echo GATE_COMMERCIAL_LAYOUT=FAIL
[[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]] && echo GATE_SCHEDULER_V0=PRESENT || echo GATE_SCHEDULER_V0=ABSENT
[[ $HOURS -gt 0 ]] && echo GATE_HORA_CERTA=READY || echo GATE_HORA_CERTA=NOT_READY
[[ $SCHED -gt 0 ]] && echo GATE_COMMERCIAL_SCHEDULE=READY || echo GATE_COMMERCIAL_SCHEDULE=NOT_READY
[[ $REALLOG -gt 0 ]] && echo GATE_REAL_PLAYLOG=READY || echo GATE_REAL_PLAYLOG=NOT_READY

hr "SUMMARY"
echo "PASS=$P WARN=$W FAIL=$F"
[[ $F -eq 0 ]] && echo RAYX_RESULT=PASS_WITH_WARNINGS_POSSIBLE || echo RAYX_RESULT=ATTENTION_REQUIRED
echo PROJECT_POSITION_HINT=RADIO_PRODUCTION__COMMERCIAL_V0__BEFORE_V1_CLOCK_SCHEDULE_REAL_PLAYLOG
echo RAYX_READONLY_COMPLETE=1
