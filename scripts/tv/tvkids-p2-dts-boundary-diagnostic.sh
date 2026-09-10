#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-tvkids-playout.service"
CH="tvkids"
BASE="/srv/tpsmedia/repository/channels/${CH}"
CAN="${BASE}/canonical"
PL="${BASE}/playlists/playlist.txt"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/tvkids-p2-dts-${TS}"
SUMMARY="${OUT}/summary.tsv"
REPORT="${OUT}/REPORT.txt"

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL: comando ausente: $1" >&2; exit 1; }; }
for c in systemctl ffmpeg ffprobe sha256sum grep awk sed find sort timeout nice ionice readlink mktemp tar wc head tail install cp journalctl basename; do need "$c"; done

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL: execute como root" >&2; exit 1; }
[[ -f "$PL" ]] || { echo "FATAL: playlist ausente: $PL" >&2; exit 1; }
[[ -d "$CAN" ]] || { echo "FATAL: canonical ausente: $CAN" >&2; exit 1; }
systemctl is-active --quiet "$UNIT" || { echo "FATAL: $UNIT não está active" >&2; exit 1; }

install -d -m 0755 "$OUT" "$OUT/cases" "$OUT/logs"
exec > >(tee "$REPORT") 2>&1

echo "TVKIDS P2 — DTS BOUNDARY DIAGNOSTIC"
echo "utc=$TS"
echo "unit=$UNIT"
echo "playlist=$PL"
echo

PID="$(systemctl show -p MainPID --value "$UNIT")"
[[ "$PID" =~ ^[1-9][0-9]*$ && -d "/proc/$PID" ]] || { echo "FATAL: MainPID inválido" >&2; exit 1; }
echo "pid=$PID"

RUNFD=""
for fd in /proc/"$PID"/fd/*; do
  target="$(readlink "$fd" 2>/dev/null || true)"
  if [[ "$target" == *"/channels/tvkids/playlists/playlist.txt"* ]]; then
    RUNFD="$fd"
    echo "running_playlist_fd=$fd"
    echo "running_playlist_target=$target"
    break
  fi
done
[[ -n "$RUNFD" ]] || { echo "FATAL: playlist aberta não localizada no PID $PID" >&2; exit 1; }

cp -L -- "$RUNFD" "$OUT/playlist.running.ffconcat"
cp -a -- "$PL" "$OUT/playlist.disk.ffconcat"
RUN_SHA="$(sha256sum "$OUT/playlist.running.ffconcat" | awk '{print $1}')"
DISK_SHA="$(sha256sum "$OUT/playlist.disk.ffconcat" | awk '{print $1}')"
echo "running_sha=$RUN_SHA"
echo "disk_sha=$DISK_SHA"
[[ "$RUN_SHA" == "$DISK_SHA" ]] || { echo "FATAL: playlist em disco difere da playlist ON-AIR" >&2; exit 2; }

mapfile -t ITEMS < <(grep '^file ' "$PL")
FILES=()
while IFS= read -r -d '' f; do
  b="$(basename "$f")"
  [[ "$b" == *teste* || "$b" == *test* ]] && continue
  FILES+=("$f")
done < <(find "$CAN" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' \) -print0 | sort -z)

N="${#ITEMS[@]}"
CAN_REFS="$(grep -c '/canonical/' "$PL" || true)"
READY_REFS="$(grep -c '/ready/' "$PL" || true)"
echo "items=$N canonical_refs=$CAN_REFS ready_refs=$READY_REFS canonical_files=${#FILES[@]}"
[[ "$N" -gt 1 ]] || { echo "FATAL: playlist precisa de pelo menos 2 itens" >&2; exit 2; }
[[ "$CAN_REFS" -eq "$N" && "$READY_REFS" -eq 0 ]] || { echo "FATAL: playlist não é 100% canonical" >&2; exit 2; }
[[ "${#FILES[@]}" -eq "$N" ]] || { echo "FATAL: contagem playlist/canonical diverge" >&2; exit 2; }

EXPECTED="$OUT/cases/expected-from-canonical.ffconcat"
printf 'ffconcat version 1.0\n' > "$EXPECTED"
for f in "${FILES[@]}"; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$EXPECTED"
done
EXPECTED_SHA="$(sha256sum "$EXPECTED" | awk '{print $1}')"
echo "expected_from_canonical_sha=$EXPECTED_SHA"
[[ "$EXPECTED_SHA" == "$DISK_SHA" ]] || { echo "FATAL: ordem canonical não reproduz playlist vigente" >&2; exit 2; }

echo
printf 'case\ttype\trc\tdts_errors\tother_errors\n' > "$SUMMARY"

make_case() {
  local name="$1"; shift
  local list="$OUT/cases/${name}.ffconcat"
  printf 'ffconcat version 1.0\n' > "$list"
  printf '%s\n' "$@" >> "$list"
  echo "$list"
}

count_dts() {
  local log="$1"
  grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$log" 2>/dev/null || true
}

count_other() {
  local log="$1"
  grep -Eic 'Invalid data|Error splitting|No start code|Error submitting|corrupt|Broken pipe|Could not|failed|Conversion failed' "$log" 2>/dev/null || true
}

run_case() {
  local name="$1" type="$2" list="$3"
  local log="$OUT/logs/${name}.stderr.log"
  local rc dts other

  set +e
  nice -n 19 ionice -c3 timeout 300 \
    ffmpeg -hide_banner -nostdin -loglevel warning -y \
      -f concat -safe 0 -i "$list" \
      -map 0:v:0 -map 0:a:0 \
      -c copy -f flv /dev/null \
      > /dev/null 2> "$log"
  rc=$?
  set -e

  dts="$(count_dts "$log")"
  other="$(count_other "$log")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$type" "$rc" "$dts" "$other" >> "$SUMMARY"
  printf '%-26s type=%-10s rc=%-3s dts=%-4s other=%s\n' "$name" "$type" "$rc" "$dts" "$other"
}

run_direct_asset() {
  local name="$1" file="$2"
  local log="$OUT/logs/${name}.stderr.log"
  local rc dts other
  set +e
  nice -n 19 ionice -c3 timeout 300 \
    ffmpeg -hide_banner -nostdin -loglevel warning -y \
      -i "$file" -map 0:v:0 -map 0:a:0 \
      -c copy -f flv /dev/null \
      > /dev/null 2> "$log"
  rc=$?
  set -e
  dts="$(count_dts "$log")"
  other="$(count_other "$log")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "single" "$rc" "$dts" "$other" >> "$SUMMARY"
  printf '%-26s type=%-10s rc=%-3s dts=%-4s other=%s  %s\n' "$name" "single" "$rc" "$dts" "$other" "$(basename "$file")"
}

echo "=== A. CADA ASSET ISOLADAMENTE (MP4 -> FLV, SEM CONCAT) ==="
for ((i=0; i<N; i++)); do
  name="asset-$(printf '%02d' $((i+1)))"
  run_direct_asset "$name" "${FILES[$i]}"
done

echo
echo "=== B. CADA BOUNDARY A -> B, INCLUINDO ÚLTIMO -> PRIMEIRO ==="
for ((i=0; i<N; i++)); do
  j=$(( (i + 1) % N ))
  name="boundary-$(printf '%02d' $((i+1)))-$(printf '%02d' $((j+1)))"
  list="$(make_case "$name" "${ITEMS[$i]}" "${ITEMS[$j]}")"
  run_case "$name" "boundary" "$list"
done

echo
echo "=== C. PLAYLIST COMPLETA — 1 CICLO ==="
run_case "full-1x" "full" "$PL"

echo
echo "=== D. PLAYLIST COMPLETA — 2 CICLOS CONCATENADOS ==="
DOUBLE="$OUT/cases/full-2x.ffconcat"
printf 'ffconcat version 1.0\n' > "$DOUBLE"
printf '%s\n' "${ITEMS[@]}" >> "$DOUBLE"
printf '%s\n' "${ITEMS[@]}" >> "$DOUBLE"
run_case "full-2x" "full2x" "$DOUBLE"

echo
echo "=== E. INVENTÁRIO TEMPORAL POR STREAM ==="
printf 'item\tfile\tvideo_probe\taudio_probe\tformat_probe\n' > "$OUT/timing.tsv"
for ((i=0; i<N; i++)); do
  f="${FILES[$i]}"
  v="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,start_time,duration,time_base,avg_frame_rate \
        -of compact=p=0:nk=0 "$f" 2>/dev/null | head -n1 || true)"
  a="$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,start_time,duration,time_base,sample_rate,channels,channel_layout \
        -of compact=p=0:nk=0 "$f" 2>/dev/null | head -n1 || true)"
  fm="$(ffprobe -v error -show_entries format=start_time,duration \
         -of compact=p=0:nk=0 "$f" 2>/dev/null | head -n1 || true)"
  printf '%02d\t%s\t%s\t%s\t%s\n' "$((i+1))" "$(basename "$f")" "$v" "$a" "$fm" >> "$OUT/timing.tsv"
done

DTS_TOTAL="$(awk -F '\t' 'NR>1{s+=$4} END{print s+0}' "$SUMMARY")"
SINGLE_DTS="$(awk -F '\t' 'NR>1 && $2=="single"{s+=$4} END{print s+0}' "$SUMMARY")"
BOUNDARY_DTS="$(awk -F '\t' 'NR>1 && $2=="boundary"{s+=$4} END{print s+0}' "$SUMMARY")"
FULL1_DTS="$(awk -F '\t' 'NR>1 && $1=="full-1x"{print $4+0}' "$SUMMARY")"
FULL2_DTS="$(awk -F '\t' 'NR>1 && $1=="full-2x"{print $4+0}' "$SUMMARY")"
FAILED_CASES="$(awk -F '\t' 'NR>1 && $3!=0{n++} END{print n+0}' "$SUMMARY")"

echo
echo "=== RESULTADO RESUMIDO ==="
echo "single_dts=$SINGLE_DTS"
echo "boundary_dts=$BOUNDARY_DTS"
echo "full_1x_dts=$FULL1_DTS"
echo "full_2x_dts=$FULL2_DTS"
echo "all_case_dts=$DTS_TOTAL"
echo "failed_cases=$FAILED_CASES"

echo
echo "=== CASOS COM DTS/ERRO ==="
awk -F '\t' 'NR==1 || $3!=0 || $4!=0 || $5!=0' "$SUMMARY" || true

echo
echo "=== ESTADO ON-AIR DURANTE O TESTE ==="
PID_AFTER="$(systemctl show -p MainPID --value "$UNIT")"
ACTIVE="$(systemctl is-active "$UNIT" || true)"
echo "active=$ACTIVE"
echo "pid_before=$PID"
echo "pid_after=$PID_AFTER"

journalctl -u "$UNIT" --since '-15 min' --no-pager > "$OUT/journal-last15m.txt" || true
LIVE_DTS="$(count_dts "$OUT/journal-last15m.txt")"
echo "live_dts_last15m=$LIVE_DTS"

TARBALL="/tmp/tvkids-p2-dts-${TS}.shareable.tar.gz"
tar -C /tmp -czf "$TARBALL" "tvkids-p2-dts-${TS}"
sha256sum "$TARBALL" | tee "${TARBALL}.sha256"

echo
echo "=== ARTEFATOS ==="
echo "summary=$SUMMARY"
echo "timing=$OUT/timing.tsv"
echo "shareable=$TARBALL"
echo "sha256=${TARBALL}.sha256"
echo
echo "P2 concluído: diagnóstico somente leitura da cadeia de mídia; produção permaneceu no mesmo PID quando pid_before=pid_after."
