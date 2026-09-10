#!/usr/bin/env bash
# StudioSat Web — CHG-R01 transactional apply for Radio Principal
# Scope: Principal-specific generator + Principal playlist + one Principal restart.
# Explicitly DOES NOT run systemctl daemon-reload, MediaMTX/NGINX restart, or touch other stations.
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-radioprincipal-playout.service"
CH="radioprincipal"
BASE="/srv/tpsmedia/repository/channels/${CH}"
READY="${BASE}/ready"
PL="${BASE}/playlists/playlist.txt"
GEN="/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed"
UNIT_FILE="/etc/systemd/system/tps-radioprincipal-playout.service"
DROP_SAFE="/etc/systemd/system/tps-radioprincipal-playout.service.d/10-tps-production-safety.conf"
DROP_FIXED="/etc/systemd/system/tps-radioprincipal-playout.service.d/20-fixed-playlist.conf"

EXPECTED_GEN_SHA="d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18"
EXPECTED_PL_SHA="9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe"
EXPECTED_UNIT_SHA="d57cd94cba7c8fc4975cba927c922ffaae2d32e460ccf3aa88558cb1acccec58"
EXPECTED_SAFE_SHA="102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48"
EXPECTED_FIXED_SHA="2e15e711c624aed3e393abe294446574dc50fbab2eae5559304f90ebf70e83e3"
EXPECTED_COUNT=18

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
GEN_CAND="${SCRIPT_DIR}/tps-generate-playlist-radioprincipal-fixed-v2.sh"
VALIDATOR="${SCRIPT_DIR}/validate-radioprincipal-playlist-v1.sh"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-R01-apply-${TS}"
BACKUP="/var/backups/studiosat/CHG-R01/${TS}"
CAND_PL="/tmp/CHG-R01-radioprincipal-playlist.candidate.${TS}"
REPORT="${OUT}/REPORT.txt"
MUTATED=0
RESTART_ATTEMPTED=0

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in systemctl sha256sum ffprobe ffmpeg find sort grep sed awk jq curl timeout runuser install stat cp mv tar date git; do need "$c"; done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "FATAL=RUN_AS_ROOT" >&2
  exit 77
fi

install -d -m 0755 "$OUT"
install -d -m 0700 "$BACKUP"
exec > >(tee "$REPORT") 2>&1

echo "CHG-R01 Radio Principal transactional apply"
echo "UTC=$TS"
echo "REPO=$REPO"
echo "OUT=$OUT"
echo "PRIVATE_BACKUP=$BACKUP"
echo

fail() { echo "FATAL=$*" >&2; exit 1; }
sha_of() { sha256sum "$1" | awk '{print $1}'; }

rollback_files_only() {
  echo "ROLLBACK_FILES=START"
  [[ -f "$BACKUP/generator.previous" ]] || fail "ROLLBACK_GENERATOR_BACKUP_MISSING"
  [[ -f "$BACKUP/playlist.previous" ]] || fail "ROLLBACK_PLAYLIST_BACKUP_MISSING"
  local gt pt
  gt="$(mktemp "$(dirname "$GEN")/.chg-r01-generator.rollback.XXXXXX")"
  pt="$(mktemp "$(dirname "$PL")/.chg-r01-playlist.rollback.XXXXXX")"
  cp -a -- "$BACKUP/generator.previous" "$gt"
  cp -a -- "$BACKUP/playlist.previous" "$pt"
  mv -f -- "$gt" "$GEN"
  mv -f -- "$pt" "$PL"
  echo "ROLLBACK_FILES=PASS"
}

rollback_after_restart_failure() {
  echo "ROLLBACK_AFTER_RESTART_FAILURE=START"
  rollback_files_only
  systemctl restart "$UNIT" || true
  sleep 2
  systemctl show "$UNIT" -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp --no-pager || true
  echo "ROLLBACK_AFTER_RESTART_FAILURE=DONE"
}

trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then if (( RESTART_ATTEMPTED == 1 )); then rollback_after_restart_failure; else rollback_files_only; fi; fi; exit $rc' EXIT

echo "=== A. REPOSITORY GATE ==="
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || fail "GIT_WORKTREE_NOT_CLEAN"
echo "git_head=$(git rev-parse HEAD)"
git log -1 --oneline
[[ -f "$GEN_CAND" ]] || fail "GENERATOR_CANDIDATE_MISSING"
[[ -f "$VALIDATOR" ]] || fail "VALIDATOR_MISSING"
bash -n "$GEN_CAND"
bash -n "$VALIDATOR"
echo "candidate_generator_sha=$(sha_of "$GEN_CAND")"
echo "validator_sha=$(sha_of "$VALIDATOR")"
echo

echo "=== B. LOCKED ARTIFACT GATE ==="
[[ "$(sha_of "$GEN")" == "$EXPECTED_GEN_SHA" ]] || fail "GENERATOR_DRIFT"
[[ "$(sha_of "$PL")" == "$EXPECTED_PL_SHA" ]] || fail "PLAYLIST_DRIFT"
[[ "$(sha_of "$UNIT_FILE")" == "$EXPECTED_UNIT_SHA" ]] || fail "UNIT_DRIFT"
[[ "$(sha_of "$DROP_SAFE")" == "$EXPECTED_SAFE_SHA" ]] || fail "SAFE_DROPIN_DRIFT"
[[ "$(sha_of "$DROP_FIXED")" == "$EXPECTED_FIXED_SHA" ]] || fail "FIXED_DROPIN_DRIFT"
echo "locked_artifacts=PASS"
echo "NeedDaemonReload=$(systemctl show "$UNIT" -p NeedDaemonReload --value)"
LOADED_PRE="$(systemctl show "$UNIT" -p ExecStartPre --value)"
LOADED_START="$(systemctl show "$UNIT" -p ExecStart --value)"
[[ "$LOADED_PRE" == *"$GEN"* ]] || fail "LOADED_EXECSTARTPRE_UNEXPECTED"
[[ "$LOADED_START" == *"tps-playout-radio radioprincipal"* ]] || fail "LOADED_EXECSTART_UNEXPECTED"
echo "loaded_exec_contract=PASS"
echo

echo "=== C. SERVICE / MEDIA PRECHECK ==="
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || fail "PRINCIPAL_NOT_ACTIVE_PRE"
PRE_PID="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$PRE_PID" =~ ^[0-9]+$ && "$PRE_PID" -gt 0 ]] || fail "PRINCIPAL_PID_INVALID_PRE"
echo "principal_pre_pid=$PRE_PID"
systemctl show "$UNIT" -p ExecMainStartTimestamp --no-pager
ELIGIBLE="$(find "$READY" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) ! -iname '*teste*' ! -iname '*test*' -print0 | awk -v RS='\0' 'NF{n++} END{print n+0}')"
echo "eligible_count=$ELIGIBLE"
[[ "$ELIGIBLE" -eq "$EXPECTED_COUNT" ]] || fail "ELIGIBLE_COUNT_EXPECTED_${EXPECTED_COUNT}_GOT_${ELIGIBLE}"

printf 'unit\tpid\n' > "$OUT/pids.pre.tsv"
for u in \
  tps-radioprincipal-playout.service \
  tps-radiopop-playout.service \
  tps-radiorock-playout.service \
  tps-radioclassicas-playout.service \
  tps-radiocountry-playout.service \
  tps-tvkids-playout.service \
  tps-tvteens-playout.service \
  tps-tvviva-playout.service \
  tps-tvmaisjovem-playout.service \
  tps-mediamtx.service \
  nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.pre.tsv"
done

printf 'station\tsha256\n' > "$OUT/playlists.pre.tsv"
for s in radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem; do
  p="/srv/tpsmedia/repository/channels/$s/playlists/playlist.txt"
  printf '%s\t%s\n' "$s" "$([[ -f "$p" ]] && sha_of "$p" || echo MISSING)" >> "$OUT/playlists.pre.tsv"
done

echo

echo "=== D. CANDIDATE GENERATION — NO PRODUCTION MUTATION ==="
rm -f -- "$CAND_PL"
runuser -u tpsmedia -- bash "$GEN_CAND" "$CAND_PL"
CAND_PL_SHA="$(sha_of "$CAND_PL")"
echo "candidate_playlist_sha=$CAND_PL_SHA"
echo "-- Ain't line in candidate --"
grep -n -i "ain" "$CAND_PL" || true

echo

echo "=== E. 18/18 VALIDATION + FULL TRAVERSAL ==="
bash "$VALIDATOR" "$CAND_PL" "$EXPECTED_COUNT" | tee "$OUT/validator.candidate.txt"
grep -qx 'RESULT=PASS' "$OUT/validator.candidate.txt" || fail "CANDIDATE_VALIDATOR_NOT_PASS"
echo

echo "=== F. PRIVATE BACKUP BEFORE MUTATION ==="
cp -a -- "$GEN" "$BACKUP/generator.previous"
cp -a -- "$PL" "$BACKUP/playlist.previous"
cp -a -- "$UNIT_FILE" "$BACKUP/"
cp -a -- "$DROP_SAFE" "$BACKUP/"
cp -a -- "$DROP_FIXED" "$BACKUP/"
systemctl show "$UNIT" > "$BACKUP/unit.show.pre.txt"
systemctl cat "$UNIT" > "$BACKUP/unit.cat.pre.txt" || true
sha256sum "$BACKUP"/* > "$BACKUP/SHA256SUMS.txt"
echo "backup=PASS"
echo

echo "=== G. ATOMIC GENERATOR PROMOTION ==="
GEN_UID="$(stat -c '%u' "$GEN")"
GEN_GID="$(stat -c '%g' "$GEN")"
GEN_MODE="$(stat -c '%a' "$GEN")"
TMP_GEN="$(mktemp "$(dirname "$GEN")/.tps-generate-playlist-radioprincipal-fixed.CHG-R01.XXXXXX")"
install -o "$GEN_UID" -g "$GEN_GID" -m "$GEN_MODE" "$GEN_CAND" "$TMP_GEN"
CAND_GEN_SHA="$(sha_of "$GEN_CAND")"
[[ "$(sha_of "$TMP_GEN")" == "$CAND_GEN_SHA" ]] || fail "TEMP_GENERATOR_HASH_MISMATCH"
mv -f -- "$TMP_GEN" "$GEN"
MUTATED=1
[[ "$(sha_of "$GEN")" == "$CAND_GEN_SHA" ]] || fail "PROMOTED_GENERATOR_HASH_MISMATCH"
echo "generator_promotion=PASS"
echo "generator_new_sha=$CAND_GEN_SHA"
echo

echo "=== H. GENERATE PRODUCTION PLAYLIST ATOMICALLY ==="
runuser -u tpsmedia -- "$GEN"
PROD_PL_SHA="$(sha_of "$PL")"
echo "production_playlist_sha=$PROD_PL_SHA"
[[ "$PROD_PL_SHA" == "$CAND_PL_SHA" ]] || fail "PRODUCTION_PLAYLIST_DIFFERS_FROM_VALIDATED_CANDIDATE"
echo "-- Ain't line in production playlist --"
grep -n -i "ain" "$PL" || true

echo

echo "=== I. REVALIDATE PRODUCTION PLAYLIST ==="
bash "$VALIDATOR" "$PL" "$EXPECTED_COUNT" | tee "$OUT/validator.production.txt"
grep -qx 'RESULT=PASS' "$OUT/validator.production.txt" || fail "PRODUCTION_VALIDATOR_NOT_PASS"

echo

echo "=== J. CURRENT PROCESS STILL ALIVE BEFORE FINAL RESTART ==="
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || fail "PRINCIPAL_DIED_BEFORE_FINAL_RESTART"
CURRENT_PID="$(systemctl show "$UNIT" -p MainPID --value)"
echo "principal_pid_before_final_restart=$CURRENT_PID"
MTX_READY="$(curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:9997/v3/paths/list | jq -r '.items[] | select(.name=="radioprincipal") | .ready' | head -n1)"
echo "mediamtx_ready_before_final_restart=${MTX_READY:-missing}"
[[ "$MTX_READY" == "true" ]] || fail "MEDIAMTX_NOT_READY_BEFORE_FINAL_RESTART"

echo

echo "=== K. ONE CONTROLLED FINAL RESTART — PRINCIPAL ONLY ==="
RESTART_SINCE="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RESTART_ATTEMPTED=1
systemctl restart "$UNIT"

for _ in $(seq 1 20); do
  [[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] && break
  sleep 1
done
[[ "$(systemctl is-active "$UNIT" || true)" == "active" ]] || fail "PRINCIPAL_NOT_ACTIVE_POST_RESTART"
POST_PID="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$POST_PID" =~ ^[0-9]+$ && "$POST_PID" -gt 0 ]] || fail "PRINCIPAL_PID_INVALID_POST"
[[ "$POST_PID" != "$CURRENT_PID" ]] || fail "PRINCIPAL_PID_DID_NOT_CHANGE"
echo "principal_post_pid=$POST_PID"
systemctl show "$UNIT" -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp -p NeedDaemonReload --no-pager

MTX_READY=""
for _ in $(seq 1 20); do
  MTX_READY="$(curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[] | select(.name=="radioprincipal") | .ready' | head -n1 || true)"
  [[ "$MTX_READY" == "true" ]] && break
  sleep 1
done
echo "mediamtx_ready_post=$MTX_READY"
[[ "$MTX_READY" == "true" ]] || fail "MEDIAMTX_NOT_READY_POST"

echo "-- RTSP post --"
timeout 15 ffprobe -v error -rtsp_transport tcp \
  -select_streams a:0 \
  -show_entries stream=codec_name,sample_rate,channels \
  -of default=noprint_wrappers=1 \
  rtsp://127.0.0.1:8554/radioprincipal | tee "$OUT/rtsp.post.txt"
[[ -s "$OUT/rtsp.post.txt" ]] || fail "RTSP_AUDIO_PROBE_EMPTY"

echo "-- journal post restart --"
journalctl -u "$UNIT" --since "$RESTART_SINCE" --no-pager -o short-iso | tee "$OUT/journal.post.txt"
IMPOSSIBLE="$(grep -ci 'Impossible to open' "$OUT/journal.post.txt" || true)"
NO_READY="$(grep -ci 'NO_READY_MEDIA' "$OUT/journal.post.txt" || true)"
echo "impossible_to_open_post=$IMPOSSIBLE"
echo "no_ready_media_post=$NO_READY"
[[ "$IMPOSSIBLE" -eq 0 ]] || fail "IMPOSSIBLE_TO_OPEN_POST_RESTART"
[[ "$NO_READY" -eq 0 ]] || fail "NO_READY_MEDIA_POST_RESTART"

echo

echo "=== L. PROVE NO OTHER PROCESS RESTARTED ==="
printf 'unit\tpid\n' > "$OUT/pids.post.tsv"
for u in \
  tps-radioprincipal-playout.service \
  tps-radiopop-playout.service \
  tps-radiorock-playout.service \
  tps-radioclassicas-playout.service \
  tps-radiocountry-playout.service \
  tps-tvkids-playout.service \
  tps-tvteens-playout.service \
  tps-tvviva-playout.service \
  tps-tvmaisjovem-playout.service \
  tps-mediamtx.service \
  nginx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value)" >> "$OUT/pids.post.tsv"
done

awk -F '\t' 'NR==FNR{pre[$1]=$2;next} $1!="tps-radioprincipal-playout.service" && pre[$1]!=$2 {print "UNEXPECTED_PID_CHANGE=" $1 " pre=" pre[$1] " post=" $2; bad=1} END{exit bad}' \
  "$OUT/pids.pre.tsv" "$OUT/pids.post.tsv" || fail "OTHER_PROCESS_PID_CHANGED"
echo "other_process_pids_unchanged=PASS"

printf 'station\tsha256\n' > "$OUT/playlists.post.tsv"
for s in radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem; do
  p="/srv/tpsmedia/repository/channels/$s/playlists/playlist.txt"
  printf '%s\t%s\n' "$s" "$([[ -f "$p" ]] && sha_of "$p" || echo MISSING)" >> "$OUT/playlists.post.tsv"
done
awk -F '\t' 'NR==FNR{pre[$1]=$2;next} $1!="radioprincipal" && pre[$1]!=$2 {print "UNEXPECTED_PLAYLIST_CHANGE=" $1; bad=1} END{exit bad}' \
  "$OUT/playlists.pre.tsv" "$OUT/playlists.post.tsv" || fail "OTHER_PLAYLIST_CHANGED"
echo "other_playlists_unchanged=PASS"

echo

echo "=== M. FINAL ARTIFACT IDENTITIES ==="
echo "generator_sha=$(sha_of "$GEN")"
echo "playlist_sha=$(sha_of "$PL")"
echo "unit_sha=$(sha_of "$UNIT_FILE")"
echo "safe_dropin_sha=$(sha_of "$DROP_SAFE")"
echo "fixed_dropin_sha=$(sha_of "$DROP_FIXED")"
echo "NeedDaemonReload=$(systemctl show "$UNIT" -p NeedDaemonReload --value)"

echo

echo "=== N. SHAREABLE EVIDENCE ==="
cp "$CAND_PL" "$OUT/playlist.candidate.ffconcat"
cp "$PL" "$OUT/playlist.production.ffconcat"
cp "$OUT/pids.pre.tsv" "$OUT/pids.pre.copy.tsv" 2>/dev/null || true
# Do not include private backups or global configs in the shareable package.
tar -C /tmp -czf "/tmp/CHG-R01-apply-${TS}.shareable.tar.gz" "CHG-R01-apply-${TS}"
sha256sum "/tmp/CHG-R01-apply-${TS}.shareable.tar.gz" | tee "/tmp/CHG-R01-apply-${TS}.shareable.tar.gz.sha256"

echo
echo "CHG_R01_IMMEDIATE_RESULT=PASS"
echo "ROTATION_18_OF_18=PENDING_OBSERVER"
echo "SHAREABLE=/tmp/CHG-R01-apply-${TS}.shareable.tar.gz"
echo "SHAREABLE_SHA256=/tmp/CHG-R01-apply-${TS}.shareable.tar.gz.sha256"
echo "PRIVATE_BACKUP=$BACKUP"

MUTATED=0
RESTART_ATTEMPTED=0
trap - EXIT
exit 0
