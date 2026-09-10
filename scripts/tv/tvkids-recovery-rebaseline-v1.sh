#!/usr/bin/env bash
# StudioSat Web — TVKIDS Recovery Rebaseline
# Version: 1.0
# Owner: Engenharia TV
# Safety class: read-only
# Purpose: reconstruir o estado factual da TVKIDS após execução intercalada no host
#          e, se os invariantes P1 permanecerem válidos, executar o diagnóstico P2.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

UNIT="tps-tvkids-playout.service"
CH="tvkids"
BASE="/srv/tpsmedia/repository/channels/${CH}"
CAN="${BASE}/canonical"
READY="${BASE}/ready"
PL="${BASE}/playlists/playlist.txt"
GEN="/usr/local/sbin/tps-generate-playlist"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
P2="${REPO}/scripts/tv/tvkids-p2-dts-boundary-diagnostic.sh"
OUT="/tmp/tvkids-recovery-rebaseline-${TS}"
REPORT="${OUT}/REPORT.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in systemctl sha256sum ffprobe ffmpeg curl jq nginx git grep awk sed find sort stat readlink tar date ps wc head tail bash install; do need "$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT" >&2; exit 77; }

install -d -m 0755 "$OUT"
exec > >(tee "$REPORT") 2>&1

fail(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
count_pat(){ grep -c "$1" "$2" 2>/dev/null || true; }

printf 'TVKIDS RECOVERY REBASELINE v1.0\nUTC=%s\nREPO=%s\n\n' "$TS" "$REPO"

printf '=== A. GIT / FONTE DA VERDADE ===\n'
cd "$REPO"
echo "git_head=$(git rev-parse HEAD)"
echo "origin_main=$(git rev-parse origin/main 2>/dev/null || echo UNKNOWN)"
echo "git_branch=$(git branch --show-current)"
git status --porcelain=v1 -uall | tee "$OUT/git-status.txt"
if [[ -s "$OUT/git-status.txt" ]]; then
  echo "git_worktree=CURRENTLY_DIRTY"
else
  echo "git_worktree=CLEAN"
fi

echo
printf '=== B. PROCESSOS DE CHANGE / OBSERVERS DETECTADOS ===\n'
ps -eo pid=,ppid=,etimes=,args= | grep -E 'apply-radioprincipal|observe-radioprincipal|apply-.*(radio|tv)|tvkids-p[0-9]|studiosat.*(apply|observer|rotation)' | grep -v -E 'grep -E|tvkids-recovery-rebaseline-v1' | tee "$OUT/change-processes.txt" || true
if [[ -s "$OUT/change-processes.txt" ]]; then
  echo "change_processes=DETECTED"
else
  echo "change_processes=NONE_DETECTED"
fi

echo
printf '=== C. TVKIDS SYSTEMD / PROCESSO REAL ===\n'
systemctl show "$UNIT" -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp -p NRestarts -p NeedDaemonReload --no-pager | tee "$OUT/tvkids-unit-show.txt"
ACTIVE="$(systemctl is-active "$UNIT" || true)"
PID="$(systemctl show "$UNIT" -p MainPID --value)"
echo "active=$ACTIVE"
echo "pid=$PID"
[[ "$ACTIVE" == "active" ]] || fail "TVKIDS_NOT_ACTIVE"
[[ "$PID" =~ ^[1-9][0-9]*$ && -d "/proc/$PID" ]] || fail "TVKIDS_MAINPID_INVALID"
tr '\0' ' ' < "/proc/$PID/cmdline" | tee "$OUT/tvkids-cmdline.txt"
echo
systemctl cat "$UNIT" > "$OUT/tvkids-unit-cat.txt"

echo
printf '=== D. PLAYLIST ON-AIR x PLAYLIST EM DISCO ===\n'
RUNFD=""
for fd in /proc/"$PID"/fd/*; do
  target="$(readlink "$fd" 2>/dev/null || true)"
  if [[ "$target" == *"/channels/tvkids/playlists/playlist.txt"* ]]; then
    RUNFD="$fd"
    echo "running_playlist_fd=$fd"
    echo "running_playlist_target=$target"
    break
  fi
done
[[ -n "$RUNFD" ]] || fail "RUNNING_PLAYLIST_FD_NOT_FOUND"
[[ -f "$PL" ]] || fail "DISK_PLAYLIST_MISSING"
cp -L -- "$RUNFD" "$OUT/playlist.running.ffconcat"
cp -a -- "$PL" "$OUT/playlist.disk.ffconcat"
RUN_SHA="$(sha "$OUT/playlist.running.ffconcat")"
DISK_SHA="$(sha "$OUT/playlist.disk.ffconcat")"
RUN_FILES="$(count_pat '^file ' "$OUT/playlist.running.ffconcat")"
RUN_CAN="$(count_pat '/canonical/' "$OUT/playlist.running.ffconcat")"
RUN_READY="$(count_pat '/ready/' "$OUT/playlist.running.ffconcat")"
DISK_FILES="$(count_pat '^file ' "$OUT/playlist.disk.ffconcat")"
DISK_CAN="$(count_pat '/canonical/' "$OUT/playlist.disk.ffconcat")"
DISK_READY="$(count_pat '/ready/' "$OUT/playlist.disk.ffconcat")"
echo "running_sha=$RUN_SHA files=$RUN_FILES canonical=$RUN_CAN ready=$RUN_READY"
echo "disk_sha=$DISK_SHA files=$DISK_FILES canonical=$DISK_CAN ready=$DISK_READY"
if [[ "$RUN_SHA" == "$DISK_SHA" ]]; then echo "playlist_identity=PASS"; else echo "playlist_identity=FAIL"; fi

printf '\n=== E. GENERATOR / RESTART GUARD INSTALADO ===\n'
[[ -f "$GEN" ]] || fail "GENERATOR_MISSING"
echo "generator_sha=$(sha "$GEN")"
grep -n -B3 -A8 -E 'MEDIA_ROOT|TVKIDS_RESTART_GUARD|canonical' "$GEN" | tee "$OUT/generator-relevant.txt" || true
if grep -q 'TVKIDS_RESTART_GUARD' "$GEN" && grep -q 'MEDIA_ROOT="${BASE}/canonical"' "$GEN"; then
  echo "restart_guard=PASS"
else
  echo "restart_guard=FAIL"
fi

printf '\n=== F. FILESYSTEM / CANONICAL / READY ===\n'
CAN_COUNT="$(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -printf x 2>/dev/null | wc -c | tr -d ' ')"
READY_COUNT="$(find "$READY" -maxdepth 1 -type f -printf x 2>/dev/null | wc -c | tr -d ' ')"
echo "canonical_mp4_count=$CAN_COUNT"
echo "ready_file_count=$READY_COUNT"
printf 'file\tvcodec\twidth\theight\tfps\tpix_fmt\tacodec\trate\tchannels\tlayout\n' > "$OUT/canonical-profile.tsv"
while IFS= read -r -d '' f; do
  v="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt -of csv=p=0 "$f" 2>/dev/null || true)"
  a="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,channel_layout -of csv=p=0 "$f" 2>/dev/null || true)"
  printf '%s\t%s\t%s\n' "$(basename "$f")" "$v" "$a" >> "$OUT/canonical-profile.tsv"
done < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)

printf '\n=== G. MEDIAMTX / STREAM LOCAL ===\n'
if curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:9997/v3/paths/list > "$OUT/mediamtx-paths.json"; then
  jq -c '.items[] | select(.name=="tvkids") | {name,ready,tracks,bytesReceived}' "$OUT/mediamtx-paths.json" | tee "$OUT/mediamtx-tvkids.json" || true
else
  echo "mediamtx_api=UNAVAILABLE"
fi
set +e
timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=index,codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels -of compact=p=0:nk=0 rtsp://127.0.0.1:8554/tvkids | tee "$OUT/rtsp-tvkids.txt"
RTSP_RC=${PIPESTATUS[0]}
set -e
echo "rtsp_probe_rc=$RTSP_RC"
LOCAL_HLS_CODE="$(curl -sS --connect-timeout 3 --max-time 8 -o "$OUT/local-tvkids.m3u8" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
echo "local_hls_http=$LOCAL_HLS_CODE"

printf '\n=== H. NGINX / QUATRO FQDNS ===\n'
set +e
nginx -t 2>&1 | tee "$OUT/nginx-test.txt"
NGINX_T_RC=${PIPESTATUS[0]}
nginx -T > "$OUT/nginx-T.txt" 2>&1
NGINX_DUMP_RC=$?
set -e
echo "nginx_test_rc=$NGINX_T_RC"
echo "nginx_dump_rc=$NGINX_DUMP_RC"
grep -n -B8 -A35 -E 'tvkids(web)?\.studiosatweb\.com\.br' "$OUT/nginx-T.txt" > "$OUT/nginx-tvkids-context.txt" || true
printf 'host\troot\ttvkids_html\thls\n' > "$OUT/public-http.tsv"
for host in www.tvkidsweb.studiosatweb.com.br tvkidsweb.studiosatweb.com.br tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br; do
  root="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/" || echo ERR)"
  html="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/tvkids.html" || echo ERR)"
  hls="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/tvkids/index.m3u8" || echo ERR)"
  printf '%s\t%s\t%s\t%s\n' "$host" "$root" "$html" "$hls" | tee -a "$OUT/public-http.tsv"
done

printf '\n=== I. JOURNAL TVKIDS / INTEGRIDADE TEMPORAL ===\n'
journalctl -u "$UNIT" --since '-60 min' --no-pager -o short-iso > "$OUT/tvkids-journal-60m.txt" || true
DTS60="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$OUT/tvkids-journal-60m.txt" || true)"
ERR60="$(grep -Eic 'Invalid data|No start code|Impossible to open|Connection refused|segfault|core dump|Broken pipe|Conversion failed' "$OUT/tvkids-journal-60m.txt" || true)"
echo "tvkids_dts_last60m=$DTS60"
echo "tvkids_other_errors_last60m=$ERR60"

printf '\n=== J. ISOLAMENTO — PIDS DAS 9 STATIONS + CORE ===\n'
printf 'unit\tactive\tpid\n' > "$OUT/pids.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\t%s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || true)" "$(systemctl show "$u" -p MainPID --value 2>/dev/null || true)" | tee -a "$OUT/pids.tsv"
done

printf '\n=== K. GATE PARA P2 ===\n'
P2_GATE=PASS
[[ "$RUN_SHA" == "$DISK_SHA" ]] || P2_GATE=BLOCKED_PLAYLIST_IDENTITY
[[ "$DISK_FILES" -gt 1 && "$DISK_CAN" -eq "$DISK_FILES" && "$DISK_READY" -eq 0 ]] || P2_GATE=BLOCKED_PLAYLIST_NOT_CANONICAL
[[ -f "$P2" ]] || P2_GATE=BLOCKED_P2_MISSING
if [[ -f "$P2" ]]; then
  if ! bash -n "$P2"; then P2_GATE=BLOCKED_P2_SYNTAX; fi
fi
echo "p2_gate=$P2_GATE"

P2_RC=99
if [[ "$P2_GATE" == "PASS" ]]; then
  printf '\n=== L. EXECUCAO P2 — SOMENTE LEITURA ===\n'
  set +e
  bash "$P2" | tee "$OUT/p2-console.txt"
  P2_RC=${PIPESTATUS[0]}
  set -e
  echo "p2_rc=$P2_RC"
else
  echo "p2_rc=SKIPPED"
fi

printf '\n=== M. ESTADO FINAL DO PROCESSO TVKIDS ===\n'
PID_AFTER="$(systemctl show "$UNIT" -p MainPID --value)"
ACTIVE_AFTER="$(systemctl is-active "$UNIT" || true)"
echo "active_after=$ACTIVE_AFTER"
echo "pid_before=$PID"
echo "pid_after=$PID_AFTER"
if [[ "$ACTIVE_AFTER" == "active" && "$PID_AFTER" == "$PID" ]]; then
  echo "tvkids_process_stability=PASS"
else
  echo "tvkids_process_stability=CHANGED"
fi

TARBALL="/tmp/tvkids-recovery-rebaseline-${TS}.shareable.tar.gz"
tar -C /tmp -czf "$TARBALL" "tvkids-recovery-rebaseline-${TS}"
sha256sum "$TARBALL" | tee "${TARBALL}.sha256"

echo
echo "=== RESULTADO DOCUMENTAL ==="
echo "shareable=$TARBALL"
echo "sha256=${TARBALL}.sha256"
echo "p2_gate=$P2_GATE"
echo "p2_rc=$P2_RC"
echo "tvkids_pid_before=$PID"
echo "tvkids_pid_after=$PID_AFTER"
echo "TVKIDS_RECOVERY_REBASELINE=DONE"
