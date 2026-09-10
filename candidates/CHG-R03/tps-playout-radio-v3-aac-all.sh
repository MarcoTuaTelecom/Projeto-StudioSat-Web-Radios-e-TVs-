#!/usr/bin/env bash
# StudioSat Web — Radio playout v3
# Five production radio stations publish AAC-LC 48 kHz stereo to MediaMTX.
set -Eeuo pipefail

CH="${1:?channel}"
case "$CH" in
  radioprincipal|radiopop|radiorock|radioclassicas|radiocountry) ;;
  *) echo "FATAL=UNSUPPORTED_RADIO_CHANNEL:$CH" >&2; exit 64 ;;
esac

PL="/srv/tpsmedia/repository/channels/${CH}/playlists/playlist.txt"
[[ -r "$PL" ]] || { echo "FATAL=PLAYLIST_NOT_READABLE:$PL" >&2; exit 66; }

grep -q '^file ' "$PL" || { echo "FATAL=PLAYLIST_EMPTY:$PL" >&2; exit 67; }

exec /usr/bin/ffmpeg -hide_banner -loglevel warning -nostdin \
  -re -stream_loop -1 -f concat -safe 0 -i "$PL" \
  -map 0:a:0 \
  -af "aresample=48000:async=1:first_pts=0" \
  -c:a aac -profile:a aac_low -b:a 192k -ar 48000 -ac 2 \
  -flvflags no_duration_filesize \
  -f flv "rtmp://127.0.0.1:1935/${CH}"
