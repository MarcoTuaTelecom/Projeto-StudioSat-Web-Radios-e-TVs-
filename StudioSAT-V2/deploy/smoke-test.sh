#!/usr/bin/env bash
set -Eeuo pipefail
BASE="https://www.radio.studiosatweb.com.br"
RADIO="https://radio.studiosatweb.com.br"
curl -kfsS "$BASE/listen-v2/" | grep -q 'STUDIO SAT V2'
curl -kfsS "$BASE/listen-v2/api/stations" >/tmp/studiosat-v2-stations.json
for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  curl -kfsS "$RADIO/$r/index.m3u8" | grep -q '^#EXTM3U'
  echo "$r HLS=OK"
done
echo "PORTAL_V2=OK"
