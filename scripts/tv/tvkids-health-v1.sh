#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
UNIT="tps-tvkids-playout.service"
API="http://127.0.0.1:9997/v3/paths/list"
RTSP="rtsp://127.0.0.1:8554/tvkids"
LOCAL_HLS="http://127.0.0.1:8888/tvkids/index.m3u8"
HOSTS=(
  "www.tvkidsweb.studiosatweb.com.br"
  "tvkidsweb.studiosatweb.com.br"
  "tvkids.studiosatweb.com.br"
  "www.tvkids.studiosatweb.com.br"
)
fail=0
ACTIVE="$(systemctl is-active "$UNIT" 2>/dev/null || true)"
PID="$(systemctl show "$UNIT" -p MainPID --value 2>/dev/null || true)"
echo "unit_active=$ACTIVE"
echo "main_pid=$PID"
[[ "$ACTIVE" == "active" && "$PID" =~ ^[1-9][0-9]*$ ]] || fail=1
mtx="$(curl -fsS --connect-timeout 3 --max-time 5 "$API" 2>/dev/null | jq -c '.items[] | select(.name=="tvkids") | {name,ready,tracks,bytesReceived}' | head -n1 || true)"
echo "mediamtx=$mtx"
[[ "$mtx" == *'"ready":true'* ]] || fail=1
probe="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels -of compact=p=0:nk=0 "$RTSP" 2>/dev/null || true)"
printf '%s\n' "$probe"
grep -q 'codec_type=video' <<<"$probe" || fail=1
grep -q 'codec_name=h264' <<<"$probe" || fail=1
grep -q 'width=1280' <<<"$probe" || fail=1
grep -q 'height=720' <<<"$probe" || fail=1
grep -q 'r_frame_rate=30/1' <<<"$probe" || fail=1
grep -q 'codec_type=audio' <<<"$probe" || fail=1
grep -q 'codec_name=aac' <<<"$probe" || fail=1
grep -q 'sample_rate=48000' <<<"$probe" || fail=1
grep -q 'channels=2' <<<"$probe" || fail=1
tmp_local="$(mktemp /tmp/tvkids-health-local.XXXXXX)"
local_hls="$(curl -sS --connect-timeout 3 --max-time 8 -o "$tmp_local" -w '%{http_code}' "$LOCAL_HLS" || true)"
echo "local_hls_http=$local_hls"
[[ "$local_hls" == "200" ]] || fail=1
grep -q '^#EXTM3U' "$tmp_local" 2>/dev/null || fail=1
rm -f "$tmp_local"
printf 'public_host\troot_follow\thls\n'
for host in "${HOSTS[@]}"; do
  tmp_hls="$(mktemp /tmp/tvkids-health-hls.XXXXXX)"
  root="$(curl -kLsS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' "https://${host}/" || true)"
  hls="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$tmp_hls" -w '%{http_code}' "https://${host}/tvkids/index.m3u8" || true)"
  printf '%s\t%s\t%s\n' "$host" "$root" "$hls"
  [[ "$root" == "200" && "$hls" == "200" ]] || fail=1
  grep -q '^#EXTM3U' "$tmp_hls" 2>/dev/null || fail=1
  rm -f "$tmp_hls"
done
if (( fail == 0 )); then
  echo "TVKIDS_PRODUCT_HEALTH=PASS"
  exit 0
fi
echo "TVKIDS_PRODUCT_HEALTH=FAIL"
exit 1
