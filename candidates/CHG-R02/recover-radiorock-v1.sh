#!/usr/bin/env bash
# StudioSat Web — CHG-R02 Radio Rock controlled recovery v1
# Purpose: recover the existing Rock legacy playout without changing shared architecture.
# Scope: Rock playlist + reset-failed/start ONLY tps-radiorock-playout.service.
# No daemon-reload, no MediaMTX/NGINX restart, no other station restart.
set -Eeuo pipefail
IFS=$'\n\t'

CH="radiorock"
UNIT="tps-radiorock-playout.service"
BASE="/srv/tpsmedia/repository/channels/${CH}"
READY="${BASE}/ready"
PLDIR="${BASE}/playlists"
PL="${PLDIR}/playlist.txt"
GLOBAL_GEN="/usr/local/sbin/tps-generate-playlist"
EXPECTED=10
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-R02-${TS}"
BK="/var/backups/studiosat/CHG-R02/${TS}"
CAND="${OUT}/playlist.candidate"
REPORT="${OUT}/REPORT.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in bash git systemctl sha256sum find sort basename ffprobe ffmpeg timeout nice install cp mv mktemp curl jq grep awk tar journalctl; do need "$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT" >&2; exit 77; }
[[ -d "$READY" ]] || { echo "FATAL=READY_DIR_MISSING" >&2; exit 66; }
[[ -d "$PLDIR" ]] || { echo "FATAL=PLAYLIST_DIR_MISSING" >&2; exit 66; }
[[ -x "$GLOBAL_GEN" ]] || { echo "FATAL=GLOBAL_GENERATOR_MISSING_OR_NOT_EXECUTABLE" >&2; exit 66; }

install -d -m 0755 "$OUT"
install -d -m 0700 "$BK"
exec > >(tee "$REPORT") 2>&1

sha_of(){ sha256sum "$1" | awk '{print $1}'; }

restore_playlist(){
  if [[ -f "$BK/playlist.previous" ]]; then
    cp -a -- "$BK/playlist.previous" "$PL"
  elif [[ -f "$BK/playlist.absent" ]]; then
    rm -f -- "$PL"
  fi
}

abort_restore(){
  rc=$?
  if (( rc != 0 )); then
    echo "RECOVERY_SCRIPT_RESULT=FAIL rc=$rc"
  fi
  exit "$rc"
}
trap abort_restore EXIT

echo "CHG-R02 Radio Rock controlled recovery v1"
echo "UTC=$TS"
echo "OUT=$OUT"
echo "PRIVATE_BACKUP=$BK"

echo "=== A. REPOSITORY / HOST GATES ==="
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || { echo "FATAL=GIT_WORKTREE_NOT_CLEAN"; exit 1; }
bash -n "$GLOBAL_GEN"
echo "git_head=$(git rev-parse HEAD)"
echo "global_generator_sha=$(sha_of "$GLOBAL_GEN")"
echo "global_generator_syntax=PASS"

STATE="$(systemctl is-active "$UNIT" || true)"
echo "rock_pre_active=$STATE"
PRE_PID="$(systemctl show "$UNIT" -p MainPID --value)"
echo "rock_pre_pid=$PRE_PID"

# Capture PIDs before any service action.
printf 'unit\tpid\n' > "$OUT/pids.pre.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.pre.tsv"
done

echo "=== B. BUILD EXPECTED ROCK PLAYLIST — READ ONLY ==="
printf 'ffconcat version 1.0\n' > "$CAND"
count=0
probe_fail=0
while IFS= read -r -d '' f; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$CAND"
  count=$((count+1))
  if ! timeout 20 ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 "$f" >/dev/null 2>&1; then
    echo "ASSET_PROBE_FAIL=$(basename -- "$f")"
    probe_fail=$((probe_fail+1))
  else
    echo "ASSET_PASS=$(basename -- "$f")"
  fi
done < <(find "$READY" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) ! -iname '*teste*' ! -iname '*test*' -print0 | sort -z)

echo "eligible_count=$count"
echo "ffprobe_failures=$probe_fail"
[[ "$count" -eq "$EXPECTED" ]] || { echo "FATAL=ELIGIBLE_COUNT_EXPECTED_${EXPECTED}_GOT_${count}"; exit 1; }
[[ "$probe_fail" -eq 0 ]] || { echo "FATAL=ASSET_PROBE_FAILURE"; exit 1; }
CAND_SHA="$(sha_of "$CAND")"
echo "candidate_playlist_sha=$CAND_SHA"

echo "=== C. FULL CONCAT TRAVERSAL — READ ONLY ==="
set +e
timeout 600 nice -n 15 ffmpeg -hide_banner -nostdin -v error -f concat -safe 0 -i "$CAND" -map 0:a:0 -c:a copy -f null - >"$OUT/traversal.stdout" 2>"$OUT/traversal.stderr"
TRC=$?
set -e
cat "$OUT/traversal.stderr"
echo "full_concat_rc=$TRC"
[[ "$TRC" -eq 0 ]] || { echo "FATAL=FULL_CONCAT_TRAVERSAL_FAILED"; exit 1; }
echo "FULL_CONCAT_TRAVERSAL=PASS"

echo "=== D. BACKUP CURRENT ROCK PLAYLIST ==="
if [[ -f "$PL" ]]; then
  cp -a -- "$PL" "$BK/playlist.previous"
  echo "playlist_previous_sha=$(sha_of "$BK/playlist.previous")"
else
  : > "$BK/playlist.absent"
  echo "playlist_previous=ABSENT"
fi
cp -a -- "$GLOBAL_GEN" "$BK/tps-generate-playlist.snapshot"
echo "backup=PASS"

echo "=== E. GENERATE PRODUCTION ROCK PLAYLIST WITH CURRENT SHARED GENERATOR ==="
set +e
"$GLOBAL_GEN" "$CH"
GRC=$?
set -e
if (( GRC != 0 )); then
  restore_playlist
  echo "FATAL=GLOBAL_GENERATOR_FAILED rc=$GRC"
  exit 1
fi
[[ -f "$PL" ]] || { restore_playlist; echo "FATAL=PRODUCTION_PLAYLIST_MISSING"; exit 1; }
PROD_SHA="$(sha_of "$PL")"
PROD_COUNT="$(grep -c '^file ' "$PL" || true)"
echo "production_playlist_sha=$PROD_SHA"
echo "production_playlist_count=$PROD_COUNT"
if [[ "$PROD_SHA" != "$CAND_SHA" || "$PROD_COUNT" -ne "$EXPECTED" ]]; then
  restore_playlist
  echo "FATAL=GLOBAL_GENERATOR_OUTPUT_DIFFERS_FROM_VALIDATED_CANDIDATE"
  exit 1
fi
echo "production_playlist=VALIDATED_10_OF_10"

echo "=== F. START ONLY RADIO ROCK ==="
START_SINCE="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
systemctl reset-failed "$UNIT" || true
systemctl start "$UNIT"
for _ in $(seq 1 30); do
  [[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] && break
  sleep 1
done
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || { echo "FATAL=ROCK_NOT_ACTIVE_AFTER_START"; exit 1; }
POST_PID="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$POST_PID" =~ ^[1-9][0-9]*$ ]] || { echo "FATAL=ROCK_POST_PID_INVALID"; exit 1; }
echo "rock_post_pid=$POST_PID"

echo "=== G. MEDIAMTX / RTSP ==="
READY_STATE=""
for _ in $(seq 1 30); do
  READY_STATE="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[] | select(.name=="radiorock") | .ready' | head -n1 || true)"
  [[ "$READY_STATE" == "true" ]] && break
  sleep 1
done
[[ "$READY_STATE" == "true" ]] || { echo "FATAL=ROCK_MEDIAMTX_NOT_READY"; exit 1; }
curl -fsS http://127.0.0.1:9997/v3/paths/list | jq -c '.items[] | select(.name=="radiorock") | {name,ready,tracks,bytesReceived}' | tee "$OUT/mediamtx.json"
timeout 15 ffprobe -v error -rtsp_transport tcp -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 rtsp://127.0.0.1:8554/radiorock | tee "$OUT/rtsp.txt"
[[ -s "$OUT/rtsp.txt" ]] || { echo "FATAL=ROCK_RTSP_PROBE_EMPTY"; exit 1; }
echo "ROCK_RTSP=PASS"

echo "=== H. NEW PROCESS JOURNAL ==="
journalctl _PID="$POST_PID" --since "$START_SINCE" --no-pager -o short-iso > "$OUT/journal-new-pid.txt" || true
cat "$OUT/journal-new-pid.txt"
ERRS="$(grep -Eic 'Impossible to open|NO_READY_MEDIA|Conversion failed|Invalid data found|Error opening' "$OUT/journal-new-pid.txt" || true)"
echo "rock_new_pid_relevant_errors=$ERRS"
[[ "$ERRS" -eq 0 ]] || { echo "FATAL=ROCK_NEW_PID_HAS_RELEVANT_ERRORS"; exit 1; }

echo "=== I. NO OTHER PID CHANGED ==="
printf 'unit\tpid\n' > "$OUT/pids.post.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.post.tsv"
done
while IFS=$'\t' read -r u pre; do
  [[ "$u" == "unit" || "$u" == "$UNIT" ]] && continue
  post="$(awk -F '\t' -v u="$u" '$1==u{print $2}' "$OUT/pids.post.tsv")"
  [[ "$pre" == "$post" ]] || { echo "FATAL=UNEXPECTED_PID_CHANGE:$u:$pre:$post"; exit 1; }
done
echo "other_pids_unchanged=PASS"

echo "=== J. EVIDENCE ==="
TAR="/tmp/CHG-R02-${TS}.shareable.tar.gz"
tar -C /tmp -czf "$TAR" "CHG-R02-${TS}"
sha256sum "$TAR" | tee "${TAR}.sha256"
echo "CHG_R02_RESULT=PASS"
echo "ROCK_SERVICE=ACTIVE"
echo "ROCK_PLAYLIST=10_OF_10"
echo "ROCK_MEDIAMTX=READY"
echo "ROCK_RTSP=PASS"
echo "ROCK_NEW_PID_ERRORS=0"
echo "SHAREABLE=$TAR"
echo "PRIVATE_BACKUP=$BK"
trap - EXIT
