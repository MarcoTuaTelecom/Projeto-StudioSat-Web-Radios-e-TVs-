#!/usr/bin/env bash
# Nome: deploy-tvkids-player-v2-isolated.sh
# Versão: 1.1
# Owner: TV + Core
# Safety class: production-change (TVKIDS web only)
# Change ID: CHG-TVKIDS-WEB-003
# Propósito: publicar player TVKIDS fullscreen/resiliente e migrar ownership NGINX legado conhecido,
# preservando Rádio, TVKIDS runtime, MediaMTX e os vhosts das demais TVs.
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
LEGACY_ONLY="/etc/nginx/conf.d/zz-tvkids-isolated.conf"
LEGACY_SHARED="/etc/nginx/conf.d/tps-tv-web.conf"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TVKIDS-WEB-003-$TS"
BACKUP="/var/backups/studiosat/CHG-TVKIDS-WEB-003/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
HOSTS=(tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br)
OTHER_TV_HOSTS=(tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br)
MUTATED=0
WEBROOT_EXISTED=0
INDEX_EXISTED=0
NGINX_EXISTED=0
LEGACY_ONLY_EXISTED=0
LEGACY_SHARED_EXISTED=0

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
for c in git systemctl curl jq nginx sha256sum awk grep sed flock install cp mv rm mkdir find sort xargs diff tar date timeout ffprobe python3 rmdir readlink; do have "$c" || die "MISSING_TOOL:$c"; done
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

jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"
[[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }

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

ready="$(curl -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_MEDIAMTX_NOT_READY
probe="$(timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels -of compact=p=0:nk=0 rtsp://127.0.0.1:8554/tvkids 2>/dev/null || true)"
grep -q 'codec_name=h264' <<<"$probe" && grep -q 'width=1280' <<<"$probe" && grep -q 'height=720' <<<"$probe" || die TVKIDS_VIDEO_PROBE_FAIL
grep -q 'codec_name=aac' <<<"$probe" && grep -q 'sample_rate=48000' <<<"$probe" && grep -q 'channels=2' <<<"$probe" || die TVKIDS_AUDIO_PROBE_FAIL
code="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$OUT/tvkids.local.m3u8" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
[[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$OUT/tvkids.local.m3u8" || die TVKIDS_LOCAL_HLS_FAIL

nginx -t > "$OUT/nginx-pre.txt" 2>&1 || die NGINX_PRETEST_FAIL
nginx -T > "$OUT/nginx-T.pre.txt" 2>&1 || die NGINX_T_PRE_FAIL

# Classifica ownership atual. Somente dois legados conhecidos podem ser migrados automaticamente.
: > "$OUT/tvkids-vhost-owners.pre.txt"
for h in "${HOSTS[@]}"; do
  grep -RIl --exclude='studiosat-tvkids-player.conf' -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null || true
done | sort -u | tee "$OUT/tvkids-vhost-owners.pre.txt"

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$f" in
    "$LEGACY_ONLY"|"$LEGACY_SHARED") ;;
    *) die "UNKNOWN_EXPLICIT_TVKIDS_VHOST_CONFLICT:$f" ;;
  esac
done < "$OUT/tvkids-vhost-owners.pre.txt"

if [[ -f "$LEGACY_ONLY" ]]; then
  LEGACY_ONLY_EXISTED=1
  # Este legado só pode ser removido automaticamente se for realmente TVKIDS-only.
  if grep -Eqi 'tvteens|tvviva|tvmaisjovem|radioprincipal|radiopop|radiorock|radioclassicas|radiocountry|(^|[.])radio\.studiosatweb\.com\.br' "$LEGACY_ONLY"; then
    die LEGACY_TVKIDS_ONLY_FILE_HAS_OTHER_OWNERS
  fi
  cp -a "$LEGACY_ONLY" "$BACKUP/zz-tvkids-isolated.conf.before"
  echo "legacy_tvkids_only_sha=$(sha "$LEGACY_ONLY")"
fi

PATCHED_SHARED="$OUT/tps-tv-web.conf.patched"
if [[ -f "$LEGACY_SHARED" ]]; then
  LEGACY_SHARED_EXISTED=1
  cp -a "$LEGACY_SHARED" "$BACKUP/tps-tv-web.conf.before"
  # Jamais migrar automaticamente se o arquivo compartilhado tiver nomes de Rádio.
  if grep -Eqi 'radioprincipal|radiopop|radiorock|radioclassicas|radiocountry|(^|[.])radio\.studiosatweb\.com\.br' "$LEGACY_SHARED"; then
    die LEGACY_SHARED_TV_FILE_CONTAINS_RADIO
  fi
  python3 - "$LEGACY_SHARED" "$PATCHED_SHARED" <<'PY'
import re,sys
src,dst=sys.argv[1:3]
remove={
 'tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br',
 'tvkidsweb.studiosatweb.com.br','www.tvkidsweb.studiosatweb.com.br'
}
out=[]
for line in open(src,encoding='utf-8'):
    m=re.match(r'^(\s*server_name\s+)([^;]+)(;.*)$',line)
    if m:
        names=m.group(2).split()
        names=[n for n in names if n not in remove]
        if not names:
            raise SystemExit('server_name would become empty')
        line=m.group(1)+' '.join(names)+m.group(3)
    out.append(line)
open(dst,'w',encoding='utf-8').writelines(out)
PY
  # Depois do patch, nenhum server_name TVKIDS pode restar; as outras TVs devem continuar presentes.
  if grep -E '^[[:space:]]*server_name[[:space:]].*(tvkids|tvkidsweb)\.studiosatweb\.com\.br' "$PATCHED_SHARED" >/dev/null; then
    die LEGACY_SHARED_PATCH_LEFT_TVKIDS_OWNER
  fi
  for oh in "${OTHER_TV_HOSTS[@]}"; do
    grep -q -- "$oh" "$PATCHED_SHARED" || die "LEGACY_SHARED_PATCH_LOST_OTHER_TV:$oh"
  done
  echo "legacy_shared_pre_sha=$(sha "$LEGACY_SHARED")"
  echo "legacy_shared_candidate_sha=$(sha "$PATCHED_SHARED")"
fi

echo PRECHECK_TVKIDS_WEB=PASS

[[ -d "$WEBROOT" ]] && WEBROOT_EXISTED=1
[[ -f "$DST" ]] && { INDEX_EXISTED=1; cp -a "$DST" "$BACKUP/index.html.before"; }
[[ -f "$NGINX_DST" ]] && { NGINX_EXISTED=1; cp -a "$NGINX_DST" "$BACKUP/studiosat-tvkids-player.conf.before"; }

rollback(){
  set +e
  echo '=== ROLLBACK CHG-TVKIDS-WEB-003 ==='
  if (( NGINX_EXISTED == 1 )); then cp -a "$BACKUP/studiosat-tvkids-player.conf.before" "$NGINX_DST"; else rm -f "$NGINX_DST"; fi
  if (( LEGACY_ONLY_EXISTED == 1 )); then cp -a "$BACKUP/zz-tvkids-isolated.conf.before" "$LEGACY_ONLY"; else rm -f "$LEGACY_ONLY"; fi
  if (( LEGACY_SHARED_EXISTED == 1 )); then cp -a "$BACKUP/tps-tv-web.conf.before" "$LEGACY_SHARED"; fi
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

# Migra os owners legados conhecidos antes de instalar o owner dedicado.
if (( LEGACY_ONLY_EXISTED == 1 )); then rm -f "$LEGACY_ONLY"; fi
if (( LEGACY_SHARED_EXISTED == 1 )); then install -o root -g root -m 0644 "$PATCHED_SHARED" "$LEGACY_SHARED"; fi
install -o root -g root -m 0644 "$NGINX_SRC" "$NGINX_DST"

nginx -t | tee "$OUT/nginx-post-install.txt"
nginx -T > "$OUT/nginx-T.post-install.txt" 2>&1 || die NGINX_T_POST_INSTALL_FAIL
if grep -Eqi 'conflicting server name.*(tvkids|tvkidsweb)' "$OUT/nginx-T.post-install.txt"; then
  die DUPLICATE_TVKIDS_SERVER_NAME_AFTER_MIGRATION
fi
# Somente o owner dedicado pode conter os quatro nomes TVKIDS após a migração.
for h in "${HOSTS[@]}"; do
  mapfile -t owners < <(grep -RIl -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null | sort -u || true)
  [[ ${#owners[@]} -eq 1 && "${owners[0]}" == "$NGINX_DST" ]] || { printf '%s\n' "${owners[@]}" > "$OUT/post-owner-$h.txt"; die "TVKIDS_OWNER_NOT_UNIQUE:$h"; }
done

systemctl reload nginx
sleep 2

for h in "${HOSTS[@]}"; do
  hdr="$OUT/$h.headers"; root="$OUT/$h.root"; hls="$OUT/$h.hls"
  rc="$(curl -kLsS -D "$hdr" --connect-timeout 5 --max-time 15 -o "$root" -w '%{http_code}' "https://$h/" || true)"
  [[ "$rc" == 200 ]] || die "PUBLIC_ROOT_HTTP:$h:$rc"
  grep -qi '^X-StudioSat-TV: tvkids-player-v2' "$hdr" || die "PUBLIC_ROOT_WRONG_VHOST:$h"
  grep -q 'Studio Sat TV — Ao Vivo' "$root" || die "PUBLIC_PLAYER_V2_NOT_SERVED:$h"
  hc="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$hls" -w '%{http_code}' "https://$h/tvkids/index.m3u8" || true)"
  [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "PUBLIC_HLS_BAD:$h:$hc"
done

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

# Se havia shared TV legado, comprova que os demais hosts continuam presentes no NGINX carregado.
if (( LEGACY_SHARED_EXISTED == 1 )); then
  for oh in "${OTHER_TV_HOSTS[@]}"; do grep -q -- "$oh" "$OUT/nginx-T.post-install.txt" || die "OTHER_TV_VHOST_LOST:$oh"; done
fi

trap - EXIT
printf 'player_sha=%s\n' "$(sha "$DST")"
printf 'nginx_sha=%s\n' "$(sha "$NGINX_DST")"
echo TVKIDS_LEGACY_VHOST_MIGRATION=PASS
echo CHG_TVKIDS_WEB_003=PASS
echo TVKIDS_FULLSCREEN_PLAYER_V2=PASS
echo TVKIDS_PUBLIC_HLS=PASS
echo ALL_5_RADIOS_PRESERVED=PASS
echo TVKIDS_RUNTIME_PRESERVED=PASS
echo MEDIAMTX_PRESERVED=PASS
echo "evidence=$OUT"
