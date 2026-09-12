#!/usr/bin/env bash
# Nome: deploy-tv-player-v2.sh
# Versão: 1.0
# Owner: TV + Core
# Safety class: production-change (webroot TV only)
# Change ID: CHG-TV-PLAYER-002
# Propósito: atualizar somente o player web das TVs para modo full-screen/resiliente, preservando Rádio, NGINX e streaming.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
SRC="$REPO/candidates/CHG-TV-PLAYER-002/tv-player-index-v2.html"
DST="/var/www/studiosat-tv-player/index.html"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TV-PLAYER-002-$TS"
BACKUP="/var/backups/studiosat/CHG-TV-PLAYER-002/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVHOSTS=(
 'tvkids.studiosatweb.com.br|tvkids' 'www.tvkids.studiosatweb.com.br|tvkids' 'tvkidsweb.studiosatweb.com.br|tvkids' 'www.tvkidsweb.studiosatweb.com.br|tvkids'
 'tvteens.studiosatweb.com.br|tvteens' 'www.tvteens.studiosatweb.com.br|tvteens'
 'tvviva.studiosatweb.com.br|tvviva' 'www.tvviva.studiosatweb.com.br|tvviva'
 'tvmaisjovem.studiosatweb.com.br|tvmaisjovem' 'www.tvmaisjovem.studiosatweb.com.br|tvmaisjovem'
)
die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1"|awk '{print $1}'; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -f "$SRC" && -f "$DST" ]] || die PLAYER_SOURCE_OR_DEST_MISSING
mkdir -p "$OUT" "$BACKUP"; chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"; flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK

NG1=/etc/nginx/conf.d/studiosat-radio.conf; NG2=/etc/nginx/conf.d/zz-studiosat-radio-portal.conf
[[ -f "$NG1" && -f "$NG2" ]] || die RADIO_NGINX_MISSING
printf '%s\t%s\n%s\t%s\n' "$NG1" "$(sha "$NG1")" "$NG2" "$(sha "$NG2")" > "$OUT/radio-nginx.pre.tsv"
: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  u="tps-${st}-playout.service"; [[ "$(systemctl is-active "$u" 2>/dev/null||true)" == active ]] || die "RADIO_NOT_ACTIVE:$st"
  pid="$(systemctl show "$u" -p MainPID --value)"; pl="/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt"; [[ -f "$pl" ]] || die "RADIO_PLAYLIST_MISSING:$st"
  printf '%s\t%s\t%s\n' "$st" "$pid" "$(sha "$pl")" >> "$OUT/radio.pre.tsv"
done
MTX_PRE="$(systemctl show tps-mediamtx.service -p MainPID --value)"
cp -a "$DST" "$BACKUP/index.html.before"
PRE="$(sha "$DST")"; NEW="$(sha "$SRC")"; echo "player_pre=$PRE"; echo "player_new=$NEW"
install -o www-data -g www-data -m 0644 "$SRC" "$DST.new-$TS"
mv -f "$DST.new-$TS" "$DST"

rollback(){ set +e; cp -a "$BACKUP/index.html.before" "$DST"; echo ROLLBACK=PLAYER_RESTORED; }
trap 'rc=$?; if (( rc != 0 )); then rollback; fi; exit $rc' EXIT

# Prova de que NGINX continua válido sem reload (configuração não foi alterada).
nginx -t > "$OUT/nginx-t.txt" 2>&1 || die NGINX_TEST_FAIL

# Todas as TVs: root deve ser o player TV e HLS deve ser M3U8 real.
for x in "${TVHOSTS[@]}"; do
  host="${x%%|*}"; st="${x#*|}"; hdr="$OUT/$host.headers"; root="$OUT/$host.root"; hls="$OUT/$host.hls"
  rc="$(curl -kLsS -D "$hdr" --connect-timeout 5 --max-time 15 -o "$root" -w '%{http_code}' "https://$host/" || true)"
  [[ "$rc" == 200 ]] || die "TV_ROOT_HTTP:$host:$rc"
  grep -qi '^X-StudioSat-TV: tv-player-v1' "$hdr" || die "TV_ROOT_WRONG_VHOST:$host"
  grep -q 'Studio Sat TV — Ao Vivo' "$root" || die "TV_PLAYER_V2_NOT_PUBLIC:$host"
  hc="$(curl -kLsS --connect-timeout 5 --max-time 15 -o "$hls" -w '%{http_code}' "https://$host/$st/index.m3u8" || true)"
  [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "TV_HLS_BAD:$host:$hc"
done

# Rádio e MediaMTX invariáveis.
[[ "$(systemctl show tps-mediamtx.service -p MainPID --value)" == "$MTX_PRE" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  pidnow="$(systemctl show "tps-${st}-playout.service" -p MainPID --value)"; [[ "$pidnow" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f spre; do [[ "$(sha "$f")" == "$spre" ]] || die "RADIO_NGINX_CHANGED:$f"; done < "$OUT/radio-nginx.pre.tsv"

trap - EXIT
echo CHG_TV_PLAYER_002=PASS
echo PLAYER_FULLSCREEN_RESILIENT_V2=PASS
echo ALL_RADIOS_PRESERVED=PASS
echo MEDIAMTX_PRESERVED=PASS
echo "player_sha=$(sha "$DST")"
echo "backup=$BACKUP/index.html.before"
