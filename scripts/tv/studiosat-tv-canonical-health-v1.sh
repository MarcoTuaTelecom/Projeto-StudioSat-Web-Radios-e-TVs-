#!/usr/bin/env bash
# Nome: studiosat-tv-canonical-health-v1.sh
# Versão: 1.0
# Safety class: read-only
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

OUT="/tmp/studiosat-tv-canonical-health-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
TVS=(tvkids tvteens tvviva tvmaisjovem)
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
CANON="/etc/nginx/conf.d/studiosat-tv.conf"
fail=0

bad(){ echo "FAIL=$*"; fail=1; }
hls_fresh(){
  local st="$1" master="$OUT/$st.master" child uri seq1 seq2
  curl -LsSf --connect-timeout 3 --max-time 12 "http://127.0.0.1:8888/$st/index.m3u8" -o "$master" || return 1
  grep -q '^#EXTM3U' "$master" || return 1
  child="$(grep -v '^#' "$master" | sed '/^[[:space:]]*$/d' | head -1)"
  [[ -n "$child" ]] || return 1
  uri="http://127.0.0.1:8888/$st/$child"
  curl -LsSf --connect-timeout 3 --max-time 12 "$uri" -o "$OUT/$st.media1" || return 1
  seq1="$(grep '^#EXT-X-MEDIA-SEQUENCE:' "$OUT/$st.media1" | tail -1 | cut -d: -f2)"
  sleep 8
  curl -LsSf --connect-timeout 3 --max-time 12 "$uri" -o "$OUT/$st.media2" || return 1
  seq2="$(grep '^#EXT-X-MEDIA-SEQUENCE:' "$OUT/$st.media2" | tail -1 | cut -d: -f2)"
  [[ -n "$seq1" && -n "$seq2" && "$seq1" != "$seq2" ]]
}

nginx -t > "$OUT/nginx-t.txt" 2>&1 || bad NGINX_TEST
nginx -T > "$OUT/nginx-T.txt" 2>&1 || bad NGINX_T
if [[ -f "$CANON" ]]; then
  if ! python3 - "$OUT/nginx-T.txt" "$CANON" > "$OUT/owners.txt" <<'PY'
import re,sys
src,expected=sys.argv[1:3]
tv=['tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br','tvkidsweb.studiosatweb.com.br','www.tvkidsweb.studiosatweb.com.br','tvteens.studiosatweb.com.br','www.tvteens.studiosatweb.com.br','tvviva.studiosatweb.com.br','www.tvviva.studiosatweb.com.br','tvmaisjovem.studiosatweb.com.br','www.tvmaisjovem.studiosatweb.com.br']
cur=None;owners={h:set() for h in tv}
for line in open(src,encoding='utf-8',errors='replace'):
    m=re.match(r'^# configuration file (.+):$',line.rstrip('\n'))
    if m: cur=m.group(1); continue
    if cur and 'server_name' in line:
        for h in tv:
            if h in line: owners[h].add(cur)
bad={h:sorted(v) for h,v in owners.items() if v!={expected}}
for h,v in owners.items(): print(h+'\t'+','.join(sorted(v)))
if bad: raise SystemExit(1)
PY
  then
    bad TV_OWNER_UNIQUE
  fi
else bad CANONICAL_NGINX_MISSING
fi

paths="$(curl -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:9997/v3/paths/list 2>/dev/null || echo '{"items":[]}')"

for st in "${RADIOS[@]}"; do
  [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active ]] || bad "RADIO_UNIT:$st"
  ready="$(jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' <<<"$paths" | head -1)"
  [[ "$ready" == true ]] || bad "RADIO_MEDIAMTX:$st"
  probe="$(timeout 12 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"
  grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || bad "RADIO_AUDIO:$st"
done

declare -A HOST=(
 [tvkids]=tvkidsweb.studiosatweb.com.br
 [tvteens]=tvteens.studiosatweb.com.br
 [tvviva]=tvviva.studiosatweb.com.br
 [tvmaisjovem]=tvmaisjovem.studiosatweb.com.br
)
for st in "${TVS[@]}"; do
  [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active ]] || bad "TV_UNIT:$st"
  ready="$(jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' <<<"$paths" | head -1)"
  [[ "$ready" == true ]] || bad "TV_MEDIAMTX:$st"
  probe="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"
  grep -q 'codec_name=h264' <<<"$probe" && grep -q 'width=1280' <<<"$probe" && grep -q 'height=720' <<<"$probe" || bad "TV_VIDEO:$st"
  grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || bad "TV_AUDIO:$st"
  hls_fresh "$st" || bad "TV_HLS_FRESH:$st"

  h="${HOST[$st]}"; hdr="$OUT/$st.public.headers"; body="$OUT/$st.public.html"; m3u="$OUT/$st.public.m3u8"
  code="$(curl -kLsS --connect-timeout 4 --max-time 15 -D "$hdr" -o "$body" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 200 ]] || bad "TV_PUBLIC_ROOT:$st:$code"
  grep -qi '^X-StudioSat-TV-Owner: canonical-v1' "$hdr" || bad "TV_PUBLIC_OWNER:$st"
  grep -q 'Studio Sat TV — Ao Vivo' "$body" || bad "TV_PUBLIC_PLAYER:$st"
  hc="$(curl -kLsS --connect-timeout 4 --max-time 15 -o "$m3u" -w '%{http_code}' "https://$h/$st/index.m3u8" || true)"
  [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$m3u" || bad "TV_PUBLIC_HLS:$st:$hc"

  journalctl -u "tps-${st}-playout.service" --since '-10 minutes' --no-pager > "$OUT/$st.journal" || true
  dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$OUT/$st.journal" || true)"
  [[ "$dts" -eq 0 ]] || bad "TV_DTS:$st:$dts"
done

if (( fail == 0 )); then
  echo STUDIOSAT_TV_CANONICAL_HEALTH=PASS
  echo ALL_5_RADIOS_HEALTHY=PASS
  echo ALL_4_TVS_HEALTHY=PASS
  echo SINGLE_TV_NGINX_OWNER=PASS
  echo ZERO_DTS_LAST_10M=PASS
  echo "evidence=$OUT"
  exit 0
fi
echo STUDIOSAT_TV_CANONICAL_HEALTH=FAIL
echo "evidence=$OUT"
exit 1
