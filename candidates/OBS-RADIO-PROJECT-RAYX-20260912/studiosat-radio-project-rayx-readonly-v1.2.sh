#!/usr/bin/env bash
set -u -o pipefail
export LC_ALL=C
R=(radioprincipal radiopop radiorock radioclassicas radiocountry)
T=(tvkids tvteens tvviva tvmaisjovem)
ROOT=/srv/tpsmedia/repository/channels
HLS=http://127.0.0.1:8888
API=http://127.0.0.1:9997
CFG=/etc/tpsmedia/mediamtx/mediamtx.yml
MTX=/opt/tpsmedia/mediamtx/current/mediamtx
REPO=/root/Projeto-StudioSat-Web-Radios-e-TVs-
P=0; W=0; F=0
h(){ printf '\n===== %s =====\n' "$*"; }
p(){ P=$((P+1)); echo "PASS $*"; }
w(){ W=$((W+1)); echo "WARN $*"; }
f(){ F=$((F+1)); echo "FAIL $*"; }
http(){ curl -sS -L --max-time 8 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || true; }
cnt(){ [[ -d "$1" ]] && find "$1" -maxdepth 1 -type f 2>/dev/null | wc -l || echo 0; }
plstat(){ python3 -c 'import os,sys; pth=sys.argv[1]; a=[]; [a.append(x.strip()[5:].strip().strip(chr(39)).strip(chr(34))) for x in open(pth,encoding="utf-8",errors="replace") if x.strip().startswith("file ")]; print("items=%d missing=%d"%(len(a),sum(not os.path.isfile(x) for x in a)))' "$1"; }
if [[ "${1:-}" == --selftest ]]; then command -v python3 >/dev/null && command -v curl >/dev/null && echo SELFTEST=PASS || exit 1; exit 0; fi

h "IDENTIDADE / HOST"
echo "UTC=$(date -u -Is) LOCAL=$(date -Is) HOST=$(hostname -f 2>/dev/null || hostname) READ_ONLY=YES"
echo "CPUS=$(nproc)"; uptime; free -h; df -hT / "$ROOT" 2>/dev/null || true; df -ih / 2>/dev/null || true

h "CORE"
for s in nginx.service bind9.service tps-mediamtx.service; do x=$(systemctl is-active "$s" 2>/dev/null || true); echo "$s=$x"; [[ $x == active ]] && p "$s" || f "$s=$x"; done
nginx -t >/dev/null 2>&1 && p nginx_config || f nginx_config
if [[ -x $MTX ]]; then echo "MEDIAMTX=$($MTX --version 2>&1|head -1)"; "$MTX" --validate-conf="$CFG" >/dev/null 2>&1 && p mediamtx_config || f mediamtx_config; else f mediamtx_binary; fi
[[ -f $CFG ]] && echo "MEDIAMTX_CFG_SHA=$(sha256sum "$CFG"|awk '{print $1}')"
ss -lntup 2>/dev/null | grep -E ':(53|80|443|1935|8888|9997)\b' || true
if command -v dig >/dev/null; then dig @127.0.0.1 studiosatweb.com.br SOA +noall +answer; dig @127.0.0.1 studiosatweb.com.br SOA +short|grep -q . && p dns_local || f dns_local; fi

h "5 RADIOS ON-AIR / CODEC"
ROK=1
for ch in "${R[@]}"; do u=tps-${ch}-playout.service; st=$(systemctl is-active "$u" 2>/dev/null||true); pid=$(systemctl show -p MainPID --value "$u" 2>/dev/null||true); code=$(http "$HLS/$ch/index.m3u8"); prof=$(timeout 15 ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0:s='|' "$HLS/$ch/index.m3u8" 2>/dev/null|head -1); echo "$ch service=$st pid=$pid HLS=$code profile=${prof:-NONE}"; [[ $st == active && $code == 200 && $prof == 'aac|48000|2' ]] && p "$ch" || { f "$ch"; ROK=0; }; done
[[ $ROK -eq 1 ]] && echo ALL_5_RADIOS_ONAIR=PASS || echo ALL_5_RADIOS_ONAIR=FAIL
ps -eo pid,pcpu,pmem,rss,etimes,args --sort=-pcpu | grep -E '[m]ediamtx|[f]fmpeg.*radio(principal|pop|rock|classicas|country)' || true
ps -eo pcpu=,rss=,args= | awk '/mediamtx|ffmpeg.*radio(principal|pop|rock|classicas|country)/{c+=$1;r+=$2}END{printf "RADIO_CPU_SUM=%.1f%% RADIO_RSS=%.1f_MiB\n",c,r/1024}'

h "PLAYLISTS / MUSICAS"
PLOK=1
for ch in "${R[@]}"; do q="$ROOT/$ch/playlists/playlist.txt"; if [[ -f $q ]]; then s=$(plstat "$q"); echo "$ch $s SHA=$(sha256sum "$q"|awk '{print $1}') MTIME=$(stat -c '%y' "$q")"; grep -q 'missing=0' <<<"$s" && grep -Eq 'items=[1-9]' <<<"$s" && p "$ch playlist" || { f "$ch playlist"; PLOK=0; }; else f "$ch playlist_missing"; PLOK=0; fi; done

h "COMERCIAL / HORA / PLAYLOG"
COK=1; ADS=0; HOURS=0; SCHED=0; LOGS=0
for ch in "${R[@]}"; do b="$ROOT/$ch/commercial"; echo "--$ch--"; for d in ads jingles calls voice hour schedules generated playlogs; do n=$(cnt "$b/$d"); echo "$d=$n"; [[ -d $b/$d ]] || COK=0; done; a=$(cnt "$b/ads"); hh=$(cnt "$b/hour"); sc=$(cnt "$b/schedules"); lg=$(find "$b/playlogs" -maxdepth 1 -type f ! -name planned-commercial-v0.tsv 2>/dev/null|wc -l); ADS=$((ADS+a)); HOURS=$((HOURS+hh)); SCHED=$((SCHED+sc)); LOGS=$((LOGS+lg)); [[ -f $b/generated/playlist-commercial-v0.ffconcat ]] && echo "candidate_events=$(grep -c '^file ' "$b/generated/playlist-commercial-v0.ffconcat") candidate_sha=$(sha256sum "$b/generated/playlist-commercial-v0.ffconcat"|awk '{print $1}')" || echo candidate=ABSENT; done
[[ $COK -eq 1 ]] && p commercial_layout || f commercial_layout
echo "ADS_FILES=$ADS HOUR_FILES=$HOURS SCHEDULE_FILES=$SCHED REAL_PLAYLOG_FILES=$LOGS"
if [[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]]; then sha256sum /usr/local/sbin/tps-commercial-scheduler-v0; python3 -c 'import ast; ast.parse(open("/usr/local/sbin/tps-commercial-scheduler-v0",encoding="utf-8").read())' && p scheduler_v0 || f scheduler_v0; else f scheduler_v0_absent; fi
[[ $HOURS -gt 0 ]] && p hora_certa || w hora_certa_NOT_READY
[[ $SCHED -gt 0 ]] && p grade_comercial || w grade_comercial_NOT_READY
[[ $LOGS -gt 0 ]] && p playlog_real || w playlog_real_NOT_READY

h "LAB COMERCIAL"
LS=$(systemctl is-active tps-radioprincipal-commercial-test.service 2>/dev/null||true); LC=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$API/v3/config/paths/get/radioprincipal-commercial-test" 2>/dev/null||true); echo "LAB_UNIT=$LS LAB_PATH_HTTP=$LC"; [[ $LS != active && $LC != 200 ]] && p lab_clean || w lab_runtime_present; grep -Eq '^  radioprincipal-commercial-test:' "$CFG" 2>/dev/null && w lab_persisted_config || p lab_not_persisted

h "MEDIAMTX PATHS"
J=$(curl -fsS --max-time 5 "$API/v3/paths/list" 2>/dev/null||true)
if [[ -n $J ]]; then printf '%s' "$J" | python3 -c 'import json,sys; w=["radioprincipal","radiopop","radiorock","radioclassicas","radiocountry","tvkids","tvteens","tvviva","tvmaisjovem"]; d=json.load(sys.stdin); m={x.get("name"):x for x in d.get("items",[])}; [print("%-20s ready=%s"%(n,m.get(n,{}).get("ready",False))) for n in w]' && p mediamtx_api || w mediamtx_json; else f mediamtx_api; fi

h "TV STATUS RESUMIDO"
for tv in "${T[@]}"; do echo "$tv service=$(systemctl is-active tps-${tv}-playout.service 2>/dev/null||true) HLS=$(http "$HLS/$tv/index.m3u8")"; done
journalctl --since '-30 min' --no-pager 2>/dev/null | grep -Ei 'tvkids|tvteens|tvviva|tvmaisjovem' | grep -Ei 'non-monotonic|dts|error|fail' | tail -30 || true

h "NGINX / WEBROOTS"
nginx -T 2>/dev/null | grep -nE 'server_name .*radio|server_name .*tv(kids|teens|viva|maisjovem)' | tail -80 || true
for x in /var/www/studiosat-radio-portal /var/www/studiosat-radio-player /var/www/studiosat-tv/current /var/www/portais/www.tvkidsweb.studiosatweb.com.br; do [[ -e $x ]] && echo "$x=YES" || echo "$x=NO"; done

h "BACKUPS"
find /var/backups/studiosat -maxdepth 2 \( -type f -o -type d \) \( -iname '*commercial*' -o -iname '*tvkids*' -o -iname '*CHG-TV*' \) 2>/dev/null | sort | tail -40 || true

h "REPO / GOVERNANCA"
if [[ -d $REPO/.git ]]; then LH=$(git -C "$REPO" rev-parse HEAD 2>/dev/null||true); RH=$(git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null|awk '{print $1}'|head -1); D=$(git -C "$REPO" status --porcelain|wc -l); echo "BRANCH=$(git -C "$REPO" branch --show-current) LOCAL=$LH REMOTE=${RH:-UNAVAILABLE} DIRTY=$D"; [[ -n $RH && $LH == $RH ]] && p repo_sync || w repo_not_sync; [[ $D -eq 0 ]] && p repo_clean || w repo_dirty; git -C "$REPO" log -n 15 --date=iso --pretty='format:%h %ad %s' || true; echo; for x in README.md docs/30-execucao/CHANGE_QUEUE.md candidates/CHG-RCOMM01/tps-commercial-lab-orchestrator-v0.2.3.sh; do [[ -f $REPO/$x ]] && echo "PRESENT=$x" || echo "ABSENT=$x"; done; else f repo_missing; fi

h "PROJECT GATES"
[[ $ROK -eq 1 ]] && echo GATE_ONAIR_5_RADIOS=PASS || echo GATE_ONAIR_5_RADIOS=FAIL
[[ $PLOK -eq 1 ]] && echo GATE_MUSIC_PLAYLISTS=PASS || echo GATE_MUSIC_PLAYLISTS=FAIL
[[ $COK -eq 1 ]] && echo GATE_COMMERCIAL_LAYOUT=PASS || echo GATE_COMMERCIAL_LAYOUT=FAIL
[[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]] && echo GATE_SCHEDULER_V0=PRESENT || echo GATE_SCHEDULER_V0=ABSENT
[[ $HOURS -gt 0 ]] && echo GATE_HORA_CERTA=READY || echo GATE_HORA_CERTA=NOT_READY
[[ $SCHED -gt 0 ]] && echo GATE_COMMERCIAL_SCHEDULE=READY || echo GATE_COMMERCIAL_SCHEDULE=NOT_READY
[[ $LOGS -gt 0 ]] && echo GATE_REAL_PLAYLOG=READY || echo GATE_REAL_PLAYLOG=NOT_READY
h "SUMMARY"
echo "PASS=$P WARN=$W FAIL=$F"
[[ $F -eq 0 ]] && echo RAYX_RESULT=PASS_WITH_WARNINGS_POSSIBLE || echo RAYX_RESULT=ATTENTION_REQUIRED
echo PROJECT_POSITION_HINT=RADIO_PRODUCTION__COMMERCIAL_V0__BEFORE_V1_CLOCK_SCHEDULE_REAL_PLAYLOG
echo RAYX_READONLY_COMPLETE=1
