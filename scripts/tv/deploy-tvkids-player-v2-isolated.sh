#!/usr/bin/env bash
# Nome: deploy-tvkids-player-v2-isolated.sh
# Versão: 1.0
# Owner: TV + Core
# Safety class: production-change (TVKIDS web only)
# Change ID: CHG-TVKIDS-WEB-003
# Propósito: publicar player TVKIDS fullscreen/resiliente e vhost dedicado sem reiniciar Rádio, TVKIDS ou MediaMTX.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
PLAYER_SRC="$REPO/candidates/CHG-TV-PLAYER-002/tv-player-index-v2.html"
NGINX_SRC="$REPO/candidates/CHG-TVKIDS-WEB-003/studiosat-tvkids-player-v2.conf"
WEBROOT="/var/www/studiosat-tv-player"
DST="$WEBROOT/index.html"
NGINX_DST="/etc/nginx/conf.d/studiosat-tvkids-player.conf"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TVKIDS-WEB-003-$TS"
BACKUP="/var/backups/studiosat/CHG-TVKIDS-WEB-003/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
HOSTS=(tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br)
MUTATED=0
WEBROOT_EXISTED=0
INDEX_EXISTED=0
NGINX_EXISTED=0

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
for c in git systemctl curl jq nginx sha256sum awk grep sed flock install cp mv rm mkdir find sort xargs diff tar date timeout ffprobe; do have "$c" || die "MISSING_TOOL:$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
[[ -f "$PLAYER_SRC" ]] || die PLAYER_SOURCE_MISSING
[[ -f "$NGINX_SRC" ]] || die NGINX_SOURCE_MISSING
[[ -f /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem && -f /etc/letsencrypt/live/studiosatweb-completo/privkey.pem ]] || die TLS_FILES_MISSING
bash -n "$0"

mkdir -p "$OUT" "$BACKUP"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK

# Never overlap another systemd mutation.
jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"
[[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }

# Baseline immutable: Radio + MediaMTX + TVKIDS runtime.
MTX_PRE="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
TVKIDS_PRE="$(systemctl show tps-tvkids-playout.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PRE" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING
[[ "$TVKIDS_PRE" =~ ^[1-9][0-9]*$ ]] || die TVKIDS_NOT_RUNNING
[[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active ]] || die TVKIDS_NOT_ACTIVE

: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  u="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$u" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE:$st"
  pid="$(systemctl show "$u" -p MainPID --value)"
  pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"
  [[ "$pid" =~ ^[1-9][0-9]*$ && -f "$pl" ]] || die "RADIO_BASELINE_INVALID:$st"
  printf '%s\t%s\t%s\n' "$st" "$pid" "$(sha "$pl")" >> "$OUT/radio.pre.tsv"
done

NG1=/etc/nginx/conf.d/studiosat-radio.conf
NG2=/etc/nginx/conf.d/zz-studiosat-radio-portal.conf
[[ -f "$NG1" && -f "$NG2" ]] || die RADIO_NGINX_MISSING
printf '%s\t%s\n%s\t%s\n' "$NG1" "$(sha "$NG1")" "$NG2" "$(sha "$NG2")" > "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  [[ -d "$d" ]] || die "RADIO_WEBROOT_MISSING:$d"
  n="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$n.pre.sha256"
done

# TVKIDS path must already be genuinely healthy locally.
ready="$(curl -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_MEDIAMTX_NOT_READY
probe="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 rtsp://127.0.0.1:8554/tvkids 2>/dev/null || true)"
grep -q 'codec_name=h264' <<<"$probe" && grep -q 'width=1280' <<<"$probe" && grep -q 'height=720' <<<"$probe" || die TVKIDS_VIDEO_PROBE_FAIL
grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || die TVKIDS_AUDIO_PROBE_FAIL
code="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$OUT/tvkids.local.m3u8" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
[[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$OUT/tvkids.local.m3u8" || die TVKIDS_LOCAL_HLS_FAIL

# Existing explicit ownership of TVKIDS names outside our target would be unsafe.
nginx -t > "$OUT/nginx-pre.txt" 2>&1 || die NGINX_PRETEST_FAIL
for h in "${HOSTS[@]}"; do
  matches="$(grep -RIl --exclude='studiosat-tvkids-player.conf' -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null || true)"
  [[ -z "$matches" ]] || { printf '%s\n' "$matches" > "$OUT/conflict-$h.txt"; die "EXPLICIT_TVKIDS_VHOST_CONFLICT:$h"; }
done

echo PRECHECK_TVKIDS_WEB=PASS

[[ -d "$WEBROOT" ]] && WEBROOT_EXISTED=1
[[ -f "$DST" ]] && { INDEX_EXISTED=1; cp -a "$DST" "$BACKUP/index.html.before"; }
[[ -f "$NGINX_DST" ]] && { NGINX_EXISTED=1; cp -a "$NGINX_DST" "$BACKUP/studiosat-tvkids-player.conf.before"; }

rollback(){
  set +e
  echo '=== ROLLBACK CHG-TVKIDS-WEB-003 ==='
  if (( NGINX_EXISTED == 1 )); then cp -a "$BACKUP/studiosat-tvkids-player.conf.before" "$NGINX_DST"; else rm -f "$NGINX_DST"; fi
  if (( INDEX_EXISTED == 1 )); then cp -a "$BACKUP/index.html.before" "$DST"; else rm -f "$DST"; fi
  if (( WEBROOT_EXISTED == 0 )); then rmdir "$WEBROOT" 2>/dev/null || true; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

MUTATED=1
install -d -o www-data -g www-data -m 0755 "$WEBROOT"
install -o www-data -g www-data -m 0644 "$PLAYER_SRC" "$DST.new-$TS"
mv -f "$DST.new-$TS" "$DST"
install -o root -g root -m 0644 "$NGINX_SRC" "$NGINX_DST"
nginx -t | tee "$OUT/nginx-post-install.txt"
systemctl reload nginx
sleep 2

# Verify every TVKIDS alias owns the new page and real HLS.
for h in "${HOSTS[@]}"; do
  hdr="$OUT/$h.headers"; root="$OUT/$h.root"; hls="$OUT/$h.hls"
  rc="$(curl -kLsS -D "$hdr" --connect-timeout 5 --max-time 15 -o "$root" -w '%{http_code}' "https://$h/" || true)"
  [[ "$rc" == 200 ]] || die "PUBLIC_ROOT_HTTP:$h:$rc"
  grep -qi '^X-StudioSat-TV: tvkids-player-v2' "$hdr" || die "PUBLIC_ROOT_WRONG_VHOST:$h"
  grep -q 'Studio Sat TV — Ao Vivo' "$root" || die "PUBLIC_PLAYER_V2_NOT_SERVED:$h"
  hc="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$hls" -w '%{http_code}' "https://$h/tvkids/index.m3u8" || true)"
  [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "PUBLIC_HLS_BAD:$h:$hc"
done

# Runtime invariants: no restart of TVKIDS/MediaMTX/radio, no Radio file drift.
[[ "$(systemctl show tps-mediamtx.service -p MainPID --value)" == "$MTX_PRE" ]] || die MEDIAMTX_PID_CHANGED
[[ "$(systemctl show tps-tvkids-playout.service -p MainPID --value)" == "$TVKIDS_PRE" ]] || die TVKIDS_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  [[ "$(systemctl show "tps-${st}-playout.service" -p MainPID --value)" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f spre; do [[ "$(sha "$f")" == "$spre" ]] || die "RADIO_NGINX_CHANGED:$f"; done < "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  n="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$n.post.sha256"
  diff -u "$OUT/$n.pre.sha256" "$OUT/$n.post.sha256" > "$OUT/$n.diff" || die "RADIO_WEBROOT_CHANGED:$d"
done

trap - EXIT
printf 'player_sha=%s\n' "$(sha "$DST")"
printf 'nginx_sha=%s\n' "$(sha "$NGINX_DST")"
echo CHG_TVKIDS_WEB_003=PASS
echo TVKIDS_FULLSCREEN_PLAYER_V2=PASS
echo TVKIDS_PUBLIC_HLS=PASS
echo ALL_5_RADIOS_PRESERVED=PASS
echo TVKIDS_RUNTIME_PRESERVED=PASS
echo MEDIAMTX_PRESERVED=PASS
echo "evidence=$OUT"
