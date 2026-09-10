#!/usr/bin/env bash
# StudioSat Web — Radio Principal candidate validator
# Change: CHG-R01
set -Eeuo pipefail
IFS=$'\n\t'

PL="${1:?usage: validate-radioprincipal-playlist-v1.sh <playlist.candidate> [expected_count]}"
EXPECTED="${2:-18}"
READY="/srv/tpsmedia/repository/channels/radioprincipal/ready"

[[ -f "$PL" ]] || { echo "FATAL=PLAYLIST_MISSING:$PL" >&2; exit 66; }
[[ -d "$READY" ]] || { echo "FATAL=READY_DIR_MISSING:$READY" >&2; exit 66; }

eligible_count=0
playlist_count="$(grep -c '^file ' "$PL" || true)"
missing_line=0
probe_fail=0

printf 'asset\tffconcat_line\tffprobe\n'
while IFS= read -r -d '' f; do
  eligible_count=$((eligible_count + 1))
  esc=${f//\'/\'\\\'\'}
  expected_line="file '$esc'"
  line_state=PASS
  probe_state=PASS
  grep -Fqx -- "$expected_line" "$PL" || { line_state=FAIL; missing_line=$((missing_line + 1)); }
  if ! timeout 20 ffprobe -v error -select_streams a:0 \
      -show_entries stream=codec_name,sample_rate,channels \
      -of default=noprint_wrappers=1 "$f" >/dev/null 2>&1; then
    probe_state=FAIL
    probe_fail=$((probe_fail + 1))
  fi
  printf '%s\t%s\t%s\n' "$(basename -- "$f")" "$line_state" "$probe_state"
done < <(
  find "$READY" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) \
    ! -iname '*teste*' ! -iname '*test*' \
    -print0 | sort -z
)

printf '\nELIGIBLE_COUNT=%d\nPLAYLIST_COUNT=%d\nEXPECTED_COUNT=%d\nMISSING_OR_TRUNCATED_LINES=%d\nFFPROBE_FAILURES=%d\n' \
  "$eligible_count" "$playlist_count" "$EXPECTED" "$missing_line" "$probe_fail"

[[ "$eligible_count" -eq "$EXPECTED" ]] || { echo 'RESULT=FAIL:ELIGIBLE_COUNT'; exit 1; }
[[ "$playlist_count" -eq "$EXPECTED" ]] || { echo 'RESULT=FAIL:PLAYLIST_COUNT'; exit 1; }
[[ "$missing_line" -eq 0 ]] || { echo 'RESULT=FAIL:FFCONCAT_LINES'; exit 1; }
[[ "$probe_fail" -eq 0 ]] || { echo 'RESULT=FAIL:FFPROBE'; exit 1; }

echo 'FULL_CONCAT_TRAVERSAL=START'
if timeout 300 nice -n 15 ffmpeg -hide_banner -v error -nostdin \
    -f concat -safe 0 -i "$PL" -map 0:a:0 -c:a copy -f null -; then
  echo 'FULL_CONCAT_TRAVERSAL=PASS'
else
  echo 'FULL_CONCAT_TRAVERSAL=FAIL'
  exit 1
fi

echo 'RESULT=PASS'
