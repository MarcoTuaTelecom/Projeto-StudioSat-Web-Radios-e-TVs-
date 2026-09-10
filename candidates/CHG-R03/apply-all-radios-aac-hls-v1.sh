#!/usr/bin/env bash
# StudioSat Web — CHG-R03
# Transactional cutover of all five radio playouts to AAC-LC 48 kHz stereo.
# Shared MediaMTX and NGINX are NOT restarted or reloaded here.
set -Eeuo pipefail
IFS=$'\n\t'

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
PLAYOUT=/usr/local/sbin/tps-playout-radio
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
CAND="$SCRIPT_DIR/tps-playout-radio-v3-aac-all.sh"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-R03-${TS}"
BK="/var/backups/studiosat/CHG-R03/${TS}"
REPORT="$OUT/REPORT.txt"
MUTATED=0
converted=()
current_radio=""

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in bash git sha256sum systemctl ffmpeg ffprobe timeout nice curl jq grep awk sed stat install cp mv mktemp tar journalctl seq head; do need "$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT' >&2; exit 77; }

install -d -m 0755 "$OUT"
install -d -m 0700 "$BK"
exec > >(tee "$REPORT") 2>&1

sha_of(){ sha256sum "$1" | awk '{print $1}'; }
fail(){ echo "FATAL=$*" >&2; return 1; }
unit_of(){ printf 'tps-%s-playout.service' "$1"; }
playlist_of(){ printf '/srv/tpsmedia/repository/channels/%s/playlists/playlist.txt' "$1"; }

rollback(){
  echo 'ROLLBACK=START'
  if [[ -f "$BK/tps-playout-radio.previous" ]]; then
    tmp="$(mktemp "$(dirname "$PLAYOUT")/.tps-playout-radio.rollback.XXXXXX")"
    cp -a -- "$BK/tps-playout-radio.previous" "$tmp"
    mv -f -- "$tmp" "$PLAYOUT"
  fi
  declare -A seen=()
  for ch in "${converted[@]}" "$current_radio"; do
    [[ -n "$ch" ]] || continue
    [[ -z "${seen[$ch]:-}" ]] || continue
    seen[$ch]=1
    echo "ROLLBACK_RESTART=$ch"
    systemctl restart "$(unit_of "$ch")" || true
    sleep 2
  done
  echo 'ROLLBACK=DONE'
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

echo 'CHG-R03 — FIVE RADIOS AAC/HLS CUTOVER'
echo "UTC=$TS"
echo "OUT=$OUT"
echo "PRIVATE_BACKUP=$BK"

echo '=== A. REPOSITORY / CANDIDATE GATES ==='
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || fail 'GIT_WORKTREE_NOT_CLEAN'
[[ -f "$CAND" ]] || fail 'CANDIDATE_MISSING'
bash -n "$CAND"
[[ -f "$PLAYOUT" ]] || fail 'CURRENT_PLAYOUT_MISSING'
CURRENT_SHA="$(sha_of "$PLAYOUT")"
echo "current_playout_sha=$CURRENT_SHA"
echo "candidate_sha=$(sha_of "$CAND")"
# Known production states: legacy stream-copy or Principal-only AAC candidate.
case "$CURRENT_SHA" in
  5920f385cc47aed6466b58ad48b26c7f9d4b2da2ba9aa17690ab1289691607e3|f0c71d3e800ac711295a38bb55f4d8eb5068120e16fba8debadef802f83637be) ;;
  *) fail "PLAYOUT_DRIFT:$CURRENT_SHA" ;;
esac

echo '=== B. PLAYLIST + 30s AAC PRECHECK FOR EACH RADIO ==='
for ch in "${RADIOS[@]}"; do
  pl="$(playlist_of "$ch")"
  [[ -r "$pl" ]] || fail "PLAYLIST_NOT_READABLE:$ch"
  count="$(grep -c '^file ' "$pl" || true)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || fail "PLAYLIST_EMPTY:$ch"
  echo "$ch playlist_items=$count"
  set +e
  timeout 60 nice -n 15 ffmpeg -hide_banner -nostdin -loglevel error \
    -f concat -safe 0 -i "$pl" -t 30 -map 0:a:0 \
    -af 'aresample=48000:async=1:first_pts=0' \
    -c:a aac -profile:a aac_low -b:a 192k -ar 48000 -ac 2 \
    -f null - >"$OUT/${ch}.pre.stdout" 2>"$OUT/${ch}.pre.stderr"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || { cat "$OUT/${ch}.pre.stderr"; fail "AAC_PRECHECK_FAILED:$ch:$rc"; }
  [[ ! -s "$OUT/${ch}.pre.stderr" ]] || cat "$OUT/${ch}.pre.stderr"
  echo "$ch AAC_PRECHECK=PASS"
done

echo '=== C. BACKUP / PRE SNAPSHOT ==='
cp -a -- "$PLAYOUT" "$BK/tps-playout-radio.previous"
sha256sum "$BK/tps-playout-radio.previous" > "$BK/SHA256SUMS.txt"
printf 'channel\tstate\tpid\n' > "$OUT/radios.pre.tsv"
for ch in "${RADIOS[@]}"; do
  unit="$(unit_of "$ch")"
  printf '%s\t%s\t%s\n' "$ch" "$(systemctl is-active "$unit" || true)" "$(systemctl show "$unit" -p MainPID --value)" >> "$OUT/radios.pre.tsv"
done
for u in tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/nonradio.pre.tsv"
done

echo '=== D. ATOMIC PROMOTION OF RADIO PLAYOUT ==='
uid="$(stat -c '%u' "$PLAYOUT")"; gid="$(stat -c '%g' "$PLAYOUT")"; mode="$(stat -c '%a' "$PLAYOUT")"
tmp="$(mktemp "$(dirname "$PLAYOUT")/.tps-playout-radio.CHG-R03.XXXXXX")"
install -o "$uid" -g "$gid" -m "$mode" "$CAND" "$tmp"
bash -n "$tmp"
mv -f -- "$tmp" "$PLAYOUT"
MUTATED=1
[[ "$(sha_of "$PLAYOUT")" == "$(sha_of "$CAND")" ]] || fail 'PLAYOUT_PROMOTION_HASH_MISMATCH'
echo "playout_new_sha=$(sha_of "$PLAYOUT")"

echo '=== E. ONE RADIO AT A TIME: RESTART + RTSP + HLS ==='
for ch in "${RADIOS[@]}"; do
  current_radio="$ch"
  unit="$(unit_of "$ch")"
  pre_pid="$(systemctl show "$unit" -p MainPID --value)"
  since="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "----- $ch -----"
  echo "$ch pre_pid=$pre_pid pre_state=$(systemctl is-active "$unit" || true)"
  systemctl reset-failed "$unit" 2>/dev/null || true
  systemctl restart "$unit"
  active=''
  for _ in $(seq 1 30); do
    active="$(systemctl is-active "$unit" || true)"
    [[ "$active" == active ]] && break
    sleep 1
  done
  [[ "$active" == active ]] || fail "SERVICE_NOT_ACTIVE:$ch"
  post_pid="$(systemctl show "$unit" -p MainPID --value)"
  [[ "$post_pid" =~ ^[1-9][0-9]*$ ]] || fail "BAD_PID:$ch:$post_pid"
  echo "$ch post_pid=$post_pid"

  ready=''
  tracks=''
  for _ in $(seq 1 30); do
    path_json="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null || true)"
    ready="$(jq -r --arg ch "$ch" '.items[] | select(.name==$ch) | .ready' <<<"$path_json" | head -n1 || true)"
    tracks="$(jq -r --arg ch "$ch" '.items[] | select(.name==$ch) | (.tracks // []) | join(",")' <<<"$path_json" | head -n1 || true)"
    [[ "$ready" == true ]] && break
    sleep 1
  done
  [[ "$ready" == true ]] || fail "MEDIAMTX_NOT_READY:$ch"
  echo "$ch mediamtx_ready=true tracks=$tracks"

  timeout 15 ffprobe -v error -rtsp_transport tcp -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of default=noprint_wrappers=1 "rtsp://127.0.0.1:8554/$ch" >"$OUT/${ch}.rtsp.txt"
  cat "$OUT/${ch}.rtsp.txt"
  grep -qx 'codec_name=aac' "$OUT/${ch}.rtsp.txt" || fail "RTSP_NOT_AAC:$ch"
  grep -qx 'sample_rate=48000' "$OUT/${ch}.rtsp.txt" || fail "RTSP_NOT_48K:$ch"
  grep -qx 'channels=2' "$OUT/${ch}.rtsp.txt" || fail "RTSP_NOT_STEREO:$ch"

  local_url="http://127.0.0.1:8888/$ch/index.m3u8"
  hls_ok=0
  for _ in $(seq 1 40); do
    code="$(curl -sSL --connect-timeout 2 --max-time 8 -o "$OUT/${ch}.local.m3u8" -w '%{http_code}' "$local_url" 2>/dev/null || true)"
    if [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$OUT/${ch}.local.m3u8"; then hls_ok=1; break; fi
    sleep 1
  done
  [[ "$hls_ok" -eq 1 ]] || { echo "$ch final_hls_http=${code:-unknown}"; cat "$OUT/${ch}.local.m3u8" 2>/dev/null || true; fail "HLS_LOCAL_FAILED:$ch"; }
  echo "$ch HLS_LOCAL=PASS"

  public_url="https://radio.studiosatweb.com.br/$ch/index.m3u8"
  public_code="$(curl -ksSL --resolve radio.studiosatweb.com.br:443:127.0.0.1 --connect-timeout 3 --max-time 10 -o "$OUT/${ch}.public.m3u8" -w '%{http_code}' "$public_url" || true)"
  [[ "$public_code" == 200 ]] || fail "HLS_PUBLIC_HTTP:$ch:$public_code"
  grep -q '^#EXTM3U' "$OUT/${ch}.public.m3u8" || { cat "$OUT/${ch}.public.m3u8"; fail "HLS_PUBLIC_NOT_MANIFEST:$ch"; }
  echo "$ch HLS_PUBLIC=PASS"

  journalctl _PID="$post_pid" --since "$since" --no-pager -o short-iso >"$OUT/${ch}.journal.txt" || true
  errs="$(grep -Eic 'Impossible to open|NO_READY_MEDIA|non[- ]?monoton|Conversion failed|Invalid data found|Error opening' "$OUT/${ch}.journal.txt" || true)"
  echo "$ch new_pid_relevant_errors=$errs"
  [[ "$errs" -eq 0 ]] || { cat "$OUT/${ch}.journal.txt"; fail "NEW_PID_ERRORS:$ch:$errs"; }

  converted+=("$ch")
  current_radio=''
done

echo '=== F. NON-RADIO PROCESSES UNCHANGED ==='
while IFS=$'\t' read -r u pre; do
  [[ -n "$u" ]] || continue
  post="$(systemctl show "$u" -p MainPID --value)"
  echo "$u pre=$pre post=$post"
  [[ "$pre" == "$post" ]] || fail "NONRADIO_PID_CHANGED:$u:$pre:$post"
done < "$OUT/nonradio.pre.tsv"

echo '=== G. FINAL FIVE-RADIO MATRIX ==='
for ch in "${RADIOS[@]}"; do
  unit="$(unit_of "$ch")"
  state="$(systemctl is-active "$unit" || true)"
  ready="$(curl -fsS http://127.0.0.1:9997/v3/paths/list | jq -r --arg ch "$ch" '.items[] | select(.name==$ch) | .ready' | head -n1)"
  printf '%-18s service=%-8s mediamtx=%s hls=PASS codec=AAC\n' "$ch" "$state" "$ready"
  [[ "$state" == active && "$ready" == true ]] || fail "FINAL_MATRIX_FAILED:$ch"
done

tar -C /tmp -czf "/tmp/CHG-R03-${TS}.shareable.tar.gz" "CHG-R03-${TS}"
sha256sum "/tmp/CHG-R03-${TS}.shareable.tar.gz" | tee "/tmp/CHG-R03-${TS}.shareable.tar.gz.sha256"

echo 'CHG_R03_RESULT=PASS'
echo 'FIVE_RADIOS_SERVICE=ACTIVE'
echo 'FIVE_RADIOS_MEDIAMTX=READY'
echo 'FIVE_RADIOS_CODEC=AAC_LC_48000_STEREO'
echo 'FIVE_RADIOS_HLS_LOCAL=PASS'
echo 'FIVE_RADIOS_HLS_PUBLIC=PASS'
echo 'NONRADIO_RESTARTS=0'
echo "SHAREABLE=/tmp/CHG-R03-${TS}.shareable.tar.gz"
trap - EXIT
