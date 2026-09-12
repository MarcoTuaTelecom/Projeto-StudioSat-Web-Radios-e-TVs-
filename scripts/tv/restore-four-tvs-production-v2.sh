#!/usr/bin/env bash
# Nome: restore-four-tvs-production-v2.sh
# Versão: 2.0
# Owner: TV + Core
# Safety class: production-change
# Change ID: CHG-TV-RESTORE-001
# Propósito: preservar as 5 rádios e restaurar TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM com gates e rollback.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CAND="$REPO/candidates/CHG-TV-RESTORE-001"
BUILDER_SRC="$CAND/tps-tv-canonical-plan-v1.sh"
NGINX_SRC="$CAND/studiosat-tv-v1.conf"
PLAYER_SRC="$CAND/tv-player-index-v1.html"
HEALTH="$REPO/scripts/ns1-health-certify-v3.sh"
NORMALIZER="$REPO/scripts/tv/tvkids-normalize-asset-v1.sh"
BUILDER="/usr/local/sbin/tps-tv-canonical-plan"
NGINX_DST="/etc/nginx/conf.d/studiosat-tv.conf"
WEBROOT="/var/www/studiosat-tv-player"
CERT="/etc/letsencrypt/live/studiosatweb-completo/fullchain.pem"
KEY="/etc/letsencrypt/live/studiosatweb-completo/privkey.pem"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
FAILED_TVS=(tvteens tvviva tvmaisjovem)
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TV-RESTORE-001-$TS"
BACKUP="/var/backups/studiosat/CHG-TV-RESTORE-001/$TS"
WORK="/srv/tpsmedia/repository/channels/tvkids/lab/chg-tv-restore-$TS"
LOCK=/run/lock/studiosat-production-change.lock
MUTATED=0; TVKIDS_SWAPPED=0; NGINX_RELOADED=0; NGINX_EXISTED=0; BUILDER_EXISTED=0; WEBROOT_EXISTED=0

die(){ echo "FATAL=$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
for c in git systemctl ffmpeg ffprobe curl jq nginx find sort sha256sum awk grep sed flock timeout nice ionice install cp mv rm mkdir tar stat readlink runuser journalctl diff free df date seq sleep basename wc xargs head cut; do have "$c" || die "MISSING_TOOL:$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
for f in "$BUILDER_SRC" "$NGINX_SRC" "$PLAYER_SRC" "$HEALTH" "$NORMALIZER" "$0"; do [[ -f "$f" ]] || die "MISSING_REPO_FILE:${f#$REPO/}"; done
bash -n "$BUILDER_SRC"; bash -n "$HEALTH"; bash -n "$NORMALIZER"; bash -n "$0"
[[ -f "$CERT" && -f "$KEY" ]] || die TLS_FILES_MISSING

mkdir -p "$OUT" "$BACKUP" "$WORK"; chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"; flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK

echo "CHG-TV-RESTORE-001 UTC=$TS"
ps -eo pid=,ppid=,etimes=,args= > "$OUT/processes.pre.txt"
if grep -E 'apply-(radio|tv)|restore-five-radios|tvkids-rebuild-production|systemctl +(restart|reload|start|stop) +(tps-|nginx)' "$OUT/processes.pre.txt" | grep -v -E 'grep -E|restore-four-tvs-production-v2' > "$OUT/concurrent.txt"; then die CONCURRENT_MUTATION_DETECTED; fi
jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"; [[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }
avail_kb="$(awk '/MemAvailable:/{print $2}' /proc/meminfo)"; (( avail_kb > 2097152 )) || die LOW_MEMORY
avail_gb="$(df -Pk /srv/tpsmedia | awk 'NR==2{print int($4/1024/1024)}')"; (( avail_gb >= 5 )) || die LOW_DISK

MTX_PID_PRE="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"; [[ "$MTX_PID_PRE" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_PID_INVALID
: > "$OUT/radio.pre.tsv"
radio_health(){
  local st="$1" u="tps-${st}-playout.service" pid pl sha1 ready probe code tmp
  [[ "$(systemctl is-active "$u" 2>/dev/null || true)" == active ]] || return 1
  pid="$(systemctl show "$u" -p MainPID --value)"; [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"; [[ -f "$pl" ]] || return 1; sha1="$(sha "$pl")"
  ready="$(curl -fsS --max-time 5 http://127.0.0.1:9997/v3/paths/list | jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' | head -1)"; [[ "$ready" == true ]] || return 1
  probe="$(timeout 12 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"
  grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || return 1
  tmp="$OUT/$st.pre.m3u8"; code="$(curl -LsS --max-time 12 -o "$tmp" -w '%{http_code}' "http://127.0.0.1:8888/$st/index.m3u8" || true)"; [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$tmp" || return 1
  printf '%s\t%s\t%s\n' "$st" "$pid" "$sha1"
}
for st in "${RADIOS[@]}"; do radio_health "$st" | tee -a "$OUT/radio.pre.tsv" || die "RADIO_PRECHECK_FAIL:$st"; done
for f in /etc/nginx/conf.d/studiosat-radio.conf /etc/nginx/conf.d/zz-studiosat-radio-portal.conf; do [[ -f "$f" ]] || die "RADIO_NGINX_MISSING:$f"; printf '%s\t%s\n' "$f" "$(sha "$f")" >> "$OUT/radio-nginx.pre.tsv"; done
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do [[ -d "$d" ]] || die "RADIO_WEBROOT_MISSING:$d"; find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$(basename "$d").pre.sha256"; done
for st in "${RADIOS[@]}"; do tmp="$OUT/portal-$st.pre.m3u8"; code="$(curl -kLsS --max-time 15 -o "$tmp" -w '%{http_code}' "https://www.radio.studiosatweb.com.br/hls/$st/index.m3u8" || true)"; [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$tmp" || die "RADIO_PORTAL_HLS_PRECHECK_FAIL:$st"; done

echo RADIO_BASELINE_PRE=PASS

profile_ok(){
  local f="$1" js="$2"
  ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,time_base,sample_rate,channels -of json "$f" > "$js" || return 1
  jq -e '([.streams[]|select(.codec_type=="video")]|length)==1 and ([.streams[]|select(.codec_type=="audio")]|length)==1 and ([.streams[]|select(.codec_type=="video")][0]|.codec_name=="h264" and .width==1280 and .height==720 and .pix_fmt=="yuv420p" and .r_frame_rate=="30/1" and .time_base=="1/90000") and ([.streams[]|select(.codec_type=="audio")][0]|.codec_name=="aac" and .sample_rate=="48000" and .channels==2 and .time_base=="1/48000")' "$js" >/dev/null
}
decode_ok(){ nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -v error -xerror -threads 1 -i "$1" -map 0:v:0 -map 0:a:0 -f null - >/dev/null 2>"$2"; }
build_list(){ local dir="$1" out="$2" repeats="${3:-1}"; printf 'ffconcat version 1.0\n' > "$out"; for _ in $(seq 1 "$repeats"); do while IFS= read -r -d '' f; do esc=${f//\'/\'\\\'\'}; printf "file '%s'\n" "$esc" >> "$out"; done < <(find "$dir" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z); done; }
temporal_ok(){ local list="$1" tag="$2" log="$OUT/$tag.stderr"; set +e; nice -n 19 ionice -c3 timeout 1200 ffmpeg -hide_banner -nostdin -loglevel warning -y -f concat -safe 0 -i "$list" -map 0:v:0 -map 0:a:0 -c copy -f flv /dev/null >/dev/null 2>"$log"; rc=$?; set -e; dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$log" || true)"; other="$(grep -Eic 'Invalid data|No start code|corrupt|Conversion failed|Could not write|Broken pipe' "$log" || true)"; echo "$tag rc=$rc dts=$dts other=$other"; [[ $rc -eq 0 && $dts -eq 0 && $other -eq 0 ]]; }

for st in "${FAILED_TVS[@]}"; do
  dir="/srv/tpsmedia/repository/channels/$st/canonical"; mapfile -d '' -t fs < <(find "$dir" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z); ((${#fs[@]} > 0)) || die "NO_CANONICAL:$st"
  i=0; for f in "${fs[@]}"; do i=$((i+1)); profile_ok "$f" "$OUT/$st-$i.json" || die "PROFILE_FAIL:$st:$(basename "$f")"; decode_ok "$f" "$OUT/$st-$i.decode" || die "DECODE_FAIL:$st:$(basename "$f")"; done
  build_list "$dir" "$OUT/$st-3x.ffconcat" 3; temporal_ok "$OUT/$st-3x.ffconcat" "$st-3x" || die "TEMPORAL_FAIL:$st"
done

KBASE=/srv/tpsmedia/repository/channels/tvkids; KCAN="$KBASE/canonical"; KPL="$KBASE/playlists/playlist.txt"; [[ -d "$KCAN" && -f "$KPL" ]] || die TVKIDS_SOURCE_MISSING
mapfile -d '' -t KFILES < <(find "$KCAN" -maxdepth 1 -type f -iname '*.mp4' -print0 | sort -z); ((${#KFILES[@]} > 0)) || die TVKIDS_CANONICAL_EMPTY
[[ "$(grep -c '^file ' "$KPL" || true)" -eq "${#KFILES[@]}" ]] || die TVKIDS_PLAYLIST_COUNT_MISMATCH
[[ "$(grep -c '/canonical/' "$KPL" || true)" -eq "${#KFILES[@]}" ]] || die TVKIDS_PLAYLIST_NOT_CANONICAL
idx=0; for f in "${KFILES[@]}"; do idx=$((idx+1)); profile_ok "$f" "$OUT/tvkids-$idx.json" || die "TVKIDS_PROFILE_FAIL:$(basename "$f")"; decode_ok "$f" "$OUT/tvkids-$idx.decode" || die "TVKIDS_DECODE_FAIL:$(basename "$f")"; done
build_list "$KCAN" "$OUT/tvkids-current-2x.ffconcat" 2
USE_CAND=0
if temporal_ok "$OUT/tvkids-current-2x.ffconcat" tvkids-current-2x; then echo TVKIDS_TEMPORAL_CURRENT=PASS; else USE_CAND=1; echo TVKIDS_TEMPORAL_CURRENT=FAIL_REPAIR_REQUIRED; fi

KNEW="$WORK/canonical-audio-rebuilt"; mkdir -p "$KNEW"
if (( USE_CAND == 1 )); then
  echo TVKIDS_REPAIR=REBUILD_AUDIO_PRESERVE_VIDEO
  idx=0; for src in "${KFILES[@]}"; do idx=$((idx+1)); dst="$KNEW/$(basename "$src")"; nice -n 19 ionice -c3 ffmpeg -hide_banner -nostdin -loglevel warning -y -i "$src" -map 0:v:0 -map 0:a:0 -c:v copy -af 'asetpts=PTS-STARTPTS,aresample=48000:async=1:first_pts=0' -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest -avoid_negative_ts make_zero -video_track_timescale 90000 -movflags +faststart "$dst" >"$OUT/audionorm-$idx.out" 2>"$OUT/audionorm-$idx.err" || die "TVKIDS_AUDIO_REBUILD_FAIL:$idx"; profile_ok "$dst" "$OUT/audionorm-$idx.json" || die "TVKIDS_AUDIO_REBUILD_PROFILE_FAIL:$idx"; decode_ok "$dst" "$OUT/audionorm-$idx.decode" || die "TVKIDS_AUDIO_REBUILD_DECODE_FAIL:$idx"; done
  build_list "$KNEW" "$OUT/tvkids-audio-rebuilt-2x.ffconcat" 2
  if ! temporal_ok "$OUT/tvkids-audio-rebuilt-2x.ffconcat" tvkids-audio-rebuilt-2x; then
    echo TVKIDS_REPAIR_AUDIO_ONLY=INSUFFICIENT_FALLBACK_FULL_NORMALIZE
    rm -rf "$KNEW"; KNEW="$WORK/canonical-full-rebuilt"; mkdir -p "$KNEW"; idx=0
    for src in "${KFILES[@]}"; do idx=$((idx+1)); dst="$KNEW/$(basename "$src")"; bash "$NORMALIZER" "$src" "$dst" >"$OUT/fullnorm-$idx.out" 2>"$OUT/fullnorm-$idx.err" || die "TVKIDS_FULL_REBUILD_FAIL:$idx"; profile_ok "$dst" "$OUT/fullnorm-$idx.json" || die "TVKIDS_FULL_REBUILD_PROFILE_FAIL:$idx"; done
    build_list "$KNEW" "$OUT/tvkids-full-rebuilt-2x.ffconcat" 2; temporal_ok "$OUT/tvkids-full-rebuilt-2x.ffconcat" tvkids-full-rebuilt-2x || die TVKIDS_REPAIR_CANNOT_REACH_ZERO_DTS
  fi
  [[ "$(find "$KNEW" -maxdepth 1 -type f -iname '*.mp4' | wc -l)" -eq "${#KFILES[@]}" ]] || die TVKIDS_REPAIRED_COUNT_MISMATCH
fi

echo TV_MEDIA_PREMUTATION_GATE=PASS
cp -a /etc/nginx/conf.d/studiosat-radio.conf "$BACKUP/"; cp -a /etc/nginx/conf.d/zz-studiosat-radio-portal.conf "$BACKUP/"
[[ -f "$NGINX_DST" ]] && { cp -a "$NGINX_DST" "$BACKUP/studiosat-tv.conf.before"; NGINX_EXISTED=1; }
[[ -f "$BUILDER" ]] && { cp -a "$BUILDER" "$BACKUP/tps-tv-canonical-plan.before"; BUILDER_EXISTED=1; }
[[ -d "$WEBROOT" ]] && { tar -C /var/www -czf "$BACKUP/studiosat-tv-player.before.tar.gz" studiosat-tv-player; WEBROOT_EXISTED=1; }
for st in "${TVS[@]}"; do pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"; [[ -f "$pl" ]] && cp -a "$pl" "$BACKUP/$st.playlist.before" || true; done
for st in "${FAILED_TVS[@]}"; do d="/etc/systemd/system/tps-${st}-playout.service.d/20-canonical-plan.conf"; [[ -f "$d" ]] && cp -a "$d" "$BACKUP/$st.20-canonical-plan.before" || true; done

rollback(){
  set +e; echo '=== ROLLBACK CHG-TV-RESTORE-001 ==='
  for st in "${FAILED_TVS[@]}"; do systemctl stop "tps-${st}-playout.service" >/dev/null 2>&1 || true; done
  systemctl stop tps-tvkids-playout.service >/dev/null 2>&1 || true
  for st in "${FAILED_TVS[@]}"; do d="/etc/systemd/system/tps-${st}-playout.service.d/20-canonical-plan.conf"; if [[ -f "$BACKUP/$st.20-canonical-plan.before" ]]; then cp -a "$BACKUP/$st.20-canonical-plan.before" "$d"; else rm -f "$d"; fi; done
  if (( BUILDER_EXISTED == 1 )); then cp -a "$BACKUP/tps-tv-canonical-plan.before" "$BUILDER"; else rm -f "$BUILDER"; fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  if (( TVKIDS_SWAPPED == 1 )); then old="$(cat "$BACKUP/tvkids-canonical-old-path" 2>/dev/null || true)"; failed="$KBASE/archive/failed-$TS-canonical"; [[ -d "$KCAN" ]] && mv "$KCAN" "$failed"; [[ -n "$old" && -d "$old" ]] && mv "$old" "$KCAN"; fi
  for st in "${TVS[@]}"; do [[ -f "$BACKUP/$st.playlist.before" ]] && cp -a "$BACKUP/$st.playlist.before" "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"; done
  if (( NGINX_EXISTED == 1 )); then cp -a "$BACKUP/studiosat-tv.conf.before" "$NGINX_DST"; else rm -f "$NGINX_DST"; fi
  if (( WEBROOT_EXISTED == 1 )); then rm -rf "$WEBROOT"; tar -C /var/www -xzf "$BACKUP/studiosat-tv-player.before.tar.gz"; else rm -rf "$WEBROOT"; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  systemctl start tps-tvkids-playout.service >/dev/null 2>&1 || true
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

MUTATED=1
install -o root -g root -m 0755 "$BUILDER_SRC" "$BUILDER"
for st in "${FAILED_TVS[@]}"; do d="/etc/systemd/system/tps-${st}-playout.service.d"; install -d -o root -g root -m 0755 "$d"; cat > "$d/20-canonical-plan.conf" <<DROP
[Service]
ExecStartPre=
ExecStartPre=/usr/local/sbin/tps-tv-canonical-plan $st
DROP
done
systemctl daemon-reload

for st in "${FAILED_TVS[@]}"; do
  runuser -u tpsmedia -- "$BUILDER" "$st" | tee "$OUT/$st-plan.txt"; grep -q '^TV_CANONICAL_PLAN_OK' "$OUT/$st-plan.txt" || die "PLAN_FAIL:$st"
  systemctl reset-failed "tps-${st}-playout.service" || true; systemctl start "tps-${st}-playout.service"
  ok=0; for _ in $(seq 1 30); do ready="$(curl -fsS --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' | head -1 || true)"; [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active && "$ready" == true ]] && { ok=1; break; }; sleep 1; done; (( ok == 1 )) || die "TV_START_FAIL:$st"
  probe="$(timeout 12 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$st" 2>/dev/null || true)"; grep -q 'codec_name=h264' <<<"$probe" && grep -q 'codec_name=aac' <<<"$probe" || die "TV_RTSP_FAIL:$st"
  tmp="$OUT/$st.local.m3u8"; code="$(curl -LsS --max-time 12 -o "$tmp" -w '%{http_code}' "http://127.0.0.1:8888/$st/index.m3u8" || true)"; [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$tmp" || die "TV_HLS_FAIL:$st"
done

if (( USE_CAND == 1 )); then
  systemctl stop tps-tvkids-playout.service
  arch="$KBASE/archive/pre-dts-repair-$TS"; mkdir -p "$arch"; old="$arch/canonical.before"; echo "$old" > "$BACKUP/tvkids-canonical-old-path"; mv "$KCAN" "$old"; TVKIDS_SWAPPED=1; mv "$KNEW" "$KCAN"; chown -R tpsmedia:tpsmedia "$KCAN"; find "$KCAN" -type d -exec chmod 0755 {} +; find "$KCAN" -type f -exec chmod 0644 {} +
  /usr/local/sbin/tps-generate-playlist tvkids | tee "$OUT/tvkids-plan.txt"
  systemctl start tps-tvkids-playout.service
  ok=0; for _ in $(seq 1 30); do ready="$(curl -fsS --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"; [[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active && "$ready" == true ]] && { ok=1; break; }; sleep 1; done; (( ok == 1 )) || die TVKIDS_RESTART_FAIL
else
  echo TVKIDS_CUTOVER=NOT_NEEDED_CURRENT_TIMELINE_ALREADY_ZERO_DTS
fi

install -d -o www-data -g www-data -m 0755 "$WEBROOT"; install -o www-data -g www-data -m 0644 "$PLAYER_SRC" "$WEBROOT/index.html"
install -o root -g root -m 0644 "$NGINX_SRC" "$NGINX_DST"
nginx -t | tee "$OUT/nginx-test.txt"
systemctl reload nginx; NGINX_RELOADED=1; sleep 2

bash "$HEALTH" | tee "$OUT/health-v3.txt"; grep -q '^NS1_HEALTH_V3=PASS$' "$OUT/health-v3.txt" || die HEALTH_V3_FAIL

start="$(systemctl show tps-tvkids-playout.service -p ExecMainStartTimestamp --value)"; journalctl -u tps-tvkids-playout.service --since "$start" --no-pager > "$OUT/tvkids.post.journal" || true
dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$OUT/tvkids.post.journal" || true)"; fatal="$(grep -Eic 'Invalid data|No start code|Impossible to open|Connection refused|Conversion failed|segfault|core dump' "$OUT/tvkids.post.journal" || true)"; echo "tvkids_post_dts=$dts fatal=$fatal"; [[ "$dts" -eq 0 && "$fatal" -eq 0 ]] || die TVKIDS_POST_JOURNAL_BAD

[[ "$(systemctl show tps-mediamtx.service -p MainPID --value)" == "$MTX_PID_PRE" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shapre; do pidnow="$(systemctl show "tps-${st}-playout.service" -p MainPID --value)"; shanow="$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")"; [[ "$pidnow" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st:$pidpre:$pidnow"; [[ "$shanow" == "$shapre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"; radio_health "$st" > "$OUT/$st.post.txt" || die "RADIO_POST_HEALTH_FAIL:$st"; done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f s; do [[ "$(sha "$f")" == "$s" ]] || die "RADIO_NGINX_CHANGED:$f"; done < "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$(basename "$d").post.sha256"; diff -u "$OUT/$(basename "$d").pre.sha256" "$OUT/$(basename "$d").post.sha256" > "$OUT/$(basename "$d").diff" || die "RADIO_WEBROOT_CHANGED:$d"; done

echo RADIO_PRESERVATION_GATE=PASS
{
 echo "mediamtx_pid=$MTX_PID_PRE"; for st in "${RADIOS[@]}" "${TVS[@]}"; do echo "$st=$(systemctl show "tps-${st}-playout.service" -p MainPID --value 2>/dev/null || true)"; done
 echo "nginx_tv_sha=$(sha "$NGINX_DST")"; echo "tv_player_sha=$(sha "$WEBROOT/index.html")"; echo "tvkids_repaired=$USE_CAND";
} | tee "$OUT/final-identities.txt"
tar -C /tmp -czf "/tmp/CHG-TV-RESTORE-001-$TS.shareable.tar.gz" "CHG-TV-RESTORE-001-$TS"; sha256sum "/tmp/CHG-TV-RESTORE-001-$TS.shareable.tar.gz" | tee "/tmp/CHG-TV-RESTORE-001-$TS.shareable.tar.gz.sha256"
trap - EXIT
echo CHG_TV_RESTORE_001=PASS
echo ALL_5_RADIOS_PRESERVED=PASS
echo ALL_4_TVS_ON_AIR=PASS
echo PUBLIC_TV_VHOSTS=PASS
echo FALSE_POSITIVE_HEALTH_V3=PASS
echo "shareable=/tmp/CHG-TV-RESTORE-001-$TS.shareable.tar.gz"
echo "sha256=/tmp/CHG-TV-RESTORE-001-$TS.shareable.tar.gz.sha256"
