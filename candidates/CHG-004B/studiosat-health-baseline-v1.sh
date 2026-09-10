#!/usr/bin/env bash
# StudioSat Web — Health Baseline v1.0-candidate
# Change: CHG-004B
# Safety: READ-ONLY sobre produção; escreve somente em /tmp.
# Objetivo: snapshot repetível antes/depois de cada change, sem falsos PASS de HLS.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0-candidate"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="/tmp/studiosat-health-baseline-${HOST}-${STAMP}"
ARCHIVE="${OUT}.tar.gz"
ROOT="/srv/tpsmedia/repository/channels"
MTX_API="http://127.0.0.1:9997/v3/paths/list"

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
CHANNELS=("${RADIOS[@]}" "${TVS[@]}")

mkdir -p "$OUT"/{core,stations,hashes,meta}
chmod 0700 "$OUT"

have(){ command -v "$1" >/dev/null 2>&1; }
need(){ have "$1" || { echo "FATAL=MISSING_COMMAND:$1" >&2; exit 66; }; }
for c in curl jq systemctl journalctl ffprobe sha256sum tar grep find awk sed timeout; do need "$c"; done

portal_url(){
  case "$1" in
    radioprincipal) printf '%s\n' 'https://www.radioprincipal.studiosatweb.com.br/' ;;
    radiopop) printf '%s\n' 'https://www.radiopop.studiosatweb.com.br/' ;;
    radiorock) printf '%s\n' 'https://www.radiorock.studiosatweb.com.br/' ;;
    radioclassicas) printf '%s\n' 'https://www.radioclassicas.studiosatweb.com.br/' ;;
    radiocountry) printf '%s\n' 'https://www.radiocountry.studiosatweb.com.br/' ;;
    tvkids) printf '%s\n' 'https://www.tvkids.studiosatweb.com.br/' ;;
    tvteens) printf '%s\n' 'https://www.tvteens.studiosatweb.com.br/' ;;
    tvviva) printf '%s\n' 'https://www.tvviva.studiosatweb.com.br/' ;;
    tvmaisjovem) printf '%s\n' 'https://www.tvmaisjovem.studiosatweb.com.br/' ;;
  esac
}

is_manifest(){
  local f="$1"
  [[ -s "$f" ]] && grep -q '^#EXTM3U' "$f" 2>/dev/null
}

printf 'STUDIOSAT_HEALTH_BASELINE_VERSION=%s\nHOST=%s\nUTC=%s\nREAD_ONLY=YES\n' \
  "$VERSION" "$HOST" "$STAMP" > "$OUT/meta/identity.txt"

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
if [[ -d "$REPO/.git" ]]; then
  git -C "$REPO" rev-parse HEAD > "$OUT/meta/git-head.txt" 2>&1 || true
  git -C "$REPO" status --short > "$OUT/meta/git-status.txt" 2>&1 || true
else
  echo "REPO_NOT_FOUND" > "$OUT/meta/git-head.txt"
fi

printf 'check\tstate\tdetail\n' > "$OUT/core/core.tsv"
for unit in tps-mediamtx.service nginx.service; do
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  [[ -n "$state" ]] || state=unknown
  printf '%s\t%s\t%s\n' "$unit" "$state" "$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)" >> "$OUT/core/core.tsv"
done

if nginx -t >"$OUT/core/nginx-t.txt" 2>&1; then
  printf 'nginx_config\tPASS\tnginx -t\n' >> "$OUT/core/core.tsv"
else
  printf 'nginx_config\tFAIL\tnginx -t\n' >> "$OUT/core/core.tsv"
fi

root_use="$(df -P / | awk 'NR==2 {print $5}')"
mem_avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
load1="$(awk '{print $1}' /proc/loadavg)"
printf 'root_disk_use\tINFO\t%s\n' "$root_use" >> "$OUT/core/core.tsv"
printf 'mem_available_kb\tINFO\t%s\n' "$mem_avail_kb" >> "$OUT/core/core.tsv"
printf 'load1\tINFO\t%s\n' "$load1" >> "$OUT/core/core.tsv"

if curl -fsS --max-time 5 "$MTX_API" > "$OUT/core/mediamtx-paths.json"; then
  printf 'mediamtx_api\tPASS\t%s\n' "$MTX_API" >> "$OUT/core/core.tsv"
else
  echo '{"items":[]}' > "$OUT/core/mediamtx-paths.json"
  printf 'mediamtx_api\tFAIL\t%s\n' "$MTX_API" >> "$OUT/core/core.tsv"
fi

printf 'sha256\tpath\tkind\n' > "$OUT/hashes/critical-static.tsv"
STATIC=(
  /usr/local/sbin/tps-generate-playlist
  /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
  /usr/local/sbin/tps-playout-radio
  /usr/local/sbin/tps-playout-tv
  /etc/tpsmedia/mediamtx/mediamtx.yml
  /etc/nginx/nginx.conf
  /etc/nginx/conf.d/tps-9-emissoras.conf
  /etc/nginx/conf.d/tps-studiosatweb.conf
  /etc/nginx/conf.d/tps-tpsolutions-https.conf
)
for f in "${STATIC[@]}"; do
  if [[ -f "$f" ]]; then
    h="$(sha256sum "$f" | awk '{print $1}')"
    printf '%s\t%s\tstatic\n' "$h" "$f" >> "$OUT/hashes/critical-static.tsv"
  else
    printf 'MISSING\t%s\tstatic\n' "$f" >> "$OUT/hashes/critical-static.tsv"
  fi
done

printf 'sha256\tpath\tstation\tkind\n' > "$OUT/hashes/systemd-stations.tsv"
for ch in "${CHANNELS[@]}"; do
  unit="tps-${ch}-playout.service"
  frag="$(systemctl show "$unit" -p FragmentPath --value 2>/dev/null || true)"
  if [[ -n "$frag" && -f "$frag" ]]; then
    printf '%s\t%s\t%s\tunit\n' "$(sha256sum "$frag" | awk '{print $1}')" "$frag" "$ch" >> "$OUT/hashes/systemd-stations.tsv"
  else
    printf 'MISSING\t%s\t%s\tunit\n' "${frag:-UNKNOWN}" "$ch" >> "$OUT/hashes/systemd-stations.tsv"
  fi
  drops="$(systemctl show "$unit" -p DropInPaths --value 2>/dev/null || true)"
  for d in $drops; do
    [[ -f "$d" ]] || continue
    printf '%s\t%s\t%s\tdropin\n' "$(sha256sum "$d" | awk '{print $1}')" "$d" "$ch" >> "$OUT/hashes/systemd-stations.tsv"
  done
done

printf 'sha256\tpath\tstation\tkind\n' > "$OUT/hashes/playlists.tsv"
for ch in "${CHANNELS[@]}"; do
  p="$ROOT/$ch/playlists/playlist.txt"
  if [[ -f "$p" ]]; then
    printf '%s\t%s\t%s\tdynamic-playlist\n' "$(sha256sum "$p" | awk '{print $1}')" "$p" "$ch" >> "$OUT/hashes/playlists.tsv"
  else
    printf 'MISSING\t%s\t%s\tdynamic-playlist\n' "$p" "$ch" >> "$OUT/hashes/playlists.tsv"
  fi
done

printf 'station\tdomain\toverall\tsystemd\tpid\tmediamtx_ready\ttracks\trtsp_probe\thls_http\thls_manifest\thls_freshness\tportal_http\timpossible_open_30m\tno_ready_30m\tdts_30m\tready_files\tplaylist_sha256\n' > "$OUT/health.tsv"

for ch in "${CHANNELS[@]}"; do
  domain=radio; [[ "$ch" == tv* ]] && domain=tv
  unit="tps-${ch}-playout.service"
  cdir="$OUT/stations/$ch"; mkdir -p "$cdir"

  sys="$(systemctl is-active "$unit" 2>/dev/null || true)"; [[ -n "$sys" ]] || sys=unknown
  pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"; [[ -n "$pid" ]] || pid=0
  start="$(systemctl show "$unit" -p ExecMainStartTimestamp --value 2>/dev/null || true)"
  printf 'systemd=%s\npid=%s\nstarted=%s\n' "$sys" "$pid" "$start" > "$cdir/systemd.txt"

  item="$(jq -c --arg ch "$ch" '.items[]? | select(.name==$ch)' "$OUT/core/mediamtx-paths.json" | head -n1 || true)"
  if [[ -n "$item" ]]; then
    ready="$(jq -r '.ready // false' <<<"$item")"
    tracks="$(jq -r '[.tracks[]?] | join("+")' <<<"$item")"
  else
    ready=false; tracks=""
  fi
  printf '%s\n' "${item:-{}}" > "$cdir/mediamtx-path.json"

  if timeout 10 ffprobe -v error -rtsp_transport tcp \
      -show_entries stream=codec_type,codec_name,sample_rate,channels,width,height \
      -of json "rtsp://127.0.0.1:8554/$ch" > "$cdir/ffprobe-rtsp.json" 2>"$cdir/ffprobe-rtsp.err"; then
    rtsp=PASS
  else
    rtsp=FAIL
  fi

  hls_url="http://127.0.0.1:8888/$ch/index.m3u8"
  hmeta="$(curl -sS -L -o "$cdir/hls-1.body" -w '%{http_code}\t%{content_type}\t%{url_effective}' --max-time 8 "$hls_url" 2>"$cdir/hls-1.err" || true)"
  hcode="${hmeta%%$'\t'*}"; rest="${hmeta#*$'\t'}"; htype="${rest%%$'\t'*}"; heffective="${rest#*$'\t'}"
  printf 'url=%s\nhttp=%s\ncontent_type=%s\neffective=%s\n' "$hls_url" "${hcode:-000}" "$htype" "$heffective" > "$cdir/hls-meta.txt"
  hmanifest=FAIL
  hfresh=SKIP
  if [[ "$hcode" == 200 ]] && is_manifest "$cdir/hls-1.body"; then
    hmanifest=PASS
    sleep 3
    curl -fsS -L --max-time 8 "$hls_url" > "$cdir/hls-2.body" 2>/dev/null || true
    if is_manifest "$cdir/hls-2.body"; then
      seq1="$(grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' "$cdir/hls-1.body" | cut -d: -f2 || true)"
      seq2="$(grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' "$cdir/hls-2.body" | cut -d: -f2 || true)"
      last1="$(grep -Ev '^#|^[[:space:]]*$' "$cdir/hls-1.body" | tail -n1 || true)"
      last2="$(grep -Ev '^#|^[[:space:]]*$' "$cdir/hls-2.body" | tail -n1 || true)"
      if [[ "$seq1" != "$seq2" || "$last1" != "$last2" ]]; then hfresh=CHANGING; else hfresh=UNCHANGED_3S; fi
    fi
  fi

  portal="$(portal_url "$ch")"
  pcode="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 8 "$portal" 2>/dev/null || true)"
  [[ -n "$pcode" ]] || pcode=000

  journalctl -u "$unit" --since '-30 min' --no-pager -o cat > "$cdir/journal-30m.txt" 2>/dev/null || true
  impossible="$(grep -Eic 'Impossible to open' "$cdir/journal-30m.txt" || true)"
  noready="$(grep -Eic 'NO_READY_MEDIA' "$cdir/journal-30m.txt" || true)"
  dts="$(grep -Eic 'non-monotonic dts' "$cdir/journal-30m.txt" || true)"

  ready_count="$(find "$ROOT/$ch/ready" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  playlist="$ROOT/$ch/playlists/playlist.txt"
  phash=MISSING; [[ -f "$playlist" ]] && phash="$(sha256sum "$playlist" | awk '{print $1}')"

  overall=healthy
  if [[ "$sys" != active || "$ready" != true || "$rtsp" != PASS ]]; then
    overall=failed
  elif [[ "$domain" == radio ]]; then
    if [[ "$hmanifest" != PASS || "$pcode" != 200 || "$impossible" -gt 0 || "$noready" -gt 0 ]]; then overall=degraded; fi
  else
    if [[ "$hmanifest" != PASS || "$pcode" != 200 || "$dts" -gt 0 || "$noready" -gt 0 ]]; then overall=degraded; fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ch" "$domain" "$overall" "$sys" "$pid" "$ready" "$tracks" "$rtsp" "${hcode:-000}" "$hmanifest" "$hfresh" "$pcode" "$impossible" "$noready" "$dts" "$ready_count" "$phash" >> "$OUT/health.tsv"
done

common_radio_http="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 8 https://www.radio.studiosatweb.com.br/ 2>/dev/null || true)"
printf 'radio_portal_www\t%s\thttps://www.radio.studiosatweb.com.br/\n' "${common_radio_http:-000}" >> "$OUT/core/core.tsv"

cat > "$OUT/SUMMARY.txt" <<SUM
STUDIOSAT_HEALTH_BASELINE_VERSION=${VERSION}
HOST=${HOST}
UTC=${STAMP}
READ_ONLY=YES
HEALTH_TSV=${OUT}/health.tsv
CORE_TSV=${OUT}/core/core.tsv
STATIC_HASHES=${OUT}/hashes/critical-static.tsv
SYSTEMD_HASHES=${OUT}/hashes/systemd-stations.tsv
PLAYLIST_HASHES=${OUT}/hashes/playlists.tsv
SUM

tar -C "$(dirname "$OUT")" -czf "$ARCHIVE" "$(basename "$OUT")"
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"

echo
if have column; then column -t -s $'\t' "$OUT/health.tsv"; else cat "$OUT/health.tsv"; fi
echo
echo "OUTPUT_DIR=$OUT"
echo "ARCHIVE=$ARCHIVE"
echo "ARCHIVE_SHA256=${ARCHIVE}.sha256"
echo "READ_ONLY=YES"
