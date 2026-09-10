#!/usr/bin/env bash
# StudioSat Web — Radio Principal playlist generator v2
# Change: CHG-R01
# Default: writes production playlist atomically.
# Validation mode: pass an alternate output path as argument 1.
set -Eeuo pipefail
IFS=$'\n\t'

CH="radioprincipal"
BASE="/srv/tpsmedia/repository/channels/${CH}"
READY="${BASE}/ready"
PLDIR="${BASE}/playlists"
DEFAULT_PL="${PLDIR}/playlist.txt"
OUTPUT="${1:-$DEFAULT_PL}"
OUTDIR="$(dirname -- "$OUTPUT")"

[[ -d "$READY" ]] || { echo "FATAL=READY_DIR_MISSING:$READY" >&2; exit 66; }
[[ -d "$OUTDIR" ]] || { echo "FATAL=OUTPUT_DIR_MISSING:$OUTDIR" >&2; exit 66; }

tmp="$(mktemp "${OUTDIR}/.$(basename -- "$OUTPUT").XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

printf 'ffconcat version 1.0\n' > "$tmp"
count=0

while IFS= read -r -d '' f; do
  # Preserve current Radio Principal eligibility semantics:
  # recursive ready/ scan; mp3/m4a/aac; test/teste excluded case-insensitively.
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$tmp"
  count=$((count + 1))
done < <(
  find "$READY" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) \
    ! -iname '*teste*' ! -iname '*test*' \
    -print0 | sort -z
)

(( count > 0 )) || { echo "FATAL=NO_READY_MEDIA:$CH" >&2; exit 1; }

chmod 0644 "$tmp"
mv -f -- "$tmp" "$OUTPUT"
trap - EXIT

printf 'PLAYLIST_OK=%s|ITEMS=%d|FILE=%s\n' "$CH" "$count" "$OUTPUT"
