#!/usr/bin/env bash
# StudioSat Web — CHG-R01B transactional AAC/HLS cutover for Radio Principal
# Scope: /usr/local/sbin/tps-playout-radio + restart ONLY radioprincipal.
# No daemon-reload, no MediaMTX/NGINX restart, no other station restart.
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-radioprincipal-playout.service"
CH="radioprincipal"
PLAYOUT="/usr/local/sbin/tps-playout-radio"
GEN="/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed"
PL="/srv/tpsmedia/repository/channels/radioprincipal/playlists/playlist.txt"
EXPECTED_OLD_PLAYOUT_SHA="5920f385cc47aed6466b58ad48b26c7f9d4b2da2ba9aa17690ab1289691607e3"
EXPECTED_GEN_SHA="d2ba61daeeaaa89389fe1cc2ed277af68ac12c09b769c2eb9dda1feea9316fcd"
EXPECTED_PL_SHA="154c3cb081f9a7d7f527ab184739b692c5a930db3fe8ff0659f241e9699b821c"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
CAND="${SCRIPT_DIR}/tps-playout-radio-v2-principal-aac.sh"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-R01B-${TS}"
BK="/var/backups/studiosat/CHG-R01B/${TS}"
REPORT="${OUT}/REPORT.txt"
MUTATED=0
RESTARTED=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in bash git sha256sum systemctl ffmpeg ffprobe timeout nice curl jq grep awk sed stat install cp mv mktemp tar journalctl; do need "$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT" >&2; exit 77; }

install -d -m 0755 "$OUT"
install -d -m 0700 "$BK"
exec > >(tee "$REPORT") 2>&1

sha_of(){ sha256sum "$1" | awk '{print $1}'; }
fail(){ echo "FATAL=$*" >&2; return 1; }

rollback(){
  echo "ROLLBACK=START"
  if [[ -f "$BK/tps-playout-radio.previous" ]]; then
    tmp="$(mktemp "$(dirname "$PLAYOUT")/.tps-playout-radio.rollback.XXXXXX")"
    cp -a -- "$BK/tps-playout-radio.previous" "$tmp"
    mv -f -- "$tmp" "$PLAYOUT"
  fi
  if (( RESTARTED == 1 )); then
    systemctl restart "$UNIT" || true
    sleep 3
  fi
  echo "ROLLBACK=DONE"
}

trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

echo "CHG-R01B Radio Principal AAC/HLS transactional cutover"
echo "UTC=$TS"
echo "OUT=$OUT"
echo "PRIVATE_BACKUP=$BK"

echo "=== A. REPOSITORY / LOCK GATES ==="
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || fail "GIT_WORKTREE_NOT_CLEAN"
[[ -f "$CAND" ]] || fail "CANDIDATE_MISSING"
bash -n "$CAND"
[[ "$(sha_of "$PLAYOUT")" == "$EXPECTED_OLD_PLAYOUT_SHA" ]] || fail "PLAYOUT_DRIFT"
[[ "$(sha_of "$GEN")" == "$EXPECTED_GEN_SHA" ]] || fail "PRINCIPAL_GENERATOR_DRIFT"
[[ "$(sha_of "$PL")" == "$EXPECTED_PL_SHA" ]] || fail "PRINCIPAL_PLAYLIST_DRIFT"
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || fail "PRINCIPAL_NOT_ACTIVE_PRE"
echo "git_head=$(git rev-parse HEAD)"
echo "candidate_sha=$(sha_of "$CAND")"
echo "locked_state=PASS"

echo "=== B. PRECHECK AAC FULL PLAYLIST — NO PRODUCTION MUTATION ==="
set +e
timeout 600 nice -n 15 ffmpeg -hide_banner -nostdin -loglevel warning \
  -f concat -safe 0 -i "$PL" \
  -map 0:a:0 \
  -af "aresample=48000:async=1:first_pts=0" \
  -c:a aac -profile:a aac_low -b:a 192k -ar 48000 -ac 2 \
  -f null - \
  >"$OUT/aac-full.stdout" 2>"$OUT/aac-full.stderr"
AAC_RC=$?
set -e
cat "$OUT/aac-full.stderr"
echo "aac_full_rc=$AAC_RC"
[[ "$AAC_RC" -eq 0 ]] || fail "AAC_FULL_TRAVERSAL_FAILED"
DTS_PRE="$(grep -Eic 'non[- ]?monoton|non monotonically increasing|DTS.*out of order' "$OUT/aac-full.stderr" || true)"
echo "aac_full_dts_warnings=$DTS_PRE"
[[ "$DTS_PRE" -eq 0 ]] || fail "AAC_FULL_TRAVERSAL_HAS_DTS_WARNINGS"
echo "AAC_FULL_TRAVERSAL=PASS"

echo "=== C. BACKUP / PRE-IMPACT SNAPSHOT ==="
cp -a -- "$PLAYOUT" "$BK/tps-playout-radio.previous"
sha256sum "$BK/tps-playout-radio.previous" > "$BK/SHA256SUMS.txt"
printf 'unit\tpid\n' > "$OUT/pids.pre.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.pre.tsv"
done
PRE_PID="$(systemctl show "$UNIT" -p MainPID --value)"
echo "principal_pre_pid=$PRE_PID"
echo "backup=PASS"

echo "=== D. ATOMIC PLAYOUT PROMOTION ==="
uid="$(stat -c '%u' "$PLAYOUT")"; gid="$(stat -c '%g' "$PLAYOUT")"; mode="$(stat -c '%a' "$PLAYOUT")"
tmp="$(mktemp "$(dirname "$PLAYOUT")/.tps-playout-radio.CHG-R01B.XXXXXX")"
install -o "$uid" -g "$gid" -m "$mode" "$CAND" "$tmp"
bash -n "$tmp"
mv -f -- "$tmp" "$PLAYOUT"
MUTATED=1
[[ "$(sha_of "$PLAYOUT")" == "$(sha_of "$CAND")" ]] || fail "PLAYOUT_PROMOTION_HASH_MISMATCH"
echo "playout_new_sha=$(sha_of "$PLAYOUT")"

echo "=== E. RESTART ONLY PRINCIPAL ==="
RESTART_SINCE="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RESTARTED=1
systemctl restart "$UNIT"
for _ in $(seq 1 30); do
  [[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] && break
  sleep 1
done
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || fail "PRINCIPAL_NOT_ACTIVE_POST"
POST_PID="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$POST_PID" =~ ^[1-9][0-9]*$ ]] || fail "PRINCIPAL_POST_PID_INVALID"
[[ "$POST_PID" != "$PRE_PID" ]] || fail "PRINCIPAL_PID_DID_NOT_CHANGE"
echo "principal_post_pid=$POST_PID"

echo "=== F. MEDIAMTX / RTSP AAC ==="
READY=""
for _ in $(seq 1 30); do
  READY="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[] | select(.name=="radioprincipal") | .ready' | head -n1 || true)"
  [[ "$READY" == "true" ]] && break
  sleep 1
done
[[ "$READY" == "true" ]] || fail "MEDIAMTX_NOT_READY"
curl -fsS http://127.0.0.1:9997/v3/paths/list | jq -c '.items[] | select(.name=="radioprincipal") | {name,ready,tracks,bytesReceived}' | tee "$OUT/mediamtx.json"
timeout 15 ffprobe -v error -rtsp_transport tcp -select_streams a:0 \
  -show_entries stream=codec_name,sample_rate,channels \
  -of default=noprint_wrappers=1 \
  rtsp://127.0.0.1:8554/radioprincipal | tee "$OUT/rtsp.txt"
grep -qx 'codec_name=aac' "$OUT/rtsp.txt" || fail "RTSP_NOT_AAC"
grep -qx 'sample_rate=48000' "$OUT/rtsp.txt" || fail "RTSP_NOT_48K"
grep -qx 'channels=2' "$OUT/rtsp.txt" || fail "RTSP_NOT_STEREO"

echo "=== G. HLS LOCAL ==="
HLS_LOCAL="http://127.0.0.1:8888/radioprincipal/index.m3u8"
LOCAL_OK=0
for _ in $(seq 1 40); do
  if curl -fsS --connect-timeout 2 --max-time 5 "$HLS_LOCAL" -o "$OUT/hls-local.m3u8" 2>/dev/null && grep -q '^#EXTM3U' "$OUT/hls-local.m3u8"; then LOCAL_OK=1; break; fi
  sleep 1
done
[[ "$LOCAL_OK" -eq 1 ]] || fail "HLS_LOCAL_MANIFEST_FAILED"
head -40 "$OUT/hls-local.m3u8"
timeout 20 ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 "$HLS_LOCAL" | tee "$OUT/hls-local-ffprobe.txt"
grep -qx 'codec_name=aac' "$OUT/hls-local-ffprobe.txt" || fail "HLS_LOCAL_NOT_AAC"
echo "HLS_LOCAL=PASS"

echo "=== H. HLS THROUGH NGINX/TLS ==="
HLS_PUBLIC="https://radio.studiosatweb.com.br/radioprincipal/index.m3u8"
curl -fsS --resolve radio.studiosatweb.com.br:443:127.0.0.1 --connect-timeout 3 --max-time 10 "$HLS_PUBLIC" -o "$OUT/hls-public.m3u8"
grep -q '^#EXTM3U' "$OUT/hls-public.m3u8" || fail "HLS_PUBLIC_NOT_MANIFEST"
head -40 "$OUT/hls-public.m3u8"
echo "HLS_PUBLIC_NGINX_TLS=PASS"

echo "=== I. NEW PROCESS JOURNAL MUST BE CLEAN ==="
journalctl _PID="$POST_PID" --since "$RESTART_SINCE" --no-pager -o short-iso > "$OUT/journal-new-pid.txt" || true
cat "$OUT/journal-new-pid.txt"
ERRS="$(grep -Eic 'Impossible to open|NO_READY_MEDIA|non[- ]?monoton|Failed to update header|Conversion failed|Invalid data found|Error opening' "$OUT/journal-new-pid.txt" || true)"
echo "new_pid_relevant_errors=$ERRS"
[[ "$ERRS" -eq 0 ]] || fail "NEW_PID_HAS_RELEVANT_ERRORS"

echo "=== J. NO OTHER SERVICE RESTARTED ==="
printf 'unit\tpid\n' > "$OUT/pids.post.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.post.tsv"
done
while IFS=$'\t' read -r u pre; do
  [[ "$u" == "unit" || "$u" == "$UNIT" ]] && continue
  post="$(awk -F '\t' -v u="$u" '$1==u{print $2}' "$OUT/pids.post.tsv")"
  [[ "$pre" == "$post" ]] || fail "UNEXPECTED_PID_CHANGE:$u:$pre:$post"
done < "$OUT/pids.pre.tsv"
echo "other_pids_unchanged=PASS"

echo "=== K. SHAREABLE / RESULT ==="
tar -C /tmp -czf "/tmp/CHG-R01B-${TS}.shareable.tar.gz" "CHG-R01B-${TS}"
sha256sum "/tmp/CHG-R01B-${TS}.shareable.tar.gz" | tee "/tmp/CHG-R01B-${TS}.shareable.tar.gz.sha256"
echo "CHG_R01B_RESULT=PASS"
echo "PRINCIPAL_CODEC=AAC_LC_48000_STEREO"
echo "MEDIAMTX=READY"
echo "RTSP=PASS"
echo "HLS_LOCAL=PASS"
echo "HLS_PUBLIC_NGINX_TLS=PASS"
echo "NEW_PID_ERRORS=0"
echo "ROTATION_REAL=PENDING_DETACHED_OBSERVER"
echo "SHAREABLE=/tmp/CHG-R01B-${TS}.shareable.tar.gz"
echo "PRIVATE_BACKUP=$BK"
trap - EXIT
