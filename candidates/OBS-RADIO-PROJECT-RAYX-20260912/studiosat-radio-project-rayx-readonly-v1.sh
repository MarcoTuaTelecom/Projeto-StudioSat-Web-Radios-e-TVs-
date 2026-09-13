#!/usr/bin/env bash
set -u -o pipefail
export LC_ALL=C

VERSION="1.0"
CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
BASE_ROOT="/srv/tpsmedia/repository/channels"
MTX_BIN="/opt/tpsmedia/mediamtx/current/mediamtx"
MTX_CFG="/etc/tpsmedia/mediamtx/mediamtx.yml"
MTX_API="http://127.0.0.1:9997"
HLS_BASE="http://127.0.0.1:8888"
REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
PASS_N=0
WARN_N=0
FAIL_N=0

hr(){ printf '\n==================================================================\n%s\n==================================================================\n' "$*"; }
pass(){ PASS_N=$((PASS_N+1)); printf 'PASS  %s\n' "$*"; }
warn(){ WARN_N=$((WARN_N+1)); printf 'WARN  %s\n' "$*"; }
fail(){ FAIL_N=$((FAIL_N+1)); printf 'FAIL  %s\n' "$*"; }
kv(){ printf '%-30s %s\n' "$1" "$2"; }
have(){ command -v "$1" >/dev/null 2>&1; }
http_code(){ curl -sS -L --max-time 8 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || printf '000'; }
ffprobe_radio_profile(){ timeout 15 ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0:s='|' "$1" 2>/dev/null | head -n1; }

playlist_asset_stats(){
  python3 - "$1" <<'PY'
import os,sys
p=sys.argv[1]
total=missing=0
if not os.path.isfile(p):
    print('total=0 missing=0'); raise SystemExit
for raw in open(p,encoding='utf-8',errors='replace'):
    s=raw.strip()
    if not s.startswith('file '): continue
    total+=1
    x=s[5:].strip()
    if len(x)>=2 and x[0]==x[-1]=="'": x=x[1:-1].replace("'\\''", "'")
    elif len(x)>=2 and x[0]==x[-1]=='"': x=x[1:-1]
    if not os.path.isfile(x): missing+=1
print(f'total={total} missing={missing}')
PY
}

count_media(){
  [[ -d "$1" ]] || { echo 0; return; }
  find "$1" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.mp4' \) -printf '.' 2>/dev/null | wc -c
}

check_media_metadata_dir(){
  local d="$1" f bad=0 total=0
  [[ -d "$d" ]] || { echo 'total=0 bad=0'; return; }
  while IFS= read -r -d '' f; do
    total=$((total+1))
    timeout 10 ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f" >/dev/null 2>&1 || bad=$((bad+1))
  done < <(find "$d" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.mp4' \) -print0 2>/dev/null)
  echo "total=$total bad=$bad"
}

if [[ "${1:-}" == "--selftest" ]]; then
  [[ "$(printf x | wc -c)" -eq 1 ]] || exit 1
  echo 'SELFTEST=PASS'
  exit 0
fi

hr "STUDIOSAT WEB — RAIO-X COMPLETO READ-ONLY v${VERSION}"
kv timestamp_utc "$(date -u -Is)"
kv timestamp_local "$(date -Is)"
kv hostname "$(hostname -f 2>/dev/null || hostname)"
kv kernel "$(uname -srmo 2>/dev/null || uname -a)"
kv uptime "$(uptime -p 2>/dev/null || true)"
kv timezone "$(timedatectl show -p Timezone --value 2>/dev/null || true)"
echo READ_ONLY=YES
echo NO_RESTART=YES
echo NO_RELOAD=YES
echo NO_FILE_WRITE=YES

hr "1. CAPACIDADE / SAUDE DO HOST"
kv cpus "$(nproc 2>/dev/null || echo '?')"
uptime || true
free -h || true
df -hT / "$BASE_ROOT" 2>/dev/null || df -hT / || true
df -ih / "$BASE_ROOT" 2>/dev/null || true
[[ -r /proc/pressure/cpu ]] && { echo CPU_PSI:; cat /proc/pressure/cpu; }
[[ -r /proc/pressure/memory ]] && { echo MEMORY_PSI:; cat /proc/pressure/memory; }

hr "2. CORE: NGINX / BIND / MEDIAMTX"
for s in nginx.service bind9.service tps-mediamtx.service; do
  st="$(systemctl is-active "$s" 2>/dev/null || true)"
  printf '%-28s %s\n' "$s" "$st"
  [[ "$st" == active ]] && pass "$s active" || fail "$s=$st"
done
if have nginx; then
  if nginx -t >/dev/null 2>&1; then pass 'nginx -t'; else fail 'nginx -t'; nginx -t 2>&1 || true; fi
fi
if [[ -x "$MTX_BIN" ]]; then
  kv mediamtx_version "$($MTX_BIN --version 2>&1 | head -n1)"
  if "$MTX_BIN" --validate-conf="$MTX_CFG" >/dev/null 2>&1; then pass 'MediaMTX config valida'; else fail 'MediaMTX config invalida'; fi
else
  fail 'MediaMTX bin ausente'
fi
[[ -f "$MTX_CFG" ]] && kv mediamtx_cfg_sha256 "$(sha256sum "$MTX_CFG" | awk '{print $1}')"
echo PORTAS_CRITICAS:
ss -lntup 2>/dev/null | grep -E ':(53|80|443|1935|8888|9997)\b' || true

hr "3. DNS LOCAL"
if have dig; then
  dig @127.0.0.1 studiosatweb.com.br SOA +noall +answer +comments || true
  if dig @127.0.0.1 studiosatweb.com.br SOA +short | grep -q .; then pass 'SOA local responde'; else fail 'SOA local sem resposta'; fi
else
  warn 'dig ausente'
fi

hr "4. CINCO RADIOS — SYSTEMD / HLS / CODEC"
RADIO_ALL_OK=1
for ch in "${CHANNELS[@]}"; do
  unit="tps-${ch}-playout.service"
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  pid="$(systemctl show -p MainPID --value "$unit" 2>/dev/null || true)"
  url="${HLS_BASE}/${ch}/index.m3u8"
  code="$(http_code "$url")"
  profile="$(ffprobe_radio_profile "$url" || true)"
  printf '%-18s service=%-8s enabled=%-10s pid=%-8s HLS=%s profile=%s\n' "$ch" "$state" "$enabled" "$pid" "$code" "${profile:-NONE}"
  if [[ "$state" == active && "$code" == 200 && "$profile" == 'aac|48000|2' ]]; then pass "$ch on-air AAC/48k/stereo"; else fail "$ch divergente"; RADIO_ALL_OK=0; fi
done
[[ "$RADIO_ALL_OK" == 1 ]] && echo ALL_5_RADIOS_ONAIR=PASS || echo ALL_5_RADIOS_ONAIR=FAIL
ps -eo pid,user,pcpu,pmem,rss,etimes,args --sort=-pcpu 2>/dev/null | grep -E '[m]ediamtx|[f]fmpeg.*radio(principal|pop|rock|classicas|country)' || true
ps -eo pcpu=,rss=,args= 2>/dev/null | awk '/mediamtx|ffmpeg.*radio(principal|pop|rock|classicas|country)/ {cpu+=$1;rss+=$2} END {printf "CPU_SUM=%.1f%% RSS=%.1f_MiB\n",cpu,rss/1024}'

hr "5. PLAYLISTS DE PRODUCAO"
PLAYLISTS_OK=1
for ch in "${CHANNELS[@]}"; do
  p="$BASE_ROOT/$ch/playlists/playlist.txt"
  if [[ ! -f "$p" ]]; then fail "$ch playlist ausente"; PLAYLISTS_OK=0; continue; fi
  stats="$(playlist_asset_stats "$p")"
  sha="$(sha256sum "$p" | awk '{print $1}')"
  mt="$(stat -c '%y' "$p" 2>/dev/null || true)"
  printf '%-18s %s sha=%s mtime=%s\n' "$ch" "$stats" "$sha" "$mt"
  missing="$(sed -n 's/.*missing=\([0-9][0-9]*\).*/\1/p' <<<"$stats")"
  total="$(sed -n 's/total=\([0-9][0-9]*\).*/\1/p' <<<"$stats")"
  if [[ "${total:-0}" -gt 0 && "${missing:-1}" -eq 0 ]]; then pass "$ch playlist integra"; else fail "$ch playlist com problema"; PLAYLISTS_OK=0; fi
done
[[ "$PLAYLISTS_OK" == 1 ]] && echo RADIO_PLAYLISTS=PASS || echo RADIO_PLAYLISTS=FAIL

hr "6. ESTRUTURA COMERCIAL / HORA CERTA / PLAYLOG"
COMM_LAYOUT_OK=1
REAL_ADS=0
HOUR_ASSETS=0
REAL_PLAYLOGS=0
SCHEDULE_FILES=0
for ch in "${CHANNELS[@]}"; do
  b="$BASE_ROOT/$ch/commercial"
  echo "--- $ch ---"
  for d in ads jingles calls voice hour schedules generated playlogs; do
    if [[ -d "$b/$d" ]]; then n="$(find "$b/$d" -maxdepth 1 -type f 2>/dev/null | wc -l)"; printf '  %-12s files=%s\n' "$d" "$n"; else printf '  %-12s MISSING\n' "$d"; COMM_LAYOUT_OK=0; fi
  done
  ads_n="$(count_media "$b/ads")"
  hours_n="$(count_media "$b/hour")"
  schedules_n="$(find "$b/schedules" -maxdepth 1 -type f 2>/dev/null | wc -l)"
  playlogs_n="$(find "$b/playlogs" -maxdepth 1 -type f ! -name 'planned-commercial-v0.tsv' 2>/dev/null | wc -l)"
  REAL_ADS=$((REAL_ADS + ads_n)); HOUR_ASSETS=$((HOUR_ASSETS + hours_n)); SCHEDULE_FILES=$((SCHEDULE_FILES + schedules_n)); REAL_PLAYLOGS=$((REAL_PLAYLOGS + playlogs_n))
  [[ "$ads_n" -gt 0 ]] && echo "  ads_metadata: $(check_media_metadata_dir "$b/ads")"
  cand="$b/generated/playlist-commercial-v0.ffconcat"; report="$b/generated/playlist-commercial-v0.json"
  [[ -f "$cand" ]] && echo "  candidate_sha=$(sha256sum "$cand" | awk '{print $1}') events=$(grep -c '^file ' "$cand" 2>/dev/null || true)" || echo '  candidate=ABSENT'
  [[ -f "$report" ]] && sed -n '1,80p' "$report" | sed 's/^/  report: /' || true
done
[[ "$COMM_LAYOUT_OK" == 1 ]] && pass 'estrutura commercial nas 5 radios' || fail 'estrutura commercial incompleta'
kv commercial_media_assets_total "$REAL_ADS"
kv hour_assets_total "$HOUR_ASSETS"
kv schedule_files_total "$SCHEDULE_FILES"
kv real_playlog_files_total "$REAL_PLAYLOGS"
if [[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]]; then
  kv scheduler_sha256 "$(sha256sum /usr/local/sbin/tps-commercial-scheduler-v0 | awk '{print $1}')"
  if python3 - /usr/local/sbin/tps-commercial-scheduler-v0 <<'PY'
import ast,sys
ast.parse(open(sys.argv[1],encoding='utf-8').read())
PY
  then pass 'scheduler V0 sintaticamente valido'; else fail 'scheduler V0 com erro de sintaxe'; fi
else
  fail 'tps-commercial-scheduler-v0 ausente'
fi
[[ "$HOUR_ASSETS" -gt 0 ]] && pass 'assets de hora certa presentes' || warn 'hora certa ainda sem assets/implementacao operacional'
[[ "$SCHEDULE_FILES" -gt 0 ]] && pass 'grades comerciais presentes' || warn 'grade horaria comercial real ainda nao cadastrada'
[[ "$REAL_PLAYLOGS" -gt 0 ]] && pass 'playlog real detectado' || warn 'playlog real/prova de veiculacao ainda nao implementado'

hr "7. LAB COMERCIAL — RESIDUOS / ISOLAMENTO"
lab_state="$(systemctl is-active tps-radioprincipal-commercial-test.service 2>/dev/null || true)"
kv lab_unit "$lab_state"
lab_code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$MTX_API/v3/config/paths/get/radioprincipal-commercial-test" 2>/dev/null || true)"
kv lab_runtime_path_http "$lab_code"
if [[ "$lab_state" != active && "$lab_code" != 200 ]]; then pass 'LAB comercial sem residuo ativo'; else warn 'LAB comercial ainda possui estado runtime'; fi
if grep -Eq '^  radioprincipal-commercial-test:' "$MTX_CFG" 2>/dev/null; then warn 'path LAB persistido em mediamtx.yml'; else pass 'mediamtx.yml sem path LAB persistente'; fi

hr "8. MEDIAMTX — PATHS DAS 9 EMISSORAS"
api_json="$(curl -fsS --max-time 5 "$MTX_API/v3/paths/list" 2>/dev/null || true)"
if [[ -n "$api_json" ]]; then
  python3 -c 'import json,sys; d=json.load(sys.stdin); w=["radioprincipal","radiopop","radiorock","radioclassicas","radiocountry","tvkids","tvteens","tvviva","tvmaisjovem"]; m={x.get("name"):x for x in d.get("items",[])}; [print(f"{n:20} ready={m.get(n,{}).get(\"ready\",False)}") for n in w]' <<<"$api_json" || true
  pass 'API paths MediaMTX respondeu'
else
  fail 'API paths MediaMTX sem resposta'
fi

hr "9. TVs — STATUS RESUMIDO (SEM ALTERAR)"
for tv in "${TVS[@]}"; do
  unit="tps-${tv}-playout.service"
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  code="$(http_code "${HLS_BASE}/${tv}/index.m3u8")"
  printf '%-18s service=%-10s HLS=%s\n' "$tv" "$state" "$code"
done
journalctl --since '-30 min' --no-pager 2>/dev/null | grep -Ei 'tvkids|tvteens|tvviva|tvmaisjovem' | grep -Ei 'non-monotonic|dts|error|fail' | tail -n 40 || true

hr "10. NGINX — OWNERSHIP RADIO/TV E WEBROOTS"
nginx -T 2>/dev/null | grep -nE 'server_name .*studio.*sat|server_name .*tv(kids|teens|viva|maisjovem)|server_name .*radio' | tail -n 80 || true
for p in /var/www/studiosat-radio-portal /var/www/studiosat-radio-player /var/www/studiosat-tv/current /var/www/portais/www.tvkidsweb.studiosatweb.com.br; do
  [[ -e "$p" ]] && printf '%-55s exists=yes\n' "$p" || printf '%-55s exists=no\n' "$p"
done

hr "11. BACKUPS / RESTORE EVIDENCE"
for pattern in commercial-v0-pre commercial-lab-v0_2-pre commercial-lab-orchestrator tvkids-vhost-good CHG-TVWEB02; do
  latest="$(find /var/backups/studiosat -maxdepth 2 \( -type f -o -type d \) -name "*${pattern}*" 2>/dev/null | sort | tail -n1)"
  printf '%-30s %s\n' "$pattern" "${latest:-NONE}"
done

hr "12. REPOSITORIO / GOVERNANCA"
if [[ -d "$REPO/.git" ]]; then
  kv repo_branch "$(git -C "$REPO" branch --show-current 2>/dev/null || true)"
  local_head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"; kv repo_local_head "$local_head"
  dirty="$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l)"; kv repo_dirty_entries "$dirty"
  kv repo_origin "$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
  remote_head="$(git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}' | head -n1)"; kv repo_remote_main "${remote_head:-UNAVAILABLE}"
  [[ -n "$remote_head" && "$local_head" == "$remote_head" ]] && pass 'repo local == remote main' || warn 'repo local nao coincide com remote main ou remoto indisponivel'
  [[ "$dirty" -eq 0 ]] && pass 'working tree limpa' || warn "working tree possui $dirty alteracoes"
  git -C "$REPO" log -n 12 --date=iso --pretty='format:%h %ad %s' 2>/dev/null || true; echo
  for f in README.md docs/30-execucao/CHANGE_QUEUE.md candidates/CHG-RCOMM01/tps-commercial-lab-orchestrator-v0.2.3.sh; do [[ -f "$REPO/$f" ]] && echo "REPO_FILE_PRESENT=$f" || echo "REPO_FILE_ABSENT=$f"; done
else
  fail "repo mestre ausente em $REPO"
fi

hr "13. BACKLOG FUNCIONAL RADIO — DETECCAO FACTUAL"
[[ "$RADIO_ALL_OK" == 1 ]] && echo GATE_ONAIR_5_RADIOS=PASS || echo GATE_ONAIR_5_RADIOS=FAIL
[[ "$PLAYLISTS_OK" == 1 ]] && echo GATE_MUSIC_PLAYLISTS=PASS || echo GATE_MUSIC_PLAYLISTS=FAIL
[[ "$COMM_LAYOUT_OK" == 1 ]] && echo GATE_COMMERCIAL_LAYOUT=PASS || echo GATE_COMMERCIAL_LAYOUT=FAIL
[[ -x /usr/local/sbin/tps-commercial-scheduler-v0 ]] && echo GATE_SCHEDULER_V0=PRESENT || echo GATE_SCHEDULER_V0=ABSENT
[[ "$HOUR_ASSETS" -gt 0 ]] && echo GATE_HORA_CERTA=ASSETS_PRESENT || echo GATE_HORA_CERTA=NOT_READY
[[ "$SCHEDULE_FILES" -gt 0 ]] && echo GATE_COMMERCIAL_SCHEDULE=FILES_PRESENT || echo GATE_COMMERCIAL_SCHEDULE=NOT_READY
[[ "$REAL_PLAYLOGS" -gt 0 ]] && echo GATE_REAL_PLAYLOG=FILES_PRESENT || echo GATE_REAL_PLAYLOG=NOT_READY

hr "14. RESUMO EXECUTIVO"
kv PASS "$PASS_N"; kv WARN "$WARN_N"; kv FAIL "$FAIL_N"
[[ "$FAIL_N" -eq 0 ]] && echo RAYX_CORE_RESULT=PASS_WITH_POSSIBLE_WARNINGS || echo RAYX_CORE_RESULT=ATTENTION_REQUIRED
echo PROJECT_POSITION_HINT=RADIO_PRODUCTION_STABLE__COMMERCIAL_V0_BUILT__V1_CLOCK_SCHEDULE_PLAYLOG_GATES_PENDING
echo RAYX_READONLY_COMPLETE=1
