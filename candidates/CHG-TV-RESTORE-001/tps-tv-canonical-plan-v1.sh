#!/usr/bin/env bash
# Nome: tps-tv-canonical-plan-v1.sh
# Versão: 1.0
# Owner: TV
# Safety class: production-helper
# Change ID: CHG-TV-RESTORE-001
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 022
CH="${1:?usage: tps-tv-canonical-plan <tvkids|tvteens|tvviva|tvmaisjovem>}"
case "$CH" in tvkids|tvteens|tvviva|tvmaisjovem) ;; *) echo "FATAL=UNSUPPORTED_TV:$CH" >&2; exit 64;; esac
BASE="/srv/tpsmedia/repository/channels/$CH"
CAN="$BASE/canonical"
PLDIR="$BASE/playlists"
PL="$PLDIR/playlist.txt"
[[ -d "$CAN" ]] || { echo "FATAL=CANONICAL_MISSING:$CAN" >&2; exit 66; }
install -d -o tpsmedia -g tpsmedia -m 0755 "$PLDIR"
TMP="$(mktemp "$PLDIR/.playlist.canonical.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT
printf 'ffconcat version 1.0\n' > "$TMP"
count=0
while IFS= read -r -d '' f; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$TMP"
  count=$((count+1))
done < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
(( count > 0 )) || { echo "FATAL=NO_CANONICAL_MEDIA:$CH" >&2; exit 1; }
chown tpsmedia:tpsmedia "$TMP"
chmod 0644 "$TMP"
mv -f -- "$TMP" "$PL"
trap - EXIT
sha="$(sha256sum "$PL" | awk '{print $1}')"
printf 'TV_CANONICAL_PLAN_OK=%s|ITEMS=%d|SHA256=%s|FILE=%s\n' "$CH" "$count" "$sha" "$PL"
