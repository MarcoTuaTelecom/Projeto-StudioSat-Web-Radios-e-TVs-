#!/usr/bin/env bash
# Nome: ns1-health-certify-v3.sh
# Versão: 3.0
# Owner: Core
# Safety class: read-only
# Change ID: OBS-NS1-HEALTH-V3
# Propósito: health sem falsos positivos de redirects, SPA fallback e vhost errado.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo FATAL=RUN_AS_ROOT; exit 77; }
OUT="/tmp/ns1-health-v3-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$OUT"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
fail=0

hls_local(){
  local st="$1" prefix="$2" master1="$OUT/${prefix}.master1" child1="$OUT/${prefix}.child1" master2="$OUT/${prefix}.master2" child2="$OUT/${prefix}.child2" url="http://127.0.0.1:8888/$st/index.m3u8"
  local code child url2 seq1 seq2
  code="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$master1" -w '%{http_code}' "$url" || true)"
  [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$master1" || return 1
  child="$(grep -v '^#' "$master1" | sed '/^[[:space:]]*$/d' | head -n1)"; [[ -n "$child" ]] || return 1
  url2="http://127.0.0.1:8888/$st/$child"; curl -LsS --connect-timeout 3 --max-time 12 "$url2" -o "$child1" || return 1
  seq1="$(grep '^#EXT-X-MEDIA-SEQUENCE:' "$child1" | tail -1 | cut -d: -f2 || true)"
  sleep 4
  code="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$master2" -w '%{http_code}' "$url" || true)"
  [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$master2" || return 1
  child="$(grep -v '^#' "$master2" | sed '/^[[:space:]]*$/d' | head -n1)"; [[ -n "$child" ]] || return 1
  url2="http://127.0.0.1:8888/$st/$child"; curl -LsS --connect-timeout 3 --max-time 12 "$url2" -o "$child2" || return 1
  seq2="$(grep '^#EXT-X-MEDIA-SEQUENCE:' "$child2" | tail -1 | cut -d: -f2 || true)"
  [[ -n "$seq1" && -n "$seq2" && "$seq2" != "$seq1" ]]
}

probe_station(){
  local st="$1" cls="$2" unit="tps-${st}-playout.service" p a pid ready ok
  a="$(systemctl is-active "$unit" 2>/dev/null || true)"; pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  ready="$(curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' | head -1 || true)"
  p="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"
  ok=1
  [[ "$a" == active && "$pid" =~ ^[1-9][0-9]*$ && "$ready" == true ]] || ok=0
  if [[ "$cls" == radio ]]; then
    grep -q 'codec_type=audio' <<<"$p" && grep -q 'codec_name=aac' <<<"$p" && grep -q 'sample_rate=48000' <<<"$p" && grep -q 'channels=2' <<<"$p" || ok=0
  else
    grep -q 'codec_type=video' <<<"$p" && grep -q 'codec_name=h264' <<<"$p" && grep -q 'width=1280' <<<"$p" && grep -q 'height=720' <<<"$p" || ok=0
    grep -q 'codec_type=audio' <<<"$p" && grep -q 'codec_name=aac' <<<"$p" && grep -q 'sample_rate=48000' <<<"$p" && grep -q 'channels=2' <<<"$p" || ok=0
  fi
  hls_local "$st" "$st" || ok=0
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$a" "$pid" "$ready" "$ok"
  (( ok == 1 )) || fail=1
}

printf 'station\tactive\tpid\tmediamtx_ready\thealth\n' | tee "$OUT/stations.tsv"
for st in "${RADIOS[@]}"; do probe_station "$st" radio | tee -a "$OUT/stations.tsv"; done
for st in "${TVS[@]}"; do probe_station "$st" tv | tee -a "$OUT/stations.tsv"; done

printf 'host\troot\thls\tcontent\n' | tee "$OUT/public.tsv"
for st in "${RADIOS[@]}"; do
  for host in "$st.studiosatweb.com.br" "www.$st.studiosatweb.com.br"; do
    r="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$OUT/${host}.root" -w '%{http_code}' "https://$host/" || true)"
    h="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$OUT/${host}.hls" -w '%{http_code}' "https://$host/$st/index.m3u8" || true)"
    c=M3U8; [[ "$h" == 200 ]] && grep -q '^#EXTM3U' "$OUT/${host}.hls" || c=NOT_M3U8
    printf '%s\t%s\t%s\t%s\n' "$host" "$r" "$h" "$c" | tee -a "$OUT/public.tsv"
    [[ "$r" == 200 && "$h" == 200 && "$c" == M3U8 ]] || fail=1
  done
done
r="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$OUT/www.radio.root" -w '%{http_code}' https://www.radio.studiosatweb.com.br/ || true)"
portal_ok=1
for st in "${RADIOS[@]}"; do h="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$OUT/www.radio.$st.hls" -w '%{http_code}' "https://www.radio.studiosatweb.com.br/hls/$st/index.m3u8" || true)"; [[ "$h" == 200 ]] && grep -q '^#EXTM3U' "$OUT/www.radio.$st.hls" || portal_ok=0; done
printf 'www.radio.studiosatweb.com.br\t%s\t%s\t%s\n' "$r" "$([[ $portal_ok == 1 ]] && echo 200 || echo FAIL)" PORTAL_HLS | tee -a "$OUT/public.tsv"
[[ "$r" == 200 && $portal_ok == 1 ]] || fail=1

TVHOSTS=(
 'tvkids.studiosatweb.com.br|tvkids' 'www.tvkids.studiosatweb.com.br|tvkids' 'tvkidsweb.studiosatweb.com.br|tvkids' 'www.tvkidsweb.studiosatweb.com.br|tvkids'
 'tvteens.studiosatweb.com.br|tvteens' 'www.tvteens.studiosatweb.com.br|tvteens' 'tvviva.studiosatweb.com.br|tvviva' 'www.tvviva.studiosatweb.com.br|tvviva'
 'tvmaisjovem.studiosatweb.com.br|tvmaisjovem' 'www.tvmaisjovem.studiosatweb.com.br|tvmaisjovem')
for x in "${TVHOSTS[@]}"; do
  host="${x%%|*}"; st="${x#*|}"; hdr="$OUT/${host}.headers"
  r="$(curl -kLsS -D "$hdr" --connect-timeout 5 --max-time 15 -o "$OUT/${host}.root" -w '%{http_code}' "https://$host/" || true)"
  owner=BAD; grep -qi '^X-StudioSat-TV: tv-player-v1' "$hdr" && owner=TV_V1
  h="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$OUT/${host}.hls" -w '%{http_code}' "https://$host/$st/index.m3u8" || true)"; c=NOT_M3U8; [[ "$h" == 200 ]] && grep -q '^#EXTM3U' "$OUT/${host}.hls" && c=M3U8
  printf '%s\t%s\t%s\t%s/%s\n' "$host" "$r" "$h" "$owner" "$c" | tee -a "$OUT/public.tsv"
  [[ "$r" == 200 && "$h" == 200 && "$owner" == TV_V1 && "$c" == M3U8 ]] || fail=1
done

nginx -t > "$OUT/nginx-t.txt" 2>&1 || fail=1
if (( fail == 0 )); then echo NS1_HEALTH_V3=PASS; else echo NS1_HEALTH_V3=FAIL; fi
echo "output=$OUT"
exit "$fail"
