#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-tvkids-playout.service"
CH="tvkids"
BASE="/srv/tpsmedia/repository/channels/${CH}"
CAN="${BASE}/canonical"
READY="${BASE}/ready"
PL="${BASE}/playlists/playlist.txt"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
PRIV="/var/backups/studiosat/tvkids-p0-${TS}"
OUT="/tmp/tvkids-p0-${TS}"
REPORT="${OUT}/REPORT.txt"

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL: missing $1" >&2; exit 1; }; }
for c in systemctl ffprobe ffmpeg curl sha256sum awk grep sed find sort stat readlink tar; do need "$c"; done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Execute como root: sudo $0" >&2
  exit 1
fi

install -d -m 0700 "$PRIV"
install -d -m 0755 "$OUT"

exec > >(tee "$REPORT") 2>&1

echo "TVKIDS P0 — LOCK CURRENT / CERTIFY"
echo "utc=$TS"
echo "unit=$UNIT"
echo "base=$BASE"
echo

echo "=== 1. ESTADO DO SERVIÇO ==="
systemctl is-active "$UNIT" || true
systemctl show "$UNIT" \
  -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp \
  -p FragmentPath -p DropInPaths -p Restart -p RestartUSec || true

PID="$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || true)"
if [[ -z "$PID" || "$PID" == "0" || ! -d "/proc/$PID" ]]; then
  echo "FATAL: TVKIDS não possui MainPID ativo; NÃO prossiga com restart." >&2
  exit 2
fi
echo "pid=$PID"
echo

echo "=== 2. PRESERVAR PLAYLIST REAL ABERTA PELO FFmpeg ==="
FD_PL=""
for fd in /proc/"$PID"/fd/*; do
  target="$(readlink "$fd" 2>/dev/null || true)"
  if [[ "$target" == *"/channels/tvkids/playlists/playlist.txt"* ]]; then
    FD_PL="$fd"
    echo "active_playlist_fd=$fd"
    echo "active_playlist_target=$target"
    break
  fi
done

if [[ -z "$FD_PL" ]]; then
  echo "FATAL: não localizei a playlist aberta pelo PID $PID." >&2
  exit 3
fi

cp -L -- "$FD_PL" "$PRIV/playlist.running.ffconcat"
cp -L -- "$FD_PL" "$OUT/playlist.running.ffconcat"

if [[ -f "$PL" ]]; then
  cp -a -- "$PL" "$PRIV/playlist.disk.ffconcat"
  cp -a -- "$PL" "$OUT/playlist.disk.ffconcat"
fi

systemctl cat "$UNIT" > "$PRIV/unit.cat.txt"
systemctl cat "$UNIT" > "$OUT/unit.cat.txt"
cp -a /usr/local/sbin/tps-generate-playlist "$PRIV/" 2>/dev/null || true
cp -a /usr/local/sbin/tps-playout-tv "$PRIV/" 2>/dev/null || true

echo "-- running playlist --"
RUN_FILES="$(grep -c '^file ' "$PRIV/playlist.running.ffconcat" || true)"
RUN_CAN="$(grep -c '/canonical/' "$PRIV/playlist.running.ffconcat" || true)"
RUN_READY="$(grep -c '/ready/' "$PRIV/playlist.running.ffconcat" || true)"
echo "files=$RUN_FILES canonical_refs=$RUN_CAN ready_refs=$RUN_READY"
sha256sum "$PRIV/playlist.running.ffconcat"

echo "-- disk playlist --"
if [[ -f "$PRIV/playlist.disk.ffconcat" ]]; then
  DISK_FILES="$(grep -c '^file ' "$PRIV/playlist.disk.ffconcat" || true)"
  DISK_CAN="$(grep -c '/canonical/' "$PRIV/playlist.disk.ffconcat" || true)"
  DISK_READY="$(grep -c '/ready/' "$PRIV/playlist.disk.ffconcat" || true)"
  echo "files=$DISK_FILES canonical_refs=$DISK_CAN ready_refs=$DISK_READY"
  sha256sum "$PRIV/playlist.disk.ffconcat"
  stat "$PL" || true
fi
echo

echo "=== 3. ARQUIVO QUE ESTÁ SENDO LIDO AGORA ==="
for fd in /proc/"$PID"/fd/*; do
  target="$(readlink "$fd" 2>/dev/null || true)"
  case "$target" in
    "$CAN"/*.mp4|"$READY"/*.mp4)
      echo "media_fd=$fd"
      echo "media=$target"
      ;;
  esac
done
echo

echo "=== 4. INVENTÁRIO E SHA256 DO CANONICAL (somente leitura) ==="
if [[ ! -d "$CAN" ]]; then
  echo "FATAL: canonical ausente: $CAN" >&2
  exit 4
fi

find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 \
  | sort -z \
  | while IFS= read -r -d '' f; do
      nice -n 19 ionice -c3 sha256sum "$f"
    done | tee "$OUT/canonical.sha256"

CAN_COUNT="$(wc -l < "$OUT/canonical.sha256" | tr -d ' ')"
echo "canonical_count=$CAN_COUNT"
echo

echo "=== 5. CONTRATO ESTRUTURAL DE TODOS OS CANONICAL ==="
printf 'status\tfile\tvcodec\twidth\theight\tpix_fmt\tfps\ttime_base_v\tacodec\trate\tchannels\tlayout\ttime_base_a\tstart\tduration\n' \
  > "$OUT/canonical-profile.tsv"

while IFS= read -r -d '' f; do
  v="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,time_base \
        -of default=nw=1:nk=1 "$f" 2>/dev/null | paste -sd $'\t' - || true)"
  a="$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels,channel_layout,time_base \
        -of default=nw=1:nk=1 "$f" 2>/dev/null | paste -sd $'\t' - || true)"
  fmt="$(ffprobe -v error -show_entries format=start_time,duration \
        -of default=nw=1:nk=1 "$f" 2>/dev/null | paste -sd $'\t' - || true)"

  ok="PASS"
  [[ "$v" == $'h264\t1280\t720\tyuv420p\t30/1\t1/90000' ]] || ok="FAIL"
  [[ "$a" == $'aac\t48000\t2\tstereo\t1/48000' ]] || ok="FAIL"

  printf '%s\t%s\t%s\t%s\t%s\n' "$ok" "$(basename "$f")" "$v" "$a" "$fmt" \
    >> "$OUT/canonical-profile.tsv"
done < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)

echo "profile_failures=$(awk -F '\t' 'NR>1 && $1!="PASS"{n++} END{print n+0}' "$OUT/canonical-profile.tsv")"
echo

echo "=== 6. GERAR CANDIDATE.FFCONCAT EM /tmp — NÃO ALTERA PRODUÇÃO ==="
CAND="$OUT/candidate.ffconcat"
printf 'ffconcat version 1.0\n' > "$CAND"
while IFS= read -r -d '' f; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$CAND"
done < <(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
echo "candidate_files=$(grep -c '^file ' "$CAND")"
sha256sum "$CAND"
echo

echo "=== 7. TESTE ACELERADO DAS TRANSIÇÕES + FLV, SEM MediaMTX ==="
set +e
nice -n 19 ionice -c3 \
  ffmpeg -hide_banner -nostdin -loglevel warning \
    -f concat -safe 0 -i "$CAND" \
    -map 0:v:0 -map 0:a:0 -c copy \
    -f flv /dev/null \
    >"$OUT/concat-flv.stdout" 2>"$OUT/concat-flv.stderr"
RC=$?
set -e
echo "concat_flv_rc=$RC"
echo "non_monotonic_dts=$(grep -ci 'Non-monotonic DTS' "$OUT/concat-flv.stderr" || true)"
echo "decoder_errors=$(grep -Eci 'Invalid data|Error splitting|No start code|Error submitting|corrupt' "$OUT/concat-flv.stderr" || true)"
echo

echo "=== 8. QUATRO DOMÍNIOS: ROOT, HTML DIRETO E HLS ==="
printf 'host\troot\ttvkids_html\thls\n' > "$OUT/domains.tsv"
for host in \
  www.tvkidsweb.studiosatweb.com.br \
  tvkidsweb.studiosatweb.com.br \
  tvkids.studiosatweb.com.br \
  www.tvkids.studiosatweb.com.br
do
  root_code="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/" || echo ERR)"
  html_code="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/tvkids.html" || echo ERR)"
  hls_code="$(curl -kLsS --connect-timeout 5 --max-time 12 -o /dev/null -w '%{http_code}' "https://${host}/tvkids/index.m3u8" || echo ERR)"
  printf '%s\t%s\t%s\t%s\n' "$host" "$root_code" "$html_code" "$hls_code" | tee -a "$OUT/domains.tsv"
done
echo

echo "=== 9. CORE SEM ALTERAÇÃO ==="
nginx -t 2>&1 || true
curl -fsS --connect-timeout 3 --max-time 5 \
  http://127.0.0.1:9997/v3/paths/list > "$OUT/mediamtx-paths.json" 2>"$OUT/mediamtx-api.err" || true
curl -fsS --connect-timeout 3 --max-time 5 \
  http://127.0.0.1:8888/tvkids/index.m3u8 > "$OUT/hls-local.m3u8" 2>"$OUT/hls-local.err" || true

echo
echo "=== 10. JOURNAL TVKIDS ÚLTIMOS 60 MIN ==="
journalctl -u "$UNIT" --since '-60 min' --no-pager > "$OUT/journal-60m.txt" || true
echo "dts_60m=$(grep -ci 'Non-monotonic DTS' "$OUT/journal-60m.txt" || true)"
echo "fatal_60m=$(grep -Eci 'FATAL|segfault|core dump|Connection refused|Invalid data|No start code' "$OUT/journal-60m.txt" || true)"
echo

echo "=== 11. EMPACOTAR RESULTADO SHAREABLE ==="
tar -C /tmp -czf "/tmp/tvkids-p0-${TS}.shareable.tar.gz" "tvkids-p0-${TS}"
sha256sum "/tmp/tvkids-p0-${TS}.shareable.tar.gz" | tee "/tmp/tvkids-p0-${TS}.shareable.tar.gz.sha256"

echo
echo "DONE"
echo "private_backup=$PRIV"
echo "shareable=/tmp/tvkids-p0-${TS}.shareable.tar.gz"
echo "sha256=/tmp/tvkids-p0-${TS}.shareable.tar.gz.sha256"
echo
echo "NENHUM serviço foi reiniciado/recarregado e nenhum arquivo de produção foi editado."
