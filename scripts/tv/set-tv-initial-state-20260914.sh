#!/usr/bin/env bash
# Nome: set-tv-initial-state-20260914.sh
# Versão: 1.0
# Escopo: TV-only. Mantém TVKIDS no ar, pausa TVTEENS/TVVIVA/TVMAISJOVEM internamente,
# aponta TVTEENS para URL externa e publica TVVIVA/TVMAISJOVEM como PAUSED.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
EXT_URL="${1:-}"
CONF_DST="/etc/nginx/conf.d/91-studiosat-tv-initial-state.conf"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/TV-INITIAL-STATE-$TS"
BACKUP="/var/backups/studiosat/TV-INITIAL-STATE/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
PAUSE_TVS=(tvteens tvviva tvmaisjovem)
TVKIDS_HOST="tvkidsweb.studiosatweb.com.br"
MUTATED=0
CONF_EXISTED=0

die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
have(){ command -v "$1" >/dev/null 2>&1; }

for c in git systemctl curl jq nginx sha256sum awk grep flock install cp rm mkdir find sort xargs diff date python3 head sleep; do
  have "$c" || die "MISSING_TOOL:$c"
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
[[ -n "$EXT_URL" ]] || die 'USAGE:set-tv-initial-state-20260914.sh https://URL-EXTERNA-DA-TVTEENS/'
python3 - "$EXT_URL" <<'PY' || exit 64
import sys, urllib.parse
u=urllib.parse.urlparse(sys.argv[1])
if u.scheme not in {'http','https'} or not u.netloc:
    raise SystemExit('URL externa inválida')
PY

cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY

mkdir -p "$OUT" "$BACKUP"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK

# Rádio: somente congelamento/validação, sem qualquer ação.
: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  u="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$u" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE_PRE:$st"
  pid="$(systemctl show "$u" -p MainPID --value)"
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

# Shared MediaMTX must stay untouched.
MTX_PID="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PID" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING

# TVKIDS must already be genuinely live before touching the other TV units.
TVKIDS_PID="$(systemctl show tps-tvkids-playout.service -p MainPID --value 2>/dev/null || true)"
[[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active && "$TVKIDS_PID" =~ ^[1-9][0-9]*$ ]] || die TVKIDS_NOT_ACTIVE
ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_NOT_READY
hc="$(curl -kLsS --resolve "$TVKIDS_HOST:443:127.0.0.1" --max-time 12 -o "$OUT/tvkids.pre.m3u8" -w '%{http_code}' "https://$TVKIDS_HOST/tvkids/index.m3u8" || true)"
[[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$OUT/tvkids.pre.m3u8" || die TVKIDS_PUBLIC_HLS_PRE_FAIL

echo TVKIDS_PRE=PASS

# Preserve current state of the 3 TVs to allow rollback.
: > "$OUT/tv.pre.tsv"
for st in "${PAUSE_TVS[@]}"; do
  u="tps-${st}-playout.service"
  active="$(systemctl is-active "$u" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$u" 2>/dev/null || true)"
  printf '%s\t%s\t%s\n' "$st" "$active" "$enabled" >> "$OUT/tv.pre.tsv"
done

# NGINX current config must be valid. Do not steal hostnames already owned elsewhere.
nginx -t > "$OUT/nginx.pre.txt" 2>&1 || die NGINX_PRETEST_FAIL
nginx -T > "$OUT/nginx-T.pre.txt" 2>&1 || die NGINX_T_PRE_FAIL
for h in tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br; do
  owners="$(grep -RIl --include='*.conf' --exclude='91-studiosat-tv-initial-state.conf' -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null || true)"
  [[ -z "$owners" ]] || { printf '%s\n' "$owners" > "$OUT/conflict-$h.txt"; die "TV_PUBLIC_VHOST_CONFLICT:$h"; }
done

[[ -f "$CONF_DST" ]] && { CONF_EXISTED=1; cp -a "$CONF_DST" "$BACKUP/91-studiosat-tv-initial-state.conf.before"; }

# Generate deterministic TV-only config. No Radio names are present.
python3 - "$EXT_URL" "$OUT/91-studiosat-tv-initial-state.conf" <<'PY'
import sys
url,out=sys.argv[1:3]
# NGINX return target: reject characters that could break syntax.
if any(c in url for c in ['\n','\r',';','{','}']):
    raise SystemExit('unsafe URL')
conf=f'''# StudioSat initial TV state — TV-only\nserver {{\n    listen 80;\n    listen [::]:80;\n    server_name tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br;\n    return 302 {url};\n}}\nserver {{\n    listen 443 ssl;\n    listen [::]:443 ssl;\n    server_name tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br;\n    ssl_certificate /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem;\n    ssl_certificate_key /etc/letsencrypt/live/studiosatweb-completo/privkey.pem;\n    add_header X-StudioSat-TV-State "external" always;\n    return 302 {url};\n}}\nserver {{\n    listen 80;\n    listen [::]:80;\n    server_name tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br;\n    default_type text/plain;\n    add_header X-StudioSat-TV-State "paused" always;\n    return 503 "Studio Sat TV — emissora pausada temporariamente\\n";\n}}\nserver {{\n    listen 443 ssl;\n    listen [::]:443 ssl;\n    server_name tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br;\n    ssl_certificate /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem;\n    ssl_certificate_key /etc/letsencrypt/live/studiosatweb-completo/privkey.pem;\n    default_type text/plain;\n    add_header X-StudioSat-TV-State "paused" always;\n    return 503 "Studio Sat TV — emissora pausada temporariamente\\n";\n}}\n'''
open(out,'w',encoding='utf-8').write(conf)
PY

rollback(){
  set +e
  echo '=== ROLLBACK TV INITIAL STATE ==='
  if (( CONF_EXISTED == 1 )); then cp -a "$BACKUP/91-studiosat-tv-initial-state.conf.before" "$CONF_DST"; else rm -f "$CONF_DST"; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  while IFS=$'\t' read -r st active enabled; do
    u="tps-${st}-playout.service"
    if [[ "$enabled" == enabled ]]; then systemctl enable "$u" >/dev/null 2>&1 || true; else systemctl disable "$u" >/dev/null 2>&1 || true; fi
    if [[ "$active" == active ]]; then systemctl start "$u" >/dev/null 2>&1 || true; else systemctl stop "$u" >/dev/null 2>&1 || true; fi
  done < "$OUT/tv.pre.tsv"
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

MUTATED=1
# Pause internal TV playouts and keep them off after reboot. TVKIDS is never touched.
for st in "${PAUSE_TVS[@]}"; do
  systemctl disable --now "tps-${st}-playout.service"
done

install -o root -g root -m 0644 "$OUT/91-studiosat-tv-initial-state.conf" "$CONF_DST"
nginx -t | tee "$OUT/nginx.post.txt"
systemctl reload nginx
sleep 2

# Required final service state.
for st in "${PAUSE_TVS[@]}"; do
  [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == inactive ]] || die "TV_NOT_PAUSED:$st"
  [[ "$(systemctl is-enabled "tps-${st}-playout.service" 2>/dev/null || true)" == disabled ]] || die "TV_NOT_DISABLED:$st"
done

# TVTEENS must point exactly to external URL through both main public names.
for h in tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br; do
  hdr="$OUT/$h.headers"
  code="$(curl -kIsS --resolve "$h:443:127.0.0.1" --max-time 10 -o /dev/null -D "$hdr" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 302 ]] || die "TVTEENS_REDIRECT_HTTP_FAIL:$h:$code"
  location="$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]+:[[:space:]]*/,"",$0);print;exit}' "$hdr")"
  [[ "$location" == "$EXT_URL" ]] || die "TVTEENS_REDIRECT_TARGET_FAIL:$h:$location"
done

# TVVIVA / TVMAISJOVEM are explicit paused, never Radio fallback.
for h in tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br; do
  hdr="$OUT/$h.headers"
  code="$(curl -kIsS --resolve "$h:443:127.0.0.1" --max-time 10 -o /dev/null -D "$hdr" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 503 ]] || die "PAUSED_TV_HTTP_FAIL:$h:$code"
  grep -qi '^X-StudioSat-TV-State: paused' "$hdr" || die "PAUSED_TV_WRONG_OWNER:$h"
done

# TVKIDS still exactly alive, same PID, public HLS available.
[[ "$(systemctl show tps-tvkids-playout.service -p MainPID --value)" == "$TVKIDS_PID" ]] || die TVKIDS_PID_CHANGED
ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_NOT_READY_POST
hc="$(curl -kLsS --resolve "$TVKIDS_HOST:443:127.0.0.1" --max-time 12 -o "$OUT/tvkids.post.m3u8" -w '%{http_code}' "https://$TVKIDS_HOST/tvkids/index.m3u8" || true)"
[[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$OUT/tvkids.post.m3u8" || die TVKIDS_PUBLIC_HLS_POST_FAIL

# Shared MediaMTX and all Radio runtime/config/webroot must be unchanged.
[[ "$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)" == "$MTX_PID" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  u="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$u" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE_POST:$st"
  [[ "$(systemctl show "$u" -p MainPID --value)" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f shpre; do [[ "$(sha "$f")" == "$shpre" ]] || die "RADIO_NGINX_CHANGED:$f"; done < "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  key="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$key.post.sha256"
  diff -u "$OUT/$key.pre.sha256" "$OUT/$key.post.sha256" > "$OUT/$key.diff" || die "RADIO_WEBROOT_CHANGED:$d"
done

trap - EXIT
echo TV_INITIAL_STATE=PASS
echo TVKIDS_ONLY_INTERNAL_STREAM=PASS
echo TVTEENS_EXTERNAL_REDIRECT=PASS
echo TVVIVA_PAUSED=PASS
echo TVMAISJOVEM_PAUSED=PASS
echo RADIO_UNTOUCHED=PASS
echo MEDIAMTX_UNTOUCHED=PASS
echo "evidence=$OUT"
