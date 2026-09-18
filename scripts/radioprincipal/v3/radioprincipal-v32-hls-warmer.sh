#!/usr/bin/env bash
set -Eeuo pipefail
install -d -m 0755 /run/studiosat
OUT=/run/studiosat/radioprincipal-v32.m3u8
TMP="${OUT}.tmp"

while true; do
  if curl -LfsS --max-time 10 \
    http://127.0.0.1:8888/radioprincipal/index.m3u8 \
    -o "$TMP" 2>/dev/null &&
    grep -q '^#EXTM3U' "$TMP"; then
    mv -f "$TMP" "$OUT"
  else
    rm -f "$TMP"
  fi
  sleep 2
done
