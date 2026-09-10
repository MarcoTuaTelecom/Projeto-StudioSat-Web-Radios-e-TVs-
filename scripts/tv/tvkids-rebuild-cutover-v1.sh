#!/usr/bin/env bash
[[ "${TVKIDS_REBUILD_ORCHESTRATOR:-0}" == 1 ]] || { echo "FATAL=SOURCE_ONLY"; return 1 2>/dev/null || exit 1; }

ROOT_BAD=0
for host in tvkidsweb.studiosatweb.com.br tvkids.studiosatweb.com.br; do
  code="$(curl -kLsS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' "https://${host}/" || true)"
  echo "pre_root_follow ${host}=${code}"
  [[ "$code" == 200 ]] || ROOT_BAD=1
done

NGCAND="$WORK/nginx.candidate.conf"
if (( ROOT_BAD == 1 )); then
  python3 "$NGPATCHER" "$NGCONF" "$NGCAND"
  diff -u "$NGCONF" "$NGCAND" > "$OUT/nginx.diff" || true
  grep -q TVKIDS_CANONICAL_ROOT_REDIRECT_v1 "$NGCAND" || fail "NGINX_CANDIDATE_INVALID"
else
  cp -a -- "$NGCONF" "$NGCAND"
fi

MUTATED=1
install -o root -g root -m 0755 "$CAND_BUILDER" "$BUILDER"
install -o root -g root -m 0755 "$CAND_HEALTH" "$HEALTH"

GEN_CAND="$WORK/tps-generate-playlist.candidate"
python3 - "$GEN" "$GEN_CAND" <<'PY'
from pathlib import Path
import re,sys
src,dst=map(Path,sys.argv[1:])
s=src.read_text()
dedicated=('# TVKIDS_DEDICATED_PLAN_BUILDER_V1\n'
           'if [[ "$CH" == "tvkids" ]]; then\n'
           '  exec /usr/local/sbin/tps-tvkids-build-plan\n'
           'fi')
if 'TVKIDS_DEDICATED_PLAN_BUILDER_V1' in s:
    out=s
elif 'TVKIDS_RESTART_GUARD' in s:
    p=re.compile(r'# TVKIDS_RESTART_GUARD:[^\n]*\nif \[\[ "\$CH" == "tvkids" \]\]; then\n\s*MEDIA_ROOT="\$\{BASE\}/canonical"\nfi')
    out,n=p.subn(dedicated,s,count=1)
    if n != 1: raise SystemExit('FATAL: P1 guard shape unexpected')
else:
    raise SystemExit('FATAL: TVKIDS guard missing')
dst.write_text(out)
PY
bash -n "$GEN_CAND"
grep -q TVKIDS_DEDICATED_PLAN_BUILDER_V1 "$GEN_CAND" || fail "GENERATOR_DISPATCH_INVALID"
install -o "$(stat -c %u "$GEN")" -g "$(stat -c %g "$GEN")" -m "$(stat -c %a "$GEN")" "$GEN_CAND" "${GEN}.new-${TS}"
mv -f -- "${GEN}.new-${TS}" "$GEN"

install -d -o tpsmedia -g tpsmedia -m 0755 "$STATE" "$PLDIR" "$ARCHIVE"
install -o tpsmedia -g tpsmedia -m 0644 "$CANDMAN" "$STATE/ready.manifest.tsv.candidate-${TS}"

echo "cutover=START"
systemctl stop "$UNIT"
if (( USE_NORMALIZED == 1 )); then
  ARCH_PATH="${ARCHIVE}/pre-rebuild-${TS}"
  mkdir -p "$ARCH_PATH"
  printf '%s\n' "$ARCH_PATH/canonical.pre-rebuild" > "$BACKUP/canonical.pre-rebuild.path"
  mv -- "$CAN" "$ARCH_PATH/canonical.pre-rebuild"
  CAN_SWAPPED=1
  mv -- "$CANDCAN" "$CAN"
  chown -R tpsmedia:tpsmedia "$CAN"
  find "$CAN" -type d -exec chmod 0755 {} +
  find "$CAN" -type f -exec chmod 0644 {} +
fi
mv -f -- "$STATE/ready.manifest.tsv.candidate-${TS}" "$STATE/ready.manifest.tsv"
chown tpsmedia:tpsmedia "$STATE/ready.manifest.tsv"
chmod 0644 "$STATE/ready.manifest.tsv"

runuser -u tpsmedia -- "$BUILDER" | tee "$OUT/plan-build.txt"
grep -q '^TVKIDS_PLAN_OK' "$OUT/plan-build.txt" || fail "PLAN_BUILD_FAILED"

systemctl start "$UNIT"
for _ in $(seq 1 30); do
  [[ "$(systemctl is-active "$UNIT" || true)" == active ]] && break
  sleep 1
done
[[ "$(systemctl is-active "$UNIT" || true)" == active ]] || fail "TVKIDS_NOT_ACTIVE_POST"
PID_POST="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$PID_POST" =~ ^[1-9][0-9]*$ && "$PID_POST" != "$PID_PRE" ]] || fail "TVKIDS_PID_INVALID_POST"
echo "post_pid=$PID_POST"

MTX_READY=""
for _ in $(seq 1 30); do
  MTX_READY="$(curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]|select(.name=="tvkids")|.ready' | head -n1 || true)"
  [[ "$MTX_READY" == true ]] && break
  sleep 1
done
[[ "$MTX_READY" == true ]] || fail "MEDIAMTX_TVKIDS_NOT_READY"

timeout 15 ffprobe -v error -rtsp_transport tcp \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -of compact=p=0:nk=0 rtsp://127.0.0.1:8554/tvkids | tee "$OUT/rtsp.post.txt"
grep -q 'codec_type=video' "$OUT/rtsp.post.txt" && grep -q 'codec_name=h264' "$OUT/rtsp.post.txt" \
  && grep -q 'width=1280' "$OUT/rtsp.post.txt" && grep -q 'height=720' "$OUT/rtsp.post.txt" \
  && grep -q 'r_frame_rate=30/1' "$OUT/rtsp.post.txt" || fail "RTSP_VIDEO_PROFILE_BAD"
grep -q 'codec_type=audio' "$OUT/rtsp.post.txt" && grep -q 'codec_name=aac' "$OUT/rtsp.post.txt" \
  && grep -q 'sample_rate=48000' "$OUT/rtsp.post.txt" && grep -q 'channels=2' "$OUT/rtsp.post.txt" \
  || fail "RTSP_AUDIO_PROFILE_BAD"

for _ in $(seq 1 20); do
  code="$(curl -sS --connect-timeout 3 --max-time 8 -o "$OUT/local.post.m3u8" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
  [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$OUT/local.post.m3u8" && break
  sleep 1
done
[[ "${code:-}" == 200 ]] || fail "LOCAL_HLS_BAD"
echo "media_cutover=PASS"
