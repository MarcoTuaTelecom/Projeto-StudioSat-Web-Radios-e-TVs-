#!/usr/bin/env bash
set -Eeuo pipefail

BASE="https://www.radio.studiosatweb.com.br"
RADIO="https://radio.studiosatweb.com.br"

curl -kfsS "$BASE/listen-v2/" | grep -q 'STUDIO SAT V2.2'
curl -kfsS "$BASE/listen-v2/api/stations" >/tmp/studiosat-v2-stations.json

python3 - <<'PY'
import json
d=json.load(open('/tmp/studiosat-v2-stations.json'))
assert len(d)==5, d
print('CATALOGO=5')
PY

for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  curl -kfsS "$RADIO/$r/index.m3u8" | grep -q '^#EXTM3U'
  echo "$r HLS_SOURCE=OK"

  python3 - "$BASE/listen-v2/live/$r.aac" "$r" <<'PY'
import sys,urllib.request
url,name=sys.argv[1],sys.argv[2]
req=urllib.request.Request(url,headers={'Cache-Control':'no-cache'})
with urllib.request.urlopen(req,timeout=10) as resp:
    ctype=resp.headers.get('Content-Type','')
    transport=resp.headers.get('X-Studiosat-Transport','')
    data=resp.read(7)
if not (len(data)>=2 and data[0]==0xff and data[1]&0xf0==0xf0):
    raise SystemExit(f'{name} RAW AAC sem sync ADTS: {data.hex()}')
print(f'{name} RAW_AAC=OK content-type={ctype} transport={transport}')
PY
done

echo "PORTAL_V2_2=OK"
