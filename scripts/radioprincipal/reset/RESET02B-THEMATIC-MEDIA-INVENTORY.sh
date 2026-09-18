#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

RADIOS=(radiopop radiorock radioclassicas radiocountry)
OUT="/root/RESET02B-MEDIA-INVENTORY-$(date -u +%Y%m%dT%H%M%SZ).txt"
exec > >(tee "$OUT") 2>&1

echo "=============================================================="
echo " RESET02B - THEMATIC RADIO MEDIA INVENTORY / READ ONLY"
echo "=============================================================="
echo "REPORT=$OUT"
echo "NO_CHANGES=YES"

for ch in "${RADIOS[@]}"; do
  base="/srv/tpsmedia/repository/channels/$ch"
  pl="$base/playlists/playlist.txt"

  echo
  echo "================================================================"
  echo " RADIO=$ch"
  echo "================================================================"
  echo "SERVICE=$(systemctl is-active "tps-$ch-playout.service" 2>/dev/null || true)"
  echo "BASE=$base"

  if [ -f "$pl" ]; then
    echo "PLAYLIST_ITEMS=$(grep -c '^file ' "$pl" || true)"
    echo "PLAYLIST_MTIME=$(stat -c '%y' "$pl")"
    echo "PLAYLIST_SHA=$(sha256sum "$pl" | awk '{print $1}')"
  else
    echo "PLAYLIST=MISSING"
  fi

  echo "--- TOP LEVEL ---"
  find "$base" -maxdepth 1 -mindepth 1 -printf '%y\t%p\n' 2>/dev/null | sort || true

  echo "--- AUDIO COUNTS BY TOP-LEVEL DIRECTORY ---"
  if [ -d "$base" ]; then
    while IFS= read -r d; do
      c="$(find "$d" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \) 2>/dev/null | wc -l)"
      printf '%8s  %s\n' "$c" "$d"
    done < <(find "$base" -maxdepth 1 -mindepth 1 -type d | sort)
  fi

  echo "--- TOTAL AUDIO UNDER CHANNEL ---"
  find "$base" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \) \
    ! -path '*/playlists/*' -print 2>/dev/null | sort -u | wc -l

  echo "--- READY COUNT ---"
  if [ -d "$base/ready" ]; then
    find "$base/ready" -type f \
      \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \) \
      -print 2>/dev/null | wc -l
  else
    echo "READY_DIR=MISSING"
  fi

  echo "--- MOST RECENT 40 AUDIO FILES ---"
  find "$base" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \) \
    ! -path '*/playlists/*' \
    -printf '%T@|%TY-%Tm-%Td %TH:%TM:%TS|%s|%p\n' 2>/dev/null |
    sort -t'|' -k1,1nr | head -40 | cut -d'|' -f2- || true

  echo "--- FILES MODIFIED ON 16/17 SEP ---"
  find "$base" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \) \
    -newermt '2026-09-16 00:00:00 UTC' ! -newermt '2026-09-18 00:00:00 UTC' \
    -printf '%TY-%Tm-%Td %TH:%TM:%TS|%s|%p\n' 2>/dev/null |
    sort | tail -80 || true
done

echo
echo "RESULTADO=RESET02B_MEDIA_INVENTORY_COMPLETE"
echo "REPORT=$OUT"
