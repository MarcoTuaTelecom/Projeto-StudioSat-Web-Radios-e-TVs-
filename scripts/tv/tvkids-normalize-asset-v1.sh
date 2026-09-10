#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
src="${1:?source required}"
dst="${2:?destination required}"
mkdir -p "$(dirname "$dst")"
tmp="${dst}.tmp.$$.mp4"
trap 'rm -f -- "$tmp"' EXIT
nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -loglevel warning -y \
  -i "$src" \
  -map 0:v:0 -map 0:a:0 \
  -vf "setpts=PTS-STARTPTS,fps=30,scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
  -af "aresample=48000:async=1:first_pts=0,apad" \
  -c:v libx264 -preset veryfast -crf 18 -profile:v high -level 3.1 \
  -g 60 -keyint_min 60 -sc_threshold 0 -threads 1 \
  -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -shortest -video_track_timescale 90000 -movflags +faststart \
  -map_metadata -1 -sn -dn "$tmp"
ffmpeg -hide_banner -nostdin -v error -xerror -i "$tmp" -map 0:v:0 -map 0:a:0 -f null -
mv -f -- "$tmp" "$dst"
trap - EXIT
echo "NORMALIZED=$(basename "$dst")"
