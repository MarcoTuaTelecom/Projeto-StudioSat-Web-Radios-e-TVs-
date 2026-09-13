#!/usr/bin/env bash
# Nome: studiosat-tv-canonical-runtime-migrate-v1.sh
# Versão: 1.0
# Owner: TV + Core
# Safety class: production-change (TV runtime only; no NGINX/MediaMTX restart)
# Change ID: CHG-TV-CANON-002
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CAND="$REPO/candidates/CHG-TV-CANON-001"
PLAN_SRC="$CAND/tps-tv-plan-v1.sh"
PLAYOUT_SRC="$CAND/tps-tv-playout-v1.sh"
PLAN_DST="/usr/local/sbin/tps-tv-plan-v1"
PLAYOUT_DST="/usr/local/sbin/tps-tv-playout-v1"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TV-CANON-002-$TS"
BACKUP="/var/backups/studiosat/CHG-TV-CANON-002/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
MUTATED=0
PLAN_EXISTED=0
PLAYOUT_EXISTED=0

die(){ echo "FATAL=$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }

for c in git systemctl ffmpeg ffprobe curl jq sha256sum awk grep flock install cp mv rm mkdir find sort xargs diff tar date timeout nice ionice runuser journalctl basename sleep seq; do
  have "$c" || die "MISSING_TOOL:$c"
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT

cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
[[ -f "$PLAN_SRC" && -f "$PLAYOUT_SRC" ]] || die CANDIDATE_HELPERS_MISSING
bash -n "$PLAN_SRC"
bash -n "$PLAYOUT_SRC"
bash -n "$0"

mkdir -p "$OUT" "$BACKUP/systemd" "$BACKUP/playlists"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK
jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"
[[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }

MTX_PRE="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PRE" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING
: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  unit="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE:$st"
  pid="$(systemctl show "$unit" -p MainPID --value)"
  pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"
  [[ "$pid" =~ ^[1-9][0-9]*$ && -f "$pl" ]] || die "RADIO_BASELINE_INVALID:$st"
  printf '%s\t%s\t%s\n' "$st" "$pid" "$(sha "$pl")" >> "$OUT/radio.pre.tsv"
done
echo RADIO_BASELINE_PRE=PASS

: > "$OUT/tv.pre.tsv"
for st in "${TVS[@]}"; do
  unit="tps-${st}-playout.service"
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  [[ -n "$active" ]] || active=unknown
  [[ -n "$pid" ]] || pid=0
  printf '%s\t%s\t%s\n' "$st" "$active" "$pid" >> "$OUT/tv.pre.tsv"
  d="/etc/systemd/system/tps-${st}-playout.service.d"
  if [[ -d "$d" ]]; then
    tar -C /etc/systemd/system -czf "$BACKUP/systemd/$st.dropins.tar.gz" "tps-${st}-playout.service.d"
  else
    : > "$BACKUP/systemd/$st.no-dropins"
  fi
  pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"
  [[ -f "$pl" ]] && cp -a "$pl" "$BACKUP/playlists/$st.playlist.txt" || : > "$BACKUP/playlists/$st.no-playlist"
done
[[ -f "$PLAN_DST" ]] && { PLAN_EXISTED=1; cp -a "$PLAN_DST" "$BACKUP/tps-tv-plan-v1.before"; }
[[ -f "$PLAYOUT_DST" ]] && { PLAYOUT_EXISTED=1; cp -a "$PLAYOUT_DST" "$BACKUP/tps-tv-playout-v1.before"; }

profile_ok(){
  local f="$1" js="$2"
  ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,time_base,sample_rate,channels -of json "$f" > "$js" || return 1
  jq -e '([.streams[]|select(.codec_type=="video")]|length)==1 and ([.streams[]|select(.codec_type=="audio")]|length)==1 and ([.streams[]|select(.codec_type=="video")][0]|.codec_name=="h264" and .width==1280 and .height==720 and .pix_fmt=="yuv420p" and .r_frame_rate=="30/1") and ([.streams[]|select(.codec_type=="audio")][0]|.codec_name=="aac" and .sample_rate=="48000" and .channels==2)' "$js" >/dev/null
}
decode_ok(){
  nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -v error -xerror -threads 1 -i "$1" -map 0:v:0 -map 0:a:0 -f null - >/dev/null 2>"$2"
}
build_3x(){
  local dir="$1" out="$2" n
  printf 'ffconcat version 1.0\n' > "$out"
  for n in 1 2 3; do
    while IFS= read -r -d '' f; do
      esc=${f//\'/\'\\\'\'}
      printf "file '%s'\n" "$esc" >> "$out"
    done < <(find "$dir" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
  done
}
canonical_playout_test(){
  local list="$1" tag="$2" log="$OUT/$tag.stderr" rc dts fatal
  set +e
  nice -n 19 ionice -c3 timeout 1800 ffmpeg -hide_banner -nostdin -loglevel warning -y \
    -f concat -safe 0 -i "$list" \
    -map 0:v:0 -map 0:a:0 \
    -c:v copy \
    -af "aresample=48000:async=1,asetpts=N/SR/TB" \
    -c:a aac -b:a 192k -ar 48000 -ac 2 \
    -f flv /dev/null >/dev/null 2>"$log"
  rc=$?
  set -e
  dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$log" || true)"
  fatal="$(grep -Eic 'Invalid data|No start code|corrupt|Conversion failed|Could not write|Error while|segfault|core dump' "$log" || true)"
  printf '%s\trc=%s\tdts=%s\tfatal=%s\n' "$tag" "$rc" "$dts" "$fatal" | tee -a "$OUT/temporal.tsv"
  [[ $rc -eq 0 && $dts -eq 0 && $fatal -eq 0 ]]
}

: > "$OUT/temporal.tsv"
for st in "${TVS[@]}"; do
  can="/srv/tpsmedia/repository/channels/$st/canonical"
  [[ -d "$can" ]] || die "CANONICAL_DIR_MISSING:$st"
  mapfile -d '' -t files < <(find "$can" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z)
  ((${#files[@]} > 0)) || die "CANONICAL_EMPTY:$st"
  i=0
  for f in "${files[@]}"; do
    i=$((i+1))
    profile_ok "$f" "$OUT/$st-$i.probe.json" || die "PROFILE_FAIL:$st:$(basename "$f")"
    decode_ok "$f" "$OUT/$st-$i.decode.log" || die "DECODE_FAIL:$st:$(basename "$f")"
  done
  build_3x "$can" "$OUT/$st-3x.ffconcat"
  canonical_playout_test "$OUT/$st-3x.ffconcat" "$st-3x-canonical-playout" || die "CANONICAL_PLAYOUT_TEMPORAL_FAIL:$st"
done
echo TV_RUNTIME_PREMUTATION_GATE=PASS

rollback(){
  set +e
  echo '=== ROLLBACK CHG-TV-CANON-002 ==='
  for st in "${TVS[@]}"; do systemctl stop "tps-${st}-playout.service" >/dev/null 2>&1 || true; done
  for st in "${TVS[@]}"; do
    d="/etc/systemd/system/tps-${st}-playout.service.d"
    rm -rf "$d"
    if [[ -f "$BACKUP/systemd/$st.dropins.tar.gz" ]]; then tar -C /etc/systemd/system -xzf "$BACKUP/systemd/$st.dropins.tar.gz"; fi
    pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"
    if [[ -f "$BACKUP/playlists/$st.playlist.txt" ]]; then
      install -d -o tpsmedia -g tpsmedia -m 0755 "$(dirname "$pl")"
      cp -a "$BACKUP/playlists/$st.playlist.txt" "$pl"
    else
      rm -f "$pl"
    fi
  done
  if (( PLAN_EXISTED == 1 )); then cp -a "$BACKUP/tps-tv-plan-v1.before" "$PLAN_DST"; else rm -f "$PLAN_DST"; fi
  if (( PLAYOUT_EXISTED == 1 )); then cp -a "$BACKUP/tps-tv-playout-v1.before" "$PLAYOUT_DST"; else rm -f "$PLAYOUT_DST"; fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  while IFS=$'\t' read -r st active pid; do
    if [[ "$active" == active ]]; then systemctl start "tps-${st}-playout.service" >/dev/null 2>&1 || true; fi
  done < "$OUT/tv.pre.tsv"
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

MUTATED=1
install -o root -g root -m 0755 "$PLAN_SRC" "$PLAN_DST"
install -o root -g root -m 0755 "$PLAYOUT_SRC" "$PLAYOUT_DST"
for st in "${TVS[@]}"; do
  d="/etc/systemd/system/tps-${st}-playout.service.d"
  rm -rf "$d"
  install -d -o root -g root -m 0755 "$d"
  cat > "$d/90-studiosat-tv-canonical.conf" <<DROP
[Service]
ExecStartPre=
ExecStartPre=$PLAN_DST $st
ExecStart=
ExecStart=$PLAYOUT_DST $st
Restart=always
RestartSec=2
DROP
done
systemctl daemon-reload

for st in "${TVS[@]}"; do
  runuser -u tpsmedia -- "$PLAN_DST" "$st" | tee "$OUT/$st-plan.txt"
  grep -q '^TV_PLAN_V1=PASS' "$OUT/$st-plan.txt" || die "PLAN_BUILD_FAIL:$st"
  systemctl reset-failed "tps-${st}-playout.service" || true
  if [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active ]]; then systemctl restart "tps-${st}-playout.service"; else systemctl start "tps-${st}-playout.service"; fi
  ok=0
  for _ in $(seq 1 45); do
    ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' | head -1 || true)"
    if [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active && "$ready" == true ]]; then ok=1; break; fi
    sleep 1
  done
  (( ok == 1 )) || die "TV_START_OR_MEDIAMTX_FAIL:$st"
  probe="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"
  grep -q 'codec_type=video' <<<"$probe" && grep -q 'codec_name=h264' <<<"$probe" && grep -q 'width=1280' <<<"$probe" && grep -q 'height=720' <<<"$probe" || die "TV_VIDEO_FAIL:$st"
  grep -q 'codec_type=audio' <<<"$probe" && grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || die "TV_AUDIO_FAIL:$st"
  hls="$OUT/$st.local.m3u8"
  hc="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$hls" -w '%{http_code}' "http://127.0.0.1:8888/$st/index.m3u8" || true)"
  [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "TV_HLS_FAIL:$st:$hc"
done

sleep 8
for st in "${TVS[@]}"; do
  start="$(systemctl show "tps-${st}-playout.service" -p ExecMainStartTimestamp --value)"
  journal="$OUT/$st.post.journal"
  journalctl -u "tps-${st}-playout.service" --since "$start" --no-pager > "$journal" || true
  dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$journal" || true)"
  fatal="$(grep -Eic 'Invalid data|No start code|Impossible to open|Connection refused|Conversion failed|segfault|core dump' "$journal" || true)"
  printf '%s\tdts=%s\tfatal=%s\n' "$st" "$dts" "$fatal" | tee -a "$OUT/journal-gate.tsv"
  [[ "$dts" -eq 0 && "$fatal" -eq 0 ]] || die "TV_POST_JOURNAL_BAD:$st"
done

[[ "$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)" == "$MTX_PRE" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  [[ "$(systemctl show "tps-${st}-playout.service" -p MainPID --value)" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"

trap - EXIT
echo CHG_TV_CANON_002_RUNTIME=PASS
echo ALL_4_TVS_RUNTIME_READY=PASS
echo ZERO_DTS_CANONICAL_PLAYOUT=PASS
echo ALL_5_RADIOS_PRESERVED=PASS
echo MEDIAMTX_PRESERVED=PASS
echo "evidence=$OUT"
