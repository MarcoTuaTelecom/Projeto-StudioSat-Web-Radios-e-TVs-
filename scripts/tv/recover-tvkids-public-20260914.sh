#!/usr/bin/env bash
# Nome: recover-tvkids-public-20260914.sh
# Versão: 1.0
# Escopo: somente TVKIDS + vhost TVKIDS. Rádio é somente observado e deve permanecer bit-a-bit/PID estável.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CAND="$REPO/candidates/CHG-TVKIDS-RECOVER-20260914"
CONF_SRC="$CAND/studiosat-tvkids-live.conf"
PLAYER_SRC="$REPO/candidates/CHG-TV-CANON-001/index.html"
CONF_DST="/etc/nginx/conf.d/90-studiosat-tvkids-live.conf"
WEBROOT="/var/www/studiosat-tv/current"
INDEX="$WEBROOT/index.html"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/TVKIDS-RECOVER-$TS"
BACKUP="/var/backups/studiosat/TVKIDS-RECOVER/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVHOSTS=(tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br)
MUTATED=0
INDEX_EXISTED=0
CONF_EXISTED=0
TVKIDS_WAS_ACTIVE=0
TVKIDS_STARTED_BY_CHANGE=0

die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
have(){ command -v "$1" >/dev/null 2>&1; }

for c in git systemctl curl jq nginx sha256sum awk grep flock install cp mv rm mkdir find sort xargs diff tar date sleep; do
  have "$c" || die "MISSING_TOOL:$c"
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
[[ -f "$CONF_SRC" && -f "$PLAYER_SRC" ]] || die CANDIDATE_MISSING
[[ -f /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem && -f /etc/letsencrypt/live/studiosatweb-completo/privkey.pem ]] || die TLS_FILES_MISSING

mkdir -p "$OUT" "$BACKUP"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK

# ===== RADIO: SOMENTE PROVA DE IMUTABILIDADE; NENHUMA AÇÃO =====
: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  unit="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE_PRE:$st"
  pid="$(systemctl show "$unit" -p MainPID --value)"
  pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"
  [[ "$pid" =~ ^[1-9][0-9]*$ && -f "$pl" ]] || die "RADIO_BASELINE_INVALID:$st"
  printf '%s\t%s\t%s\n' "$st" "$pid" "$(sha "$pl")" >> "$OUT/radio.pre.tsv"
done
NG1=/etc/nginx/conf.d/studiosat-radio.conf
NG2=/etc/nginx/conf.d/zz-studiosat-radio-portal.conf
[[ -f "$NG1" && -f "$NG2" ]] || die RADIO_NGINX_BASELINE_MISSING
printf '%s\t%s\n%s\t%s\n' "$NG1" "$(sha "$NG1")" "$NG2" "$(sha "$NG2")" > "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  [[ -d "$d" ]] || die "RADIO_WEBROOT_MISSING:$d"
  key="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$key.pre.sha256"
done
echo RADIO_BASELINE_READONLY=PASS

# MediaMTX é compartilhado: deve já estar ativo e NÃO será reiniciado.
MTX_PID="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PID" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING

# TVKIDS: não reinicia se já estiver ativa. Se estiver parada, somente TVKIDS é iniciada.
if [[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active ]]; then
  TVKIDS_WAS_ACTIVE=1
  TVKIDS_PID_PRE="$(systemctl show tps-tvkids-playout.service -p MainPID --value)"
  echo "TVKIDS_RUNTIME=ALREADY_ACTIVE pid=$TVKIDS_PID_PRE"
else
  echo TVKIDS_RUNTIME=STARTING_TVKIDS_ONLY
  systemctl reset-failed tps-tvkids-playout.service || true
  systemctl start tps-tvkids-playout.service
  TVKIDS_STARTED_BY_CHANGE=1
  sleep 3
fi
[[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active ]] || die TVKIDS_SERVICE_NOT_ACTIVE

ready=false
for _ in $(seq 1 20); do
  ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
  [[ "$ready" == true ]] && break
  sleep 1
done
[[ "$ready" == true ]] || die TVKIDS_MEDIAMTX_NOT_READY
local_hls="$OUT/tvkids.local.m3u8"
hc="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$local_hls" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
[[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$local_hls" || die TVKIDS_LOCAL_HLS_FAIL
echo TVKIDS_INTERNAL_STREAM=PASS

# NGINX atual deve estar saudável antes da mudança.
nginx -t > "$OUT/nginx.pre.txt" 2>&1 || die NGINX_PRETEST_FAIL

# Não sobrepõe ownership TVKIDS desconhecido. O único arquivo permitido é o nosso próprio destino.
conflicts=""
for h in "${TVHOSTS[@]}"; do
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$f" == "$CONF_DST" ]] && continue
    conflicts+="$f\n"
  done < <(grep -RIl --include='*.conf' -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null || true)
done
if [[ -n "$conflicts" ]]; then
  printf '%b' "$conflicts" | sort -u > "$OUT/tvkids-vhost-conflicts.txt"
  die TVKIDS_VHOST_CONFLICT_FOUND
fi

[[ -f "$INDEX" ]] && { INDEX_EXISTED=1; cp -a "$INDEX" "$BACKUP/index.html.before"; }
[[ -f "$CONF_DST" ]] && { CONF_EXISTED=1; cp -a "$CONF_DST" "$BACKUP/90-studiosat-tvkids-live.conf.before"; }

rollback(){
  set +e
  echo '=== ROLLBACK TVKIDS RECOVERY ==='
  if (( CONF_EXISTED == 1 )); then cp -a "$BACKUP/90-studiosat-tvkids-live.conf.before" "$CONF_DST"; else rm -f "$CONF_DST"; fi
  if (( INDEX_EXISTED == 1 )); then cp -a "$BACKUP/index.html.before" "$INDEX"; else rm -f "$INDEX"; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  if (( TVKIDS_STARTED_BY_CHANGE == 1 && TVKIDS_WAS_ACTIVE == 0 )); then systemctl stop tps-tvkids-playout.service >/dev/null 2>&1 || true; fi
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

# ===== MUTA SOMENTE WEBROOT/VHOST TVKIDS =====
MUTATED=1
install -d -o www-data -g www-data -m 0755 "$WEBROOT"
install -o www-data -g www-data -m 0644 "$PLAYER_SRC" "$INDEX.new-$TS"
mv -f "$INDEX.new-$TS" "$INDEX"
install -o root -g root -m 0644 "$CONF_SRC" "$CONF_DST"

nginx -t | tee "$OUT/nginx.post.txt"
# Reload gracioso do NGINX; não reinicia FFmpeg, Rádio ou MediaMTX.
systemctl reload nginx
sleep 2

# Prova local por SNI: HTML TVKIDS e HLS real.
for h in "${TVHOSTS[@]}"; do
  hdr="$OUT/$h.headers"; body="$OUT/$h.root"; hls="$OUT/$h.m3u8"
  code="$(curl -kLsS --resolve "$h:443:127.0.0.1" -D "$hdr" --connect-timeout 4 --max-time 12 -o "$body" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 200 ]] || die "TVKIDS_ROOT_HTTP_FAIL:$h:$code"
  grep -qi '^X-StudioSat-TV-Owner: tvkids-recovery-v1' "$hdr" || die "TVKIDS_WRONG_VHOST:$h"
  grep -q 'Studio Sat TV — Ao Vivo' "$body" || die "TVKIDS_PLAYER_BODY_FAIL:$h"
  hcode="$(curl -kLsS --resolve "$h:443:127.0.0.1" --connect-timeout 4 --max-time 15 -o "$hls" -w '%{http_code}' "https://$h/tvkids/index.m3u8" || true)"
  [[ "$hcode" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "TVKIDS_PUBLIC_HLS_FAIL:$h:$hcode"
done

# ===== RADIO: PROVA PÓS-MUDANÇA; CONTINUA SEM AÇÃO =====
[[ "$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)" == "$MTX_PID" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE_POST:$st"
  [[ "$(systemctl show "tps-${st}-playout.service" -p MainPID --value)" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f shpre; do
  [[ "$(sha "$f")" == "$shpre" ]] || die "RADIO_NGINX_CHANGED:$f"
done < "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  key="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$key.post.sha256"
  diff -u "$OUT/$key.pre.sha256" "$OUT/$key.post.sha256" > "$OUT/$key.diff" || die "RADIO_WEBROOT_CHANGED:$d"
done
if (( TVKIDS_WAS_ACTIVE == 1 )); then
  [[ "$(systemctl show tps-tvkids-playout.service -p MainPID --value)" == "$TVKIDS_PID_PRE" ]] || die TVKIDS_PID_CHANGED_UNEXPECTEDLY
fi

trap - EXIT
echo TVKIDS_RECOVERY=PASS
echo TVKIDS_INTERNAL_STREAM=PASS
echo TVKIDS_PUBLIC_WEB=PASS
echo TVKIDS_PUBLIC_HLS=PASS
echo RADIO_UNTOUCHED=PASS
echo MEDIAMTX_UNTOUCHED=PASS
echo "evidence=$OUT"
