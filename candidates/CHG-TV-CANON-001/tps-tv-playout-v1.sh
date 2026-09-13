#!/usr/bin/env bash
# StudioSat TV canonical playout v1
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
CH="${1:?usage: tps-tv-playout-v1 <tvkids|tvteens|tvviva|tvmaisjovem>}"
case "$CH" in tvkids|tvteens|tvviva|tvmaisjovem) ;; *) echo "FATAL=UNSUPPORTED_TV:$CH" >&2; exit 64;; esac
PL="/srv/tpsmedia/repository/channels/$CH/playlists/playlist.txt"
[[ -s "$PL" ]] || { echo "FATAL=PLAYLIST_MISSING:$PL" >&2; exit 66; }

# Video remains bit-exact. Audio is decoded once and receives timestamps
# from output sample count, removing AAC timestamp overlap at concat boundaries.
exec /usr/bin/ffmpeg \
  -hide_banner -nostdin -loglevel warning \
  -re -stream_loop -1 \
  -f concat -safe 0 -i "$PL" \
  -map 0:v:0 -map 0:a:0 \
  -c:v copy \
  -af "aresample=48000:async=1,asetpts=N/SR/TB" \
  -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -f flv "rtmp://127.0.0.1:1935/$CH"
