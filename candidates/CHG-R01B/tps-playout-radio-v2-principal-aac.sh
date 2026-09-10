#!/usr/bin/env bash
# StudioSat Web — Radio playout v2
# CHG-R01B: only radioprincipal changes delivery profile to AAC-LC 48 kHz stereo.
# All other radio channels preserve the legacy stream-copy behavior byte-for-byte in semantics.
set -Eeuo pipefail

CH="${1:?channel}"
PL="/srv/tpsmedia/repository/channels/${CH}/playlists/playlist.txt"
[[ -r "$PL" ]] || { echo "FATAL=PLAYLIST_NOT_READABLE:$PL" >&2; exit 66; }

if [[ "$CH" == "radioprincipal" ]]; then
  exec /usr/bin/ffmpeg -hide_banner -loglevel warning -nostdin \
    -re -stream_loop -1 -f concat -safe 0 -i "$PL" \
    -map 0:a:0 \
    -af "aresample=48000:async=1:first_pts=0" \
    -c:a aac -profile:a aac_low -b:a 192k -ar 48000 -ac 2 \
    -flvflags no_duration_filesize \
    -f flv "rtmp://127.0.0.1:1935/${CH}"
fi

exec /usr/bin/ffmpeg -hide_banner -loglevel warning -nostdin \
  -re -stream_loop -1 -f concat -safe 0 -i "$PL" \
  -map 0:a:0 -c:a copy \
  -f flv "rtmp://127.0.0.1:1935/${CH}"
