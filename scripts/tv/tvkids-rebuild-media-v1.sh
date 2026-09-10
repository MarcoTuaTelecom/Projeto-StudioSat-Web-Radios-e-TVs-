#!/usr/bin/env bash
[[ "${TVKIDS_REBUILD_ORCHESTRATOR:-0}" == 1 ]] || { echo "FATAL=SOURCE_ONLY"; return 1 2>/dev/null || exit 1; }

mapfile -d '' -t SOURCE_FILES < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
N="${#SOURCE_FILES[@]}"
[[ "$N" -eq "$RUN_ITEMS" ]] || fail "CANONICAL_COUNT_DIFFERS_FROM_ON_AIR_PLAYLIST"

printf 'ffconcat version 1.0\n' > "$WORK/source.ffconcat"
for f in "${SOURCE_FILES[@]}"; do esc=${f//\'/\'\\\'\'}; printf "file '%s'\n" "$esc" >> "$WORK/source.ffconcat"; done
[[ "$(sha "$WORK/source.ffconcat")" == "$RUN_SHA" ]] || fail "CANONICAL_ORDER_DIFFERS_FROM_ON_AIR"

printf 'file\tprofile\tfull_decode\n' > "$OUT/current-certification.tsv"
CURRENT_CERT_PASS=1
idx=0
for f in "${SOURCE_FILES[@]}"; do
  idx=$((idx+1)); b="$(basename "$f")"; js="$OUT/probe-current-$(printf '%03d' "$idx").json"
  ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,time_base,sample_rate,channels -of json "$f" > "$js" || true
  profile=FAIL
  jq -e '([.streams[]|select(.codec_type=="video")]|length)==1 and ([.streams[]|select(.codec_type=="audio")]|length)==1 and ([.streams[]|select(.codec_type=="video")][0]|.codec_name=="h264" and .width==1280 and .height==720 and .pix_fmt=="yuv420p" and .r_frame_rate=="30/1" and .time_base=="1/90000") and ([.streams[]|select(.codec_type=="audio")][0]|.codec_name=="aac" and .sample_rate=="48000" and .channels==2 and .time_base=="1/48000")' "$js" >/dev/null 2>&1 && profile=PASS
  decode=FAIL
  nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -v error -xerror -threads 1 -i "$f" -map 0:v:0 -map 0:a:0 -f null - >/dev/null 2>"$OUT/decode-current-${idx}.log" && decode=PASS
  printf '%s\t%s\t%s\n' "$b" "$profile" "$decode" | tee -a "$OUT/current-certification.tsv"
  [[ "$profile" == PASS && "$decode" == PASS ]] || CURRENT_CERT_PASS=0
done

test_temporal(){
  local list="$1" loop="$2" prefix="$3" log="$OUT/${3}.stderr.log" rc dts other
  set +e
  if [[ "$loop" == 1 ]]; then
    nice -n 19 ionice -c3 timeout 600 ffmpeg -hide_banner -nostdin -loglevel warning -y -stream_loop 1 -f concat -safe 0 -i "$list" -map 0:v:0 -map 0:a:0 -c copy -f flv /dev/null >/dev/null 2>"$log"
  else
    nice -n 19 ionice -c3 timeout 600 ffmpeg -hide_banner -nostdin -loglevel warning -y -f concat -safe 0 -i "$list" -map 0:v:0 -map 0:a:0 -c copy -f flv /dev/null >/dev/null 2>"$log"
  fi
  rc=$?
  set -e
  dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$log" || true)"
  other="$(grep -Eic 'Invalid data|Error splitting|No start code|corrupt|Conversion failed|Could not write|Broken pipe' "$log" || true)"
  echo "${prefix}_rc=$rc ${prefix}_dts=$dts ${prefix}_other=$other"
  [[ "$rc" -eq 0 && "$dts" -eq 0 && "$other" -eq 0 ]]
}

printf 'ffconcat version 1.0\n' > "$WORK/source-2x.ffconcat"
tail -n +2 "$WORK/source.ffconcat" >> "$WORK/source-2x.ffconcat"
tail -n +2 "$WORK/source.ffconcat" >> "$WORK/source-2x.ffconcat"
CURRENT_TEMPORAL_PASS=0
test_temporal "$WORK/source-2x.ffconcat" 0 current_2x && test_temporal "$WORK/source.ffconcat" 1 current_loop && CURRENT_TEMPORAL_PASS=1 || true

USE_NORMALIZED=0
(( CURRENT_CERT_PASS == 1 && CURRENT_TEMPORAL_PASS == 1 )) || USE_NORMALIZED=1
FINAL_FILES=()

if (( USE_NORMALIZED == 1 )); then
  echo "canonical_action=NORMALIZE_ALL"
  printf 'source\tresult\n' > "$OUT/normalization.tsv"
  idx=0
  for src in "${SOURCE_FILES[@]}"; do
    idx=$((idx+1)); b="$(basename "$src")"; dst="$CANDCAN/$b"
    if bash "$NORMALIZER" "$src" "$dst" >"$OUT/normalize-${idx}.out" 2>"$OUT/normalize-${idx}.err"; then
      printf '%s\tPASS\n' "$b" | tee -a "$OUT/normalization.tsv"
    else
      printf '%s\tEXCLUDED\n' "$b" | tee -a "$OUT/normalization.tsv"; rm -f -- "$dst"
    fi
  done
  mapfile -d '' -t CAND_FILES < <(find "$CANDCAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
  ((${#CAND_FILES[@]} >= 2)) || fail "LESS_THAN_TWO_NORMALIZED_ASSETS"

  idx=0
  for f in "${CAND_FILES[@]}"; do
    idx=$((idx+1)); js="$OUT/probe-candidate-$(printf '%03d' "$idx").json"
    ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,time_base,sample_rate,channels -of json "$f" > "$js"
    jq -e '([.streams[]|select(.codec_type=="video")]|length)==1 and ([.streams[]|select(.codec_type=="audio")]|length)==1 and ([.streams[]|select(.codec_type=="video")][0]|.codec_name=="h264" and .width==1280 and .height==720 and .pix_fmt=="yuv420p" and .r_frame_rate=="30/1" and .time_base=="1/90000") and ([.streams[]|select(.codec_type=="audio")][0]|.codec_name=="aac" and .sample_rate=="48000" and .channels==2 and .time_base=="1/48000")' "$js" >/dev/null || fail "NORMALIZED_PROFILE_FAIL"
    nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -v error -xerror -threads 1 -i "$f" -map 0:v:0 -map 0:a:0 -f null - >/dev/null 2>"$OUT/decode-candidate-${idx}.log" || fail "NORMALIZED_DECODE_FAIL"
    FINAL_FILES+=("$f")
  done
  printf 'ffconcat version 1.0\n' > "$WORK/candidate-physical.ffconcat"
  for f in "${FINAL_FILES[@]}"; do esc=${f//\'/\'\\\'\'}; printf "file '%s'\n" "$esc" >> "$WORK/candidate-physical.ffconcat"; done
  printf 'ffconcat version 1.0\n' > "$WORK/candidate-physical-2x.ffconcat"
  tail -n +2 "$WORK/candidate-physical.ffconcat" >> "$WORK/candidate-physical-2x.ffconcat"
  tail -n +2 "$WORK/candidate-physical.ffconcat" >> "$WORK/candidate-physical-2x.ffconcat"
  test_temporal "$WORK/candidate-physical-2x.ffconcat" 0 normalized_2x || fail "NORMALIZED_2X_DTS"
  test_temporal "$WORK/candidate-physical.ffconcat" 1 normalized_loop || fail "NORMALIZED_LOOP_DTS"
else
  echo "canonical_action=REUSE_CERTIFIED"
  FINAL_FILES=("${SOURCE_FILES[@]}")
fi

: > "$CANDMAN"
if (( USE_NORMALIZED == 1 )); then
  for f in "${FINAL_FILES[@]}"; do printf '%s\t%s/%s\n' "$(sha "$f")" "$CAN" "$(basename "$f")" >> "$CANDMAN"; done
else
  for f in "${FINAL_FILES[@]}"; do printf '%s\t%s\n' "$(sha "$f")" "$f" >> "$CANDMAN"; done
fi
echo "media_gate=PASS normalized=$USE_NORMALIZED manifest_items=$(wc -l < "$CANDMAN")"
