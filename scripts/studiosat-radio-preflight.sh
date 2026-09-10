#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="/tmp/studiosat-radio-preflight-${STAMP}"
ARCHIVE="${OUT}.tar.gz"
mkdir -p "$OUT" "$OUT/systemd" "$OUT/nginx" "$OUT/media" "$OUT/mediamtx"

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
REPO="/srv/tpsmedia/repository/channels"

log(){ printf '[%s] %s\n' "$(date -Is)" "$*" >&2; }
has(){ command -v "$1" >/dev/null 2>&1; }
redact(){
  sed -E \
    -e 's/((pass(word)?|secret|token|api[_-]?key|stream[_-]?key|authorization)[[:space:]]*[:=][[:space:]]*)[^[:space:]\";]+/\1<REDACTED>/Ig' \
    -e 's#(rtmps?://[^:/[:space:]]+:)[^@/[:space:]]+@#\1<REDACTED>@#g'
}
run(){
  local title="$1"; shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@" 2>&1 || true
  } >> "$OUT/report.txt"
}

cat > "$OUT/README.txt" <<TXT
StudioSat Radio Preflight - READ ONLY
Generated: $(date -Is)
Purpose: collect only facts relevant to Radio Studio Sat radio channels.
No install/restart/stop/reload/delete/write to production configuration is performed.
TXT

log "Collecting system baseline"
run "DATE" date -Is
run "HOSTNAME" hostnamectl
run "OS" bash -lc 'cat /etc/os-release 2>/dev/null || true'
run "KERNEL" uname -a
run "CPU" bash -lc 'nproc; lscpu 2>/dev/null | sed -n "1,40p"'
run "MEMORY" free -h
run "DISK" df -hT
run "LOAD" uptime

{
  echo "===== BINARIES ====="
  for b in ffmpeg ffprobe liquidsoap mediamtx nginx docker podman icecast2; do
    if has "$b"; then
      printf '%-14s %s\n' "$b" "$(command -v "$b")"
      case "$b" in
        ffmpeg|ffprobe) "$b" -version 2>/dev/null | head -n 2 || true ;;
        liquidsoap) "$b" --version 2>/dev/null | head -n 3 || true ;;
        nginx) "$b" -v 2>&1 || true ;;
        docker|podman) "$b" --version 2>&1 || true ;;
        *) "$b" --version 2>&1 | head -n 3 || true ;;
      esac
    else
      printf '%-14s ABSENT\n' "$b"
    fi
  done
} > "$OUT/binaries.txt"

log "Collecting listeners and processes"
(ss -lntup 2>/dev/null || true) > "$OUT/ports.txt"
(ps -eo pid,ppid,user,pcpu,pmem,etimes,args --sort=-pcpu 2>/dev/null || true) | grep -E 'PID|ffmpeg|liquidsoap|mediamtx|nginx|radioprincipal|radiopop|radiorock|radioclassicas|radiocountry' > "$OUT/processes-radio.txt" || true

log "Collecting systemd facts for radio channels"
for ch in "${RADIOS[@]}"; do
  unit="tps-${ch}-playout.service"
  {
    echo "UNIT=$unit"
    systemctl show "$unit" -p Id -p LoadState -p ActiveState -p SubState -p MainPID -p User -p Group -p ExecStart -p ExecStartPre -p WorkingDirectory -p Restart -p RestartUSec -p CPUQuotaPerSecUSec -p MemoryMax -p FragmentPath -p DropInPaths 2>&1 || true
    echo
    systemctl cat "$unit" 2>&1 || true
  } | redact > "$OUT/systemd/${unit}.txt"
  journalctl -u "$unit" -n 120 --no-pager 2>&1 | redact > "$OUT/systemd/${unit}.journal.txt" || true
done

log "Collecting NGINX radio-domain mapping"
if has nginx; then
  nginx -T 2>&1 | redact > "$OUT/nginx/nginx-T-redacted.txt" || true
  grep -Ein -C 4 'radio\.studiosatweb\.com\.br|www\.radio\.studiosatweb\.com\.br|radioprincipal|radiopop|radiorock|radioclassicas|radiocountry|8888|1935' "$OUT/nginx/nginx-T-redacted.txt" > "$OUT/nginx/radio-matches.txt" || true
fi

log "Collecting MediaMTX facts"
if systemctl list-unit-files 2>/dev/null | grep -q '^mediamtx\.service'; then
  systemctl show mediamtx.service -p ActiveState -p SubState -p MainPID -p ExecStart -p User -p Group > "$OUT/mediamtx/service.txt" 2>&1 || true
  systemctl cat mediamtx.service 2>&1 | redact > "$OUT/mediamtx/unit-redacted.txt" || true
fi

if has curl; then
  curl -fsS --max-time 3 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | redact > "$OUT/mediamtx/paths-api.json" || true
fi

for cfg in /etc/mediamtx.yml /etc/mediamtx/mediamtx.yml /usr/local/etc/mediamtx.yml /opt/mediamtx/mediamtx.yml; do
  if [[ -r "$cfg" ]]; then
    redact < "$cfg" > "$OUT/mediamtx/$(basename "$cfg").redacted"
  fi
done

log "Collecting radio repository and media profiles"
for ch in "${RADIOS[@]}"; do
  base="$REPO/$ch"
  ready="$base/ready"
  pl="$base/playlists/playlist.txt"
  out="$OUT/media/${ch}.txt"
  {
    echo "CHANNEL=$ch"
    echo "BASE=$base"
    if [[ -d "$base" ]]; then
      du -sh "$base" 2>/dev/null || true
      find "$base" -maxdepth 2 -type d -printf 'DIR %p\n' 2>/dev/null | sort || true
    else
      echo "BASE_MISSING"
    fi
    if [[ -d "$ready" ]]; then
      echo "READY_COUNT=$(find "$ready" -maxdepth 1 -type f 2>/dev/null | wc -l)"
      find "$ready" -maxdepth 1 -type f -printf '%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\n' 2>/dev/null | sort -nr | head -n 100 || true
    else
      echo "READY_MISSING"
    fi
    if [[ -r "$pl" ]]; then
      echo "PLAYLIST=$pl"
      echo "PLAYLIST_LINES=$(grep -c '^file ' "$pl" 2>/dev/null || true)"
      sed -n '1,40p' "$pl" || true
    fi
  } > "$out"

  if has ffprobe && [[ -d "$ready" ]]; then
    : > "$OUT/media/${ch}-ffprobe.tsv"
    printf 'channel\tfile\tformat\tduration\tvcodec\twidth\theight\tfps\tpix_fmt\tattached_pic\tacodec\tsample_rate\tchannels\tchannel_layout\n' >> "$OUT/media/${ch}-ffprobe.tsv"
    mapfile -d '' files < <(find "$ready" -maxdepth 1 -type f -print0 2>/dev/null | sort -z | head -z -n 20)
    for f in "${files[@]:-}"; do
      [[ -n "$f" ]] || continue
      fmt=$(ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)
      dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f" 2>/dev/null | head -n1 || true)
      v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt:stream_disposition=attached_pic -of csv=p=0 "$f" 2>/dev/null | head -n1 || true)
      a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,channel_layout -of csv=p=0 "$f" 2>/dev/null | head -n1 || true)
      IFS=',' read -r vc vw vh vfps vpix vatt <<< "$v"
      IFS=',' read -r ac asr ach acl <<< "$a"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$f" "$fmt" "$dur" "$vc" "$vw" "$vh" "$vfps" "$vpix" "$vatt" "$ac" "$asr" "$ach" "$acl" >> "$OUT/media/${ch}-ffprobe.tsv"
    done
  fi
done

log "Probing current local RTMP/HLS paths without publishing"
{
  printf 'channel\trtmp_probe\thls_probe\n'
  for ch in "${RADIOS[@]}"; do
    rtmp="FAIL"; hls="FAIL"
    if has ffprobe && timeout 5 ffprobe -v error -show_entries stream=codec_type,codec_name -of compact=p=0:nk=1 "rtmp://127.0.0.1:1935/${ch}" >/dev/null 2>&1; then rtmp="OK"; fi
    if has curl && curl -fsS --max-time 5 "http://127.0.0.1:8888/${ch}/index.m3u8" >/dev/null 2>&1; then hls="OK"; fi
    printf '%s\t%s\t%s\n' "$ch" "$rtmp" "$hls"
  done
} > "$OUT/endpoints.tsv"

log "Collecting TPS radio scripts (metadata + redacted relevant text)"
for f in /usr/local/sbin/tps-playout-radio /usr/local/sbin/tps-generate-playlist /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed; do
  if [[ -r "$f" ]]; then
    {
      ls -l "$f"
      sha256sum "$f"
      echo
      redact < "$f"
    } > "$OUT/$(basename "$f").redacted.txt"
  fi
done

cat > "$OUT/SUMMARY.txt" <<TXT
STUDIOSAT RADIO PREFLIGHT
Generated: $(date -Is)
Channels: ${RADIOS[*]}

Primary questions this package answers:
1. Which NGINX routes serve www.radio.studiosatweb.com.br and radio.studiosatweb.com.br?
2. What each tps-<radio>-playout unit executes today.
3. What each radio publishes locally and whether HLS is reachable.
4. Which media profiles exist in each ready/ directory.
5. Which MediaMTX paths/ports are active.
6. Whether Liquidsoap/Docker/Icecast are already present.

This collector is read-only. Review redacted outputs before sharing externally.
TXT

tar -C "$(dirname "$OUT")" -czf "$ARCHIVE" "$(basename "$OUT")"
chmod 600 "$ARCHIVE"

log "Completed"
printf '%s\n' "$ARCHIVE"
