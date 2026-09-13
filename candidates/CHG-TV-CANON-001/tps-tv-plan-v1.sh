#!/usr/bin/env bash
# StudioSat TV canonical plan builder v1
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 022
CH="${1:?usage: tps-tv-plan-v1 <tvkids|tvteens|tvviva|tvmaisjovem>}"
case "$CH" in tvkids|tvteens|tvviva|tvmaisjovem) ;; *) echo "FATAL=UNSUPPORTED_TV:$CH" >&2; exit 64;; esac
BASE="/srv/tpsmedia/repository/channels/$CH"
CAN="$BASE/canonical"
PLDIR="$BASE/playlists"
PL="$PLDIR/playlist.txt"
[[ -d "$CAN" ]] || { echo "FATAL=CANONICAL_MISSING:$CAN" >&2; exit 66; }
mkdir -p "$PLDIR"
[[ -w "$PLDIR" ]] || { echo "FATAL=PLAYLIST_DIR_NOT_WRITABLE:$PLDIR" >&2; exit 73; }
TMP="$(mktemp "$PLDIR/.playlist.canonical.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf 'ffconcat version 1.0\n' > "$TMP"
count=0
while IFS= read -r -d '' f; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$TMP"
  count=$((count+1))
done < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
(( count > 0 )) || { echo "FATAL=NO_CANONICAL_MEDIA:$CH" >&2; exit 1; }
chmod 0644 "$TMP"
mv -f "$TMP" "$PL"
trap - EXIT
printf 'TV_PLAN_V1=PASS|STATION=%s|ITEMS=%d|SHA256=%s\n' "$CH" "$count" "$(sha256sum "$PL"|awk '{print $1}')"
