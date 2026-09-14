#!/usr/bin/env bash
# Nome: apply-tv-initial-plena-20260914.sh
# Versão: 1.0
# Escopo: SOMENTE TVs. Rádio é somente observado e deve permanecer imutável.
# Estado final: TVKIDS única origem interna ao vivo; TVTEENS/TVTEENSWEB = aliases públicos da TVKIDS;
# TVVIVA e TVMAISJOVEM pausadas; TVTEENS runtime interno também pausado.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CAND="$REPO/candidates/CHG-TV-INITIAL-PLENA-20260914"
PLAYER_SRC="$CAND/index-flat.html"
CONF_SRC="$CAND/92-studiosat-tv-initial-plena.conf"
CONF_DST="/etc/nginx/conf.d/92-studiosat-tv-initial-plena.conf"
ACME_CONF="/etc/nginx/conf.d/89-studiosat-tvteensweb-acme.conf"
WEBROOT="/var/www/studiosat-tv/current"
ASSET_DIR="$WEBROOT/assets"
INDEX="$WEBROOT/index.html"
HLSJS="$ASSET_DIR/hls.min.js"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/TV-INITIAL-PLENA-$TS"
BACKUP_BASE="/root/pre_intalacao_plena_backup"
BACKUP="$BACKUP_BASE/$TS"
CERT_NAME="tvteensweb.studiosatweb.com.br"
CERT_DIR="/etc/letsencrypt/live/$CERT_NAME"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
PAUSE_TVS=(tvteens tvviva tvmaisjovem)
TV_HOSTS=(
 tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br
 tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br tvteensweb.studiosatweb.com.br
 tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br
 tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br
)
MUTATED=0
OWNERS_TAR=0
WEBROOT_TAR=0

die(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
have(){ command -v "$1" >/dev/null 2>&1; }

for c in git systemctl curl jq nginx sha256sum awk grep sed flock install cp mv rm mkdir find sort xargs diff tar date sleep seq head python3 certbot openssl stat getent tee; do
  have "$c" || die "MISSING_TOOL:$c"
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT
cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
[[ -f "$PLAYER_SRC" && -f "$CONF_SRC" ]] || die CANDIDATE_MISSING
[[ -f /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem && -f /etc/letsencrypt/live/studiosatweb-completo/privkey.pem ]] || die BASE_TLS_MISSING
bash -n "$0"

mkdir -p "$OUT" "$BACKUP" "$BACKUP_BASE"
chmod 0700 "$BACKUP_BASE" "$BACKUP"
ln -sfn "$BACKUP" "$BACKUP_BASE/latest"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK
jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"
[[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }

# ===== RADIO: SOMENTE BASELINE DE IMUTABILIDADE =====
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

# ===== SHARED MEDIAMTX: OBSERVADO, NUNCA REINICIADO =====
MTX_PID="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PID" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING

# ===== TVKIDS TEM DE ESTAR REALMENTE VIVA ANTES DA MUDANÇA =====
TVKIDS_PID="$(systemctl show tps-tvkids-playout.service -p MainPID --value 2>/dev/null || true)"
[[ "$(systemctl is-active tps-tvkids-playout.service 2>/dev/null || true)" == active && "$TVKIDS_PID" =~ ^[1-9][0-9]*$ ]] || die TVKIDS_NOT_ACTIVE
ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_NOT_READY
hc="$(curl -LsS --connect-timeout 3 --max-time 12 -o "$OUT/tvkids.local.pre.m3u8" -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 || true)"
[[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$OUT/tvkids.local.pre.m3u8" || die TVKIDS_LOCAL_HLS_PRE_FAIL
echo TVKIDS_INTERNAL_PRE=PASS

# ===== BACKUP PLENO PRE-INSTALAÇÃO (ANTES DE QUALQUER MUTAÇÃO) =====
printf 'timestamp=%s\ngit_head=%s\nmediamtx_pid=%s\ntvkids_pid=%s\n' "$TS" "$(git rev-parse HEAD)" "$MTX_PID" "$TVKIDS_PID" > "$BACKUP/metadata.txt"
nginx -T > "$BACKUP/nginx-T.before.txt" 2>&1 || die NGINX_T_PRE_FAIL
systemctl list-unit-files 'tps-tv*-playout.service' --no-pager > "$BACKUP/tv-unit-files.before.txt" || true
for st in tvkids tvteens tvviva tvmaisjovem; do
  systemctl status "tps-${st}-playout.service" --no-pager -l > "$BACKUP/$st.status.before.txt" 2>&1 || true
  systemctl cat "tps-${st}-playout.service" > "$BACKUP/$st.unit.before.txt" 2>&1 || true
done
curl -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:9997/v3/paths/list > "$BACKUP/mediamtx-paths.before.json" || true
certbot certificates > "$BACKUP/certbot-certificates.before.txt" 2>&1 || true
# Cópia integral para recuperação humana; rollback automático abaixo usa apenas escopo TV.
tar -czPf "$BACKUP/nginx-full-readonly.tar.gz" /etc/nginx 2>/dev/null || die BACKUP_NGINX_FAIL
tar -czPf "$BACKUP/tv-systemd-full.tar.gz" --ignore-failed-read \
  /etc/systemd/system/tps-tvkids-playout.service /etc/systemd/system/tps-tvkids-playout.service.d \
  /etc/systemd/system/tps-tvteens-playout.service /etc/systemd/system/tps-tvteens-playout.service.d \
  /etc/systemd/system/tps-tvviva-playout.service /etc/systemd/system/tps-tvviva-playout.service.d \
  /etc/systemd/system/tps-tvmaisjovem-playout.service /etc/systemd/system/tps-tvmaisjovem-playout.service.d \
  /usr/local/sbin/tps-playout-tv /usr/local/sbin/tps-generate-playlist-tvteens-recovery 2>/dev/null || true
tar -czPf "$BACKUP/tv-repository-state.tar.gz" --ignore-failed-read \
  /srv/tpsmedia/repository/channels/tvkids/playlists \
  /srv/tpsmedia/repository/channels/tvteens/playlists \
  /srv/tpsmedia/repository/channels/tvviva/playlists \
  /srv/tpsmedia/repository/channels/tvmaisjovem/playlists 2>/dev/null || true
tar -czPf "$BACKUP/letsencrypt-full.tar.gz" /etc/letsencrypt 2>/dev/null || die BACKUP_CERTS_FAIL
if [[ -d /var/www/studiosat-tv ]]; then
  tar -czPf "$BACKUP/tv-webroot.before.tar.gz" /var/www/studiosat-tv
  WEBROOT_TAR=1
fi
sha256sum "$BACKUP"/*.tar.gz > "$BACKUP/SHA256SUMS"
echo "PRE_INTALACAO_PLENA_BACKUP=PASS path=$BACKUP"

# ===== ESTADO ORIGINAL DAS TRÊS TVs QUE SERÃO PAUSADAS =====
: > "$OUT/tv.pre.tsv"
for st in "${PAUSE_TVS[@]}"; do
  u="tps-${st}-playout.service"
  active="$(systemctl is-active "$u" 2>/dev/null || true)"; [[ -n "$active" ]] || active=unknown
  enabled="$(systemctl is-enabled "$u" 2>/dev/null || true)"; [[ -n "$enabled" ]] || enabled=unknown
  printf '%s\t%s\t%s\n' "$st" "$active" "$enabled" >> "$OUT/tv.pre.tsv"
done

# ===== CLASSIFICA OWNERS NGINX TV REAIS =====
nginx -t > "$OUT/nginx.pre.txt" 2>&1 || die NGINX_PRETEST_FAIL
: > "$OUT/tv-owner-files.txt"
for h in "${TV_HOSTS[@]}"; do
  grep -RIl --include='*.conf' -- "$h" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null || true
done | sort -u > "$OUT/tv-owner-files.txt"
: > "$OUT/retire-files.txt"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  [[ "$f" == "$CONF_DST" || "$f" == "$ACME_CONF" ]] && continue
  if grep -Eqi '(radio\.studiosatweb\.com\.br|radioprincipal|radiopop|radiorock|radioclassicas|radiocountry)' "$f"; then
    die "TV_OWNER_MIXES_RADIO:$f"
  fi
  if ! python3 - "$f" <<'PY'
import re,sys
p=sys.argv[1]
allowed={
'tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br','tvkidsweb.studiosatweb.com.br','www.tvkidsweb.studiosatweb.com.br',
'tvteens.studiosatweb.com.br','www.tvteens.studiosatweb.com.br','tvteensweb.studiosatweb.com.br',
'tvviva.studiosatweb.com.br','www.tvviva.studiosatweb.com.br','tvmaisjovem.studiosatweb.com.br','www.tvmaisjovem.studiosatweb.com.br'}
text=open(p,encoding='utf-8',errors='replace').read()
n=[]
for m in re.finditer(r'\bserver_name\s+([^;]+);',text,re.S): n += m.group(1).split()
foreign=sorted({x for x in n if x not in allowed and x not in {'_','""'}})
if foreign:
    print('FOREIGN_SERVER_NAMES='+','.join(foreign),file=sys.stderr)
    raise SystemExit(1)
PY
  then die "TV_OWNER_HAS_FOREIGN_NAMES:$f"; fi
  printf '%s\n' "$f" >> "$OUT/retire-files.txt"
done < "$OUT/tv-owner-files.txt"
mapfile -t RETIRE < "$OUT/retire-files.txt"
if ((${#RETIRE[@]})); then
  tar -czPf "$BACKUP/nginx-tv-owners.before.tar.gz" "${RETIRE[@]}"
  OWNERS_TAR=1
fi
printf 'TV_OWNERS_BEFORE:\n'; cat "$OUT/tv-owner-files.txt" || true
echo TV_OWNER_CLASSIFICATION=PASS

# ===== BAIXA HLS.JS FIXO ANTES DE QUALQUER MUTAÇÃO =====
curl -fL --connect-timeout 8 --max-time 45 \
  https://cdn.jsdelivr.net/npm/hls.js@1.7.2/dist/hls.min.js \
  -o "$OUT/hls.min.js"
[[ "$(stat -c '%s' "$OUT/hls.min.js")" -gt 100000 ]] || die HLSJS_DOWNLOAD_INVALID
grep -q 'Hls' "$OUT/hls.min.js" || die HLSJS_CONTENT_INVALID
echo HLSJS_LOCAL_CANDIDATE=PASS

rollback(){
  set +e
  echo '=== ROLLBACK TV INITIAL PLENA ==='
  rm -f "$CONF_DST" "$ACME_CONF"
  for f in "${RETIRE[@]}"; do [[ -n "$f" ]] && rm -f "$f"; done
  if (( OWNERS_TAR == 1 )); then tar -xzPf "$BACKUP/nginx-tv-owners.before.tar.gz"; fi
  if (( WEBROOT_TAR == 1 )); then rm -rf /var/www/studiosat-tv; tar -xzPf "$BACKUP/tv-webroot.before.tar.gz"; else rm -rf /var/www/studiosat-tv; fi
  while IFS=$'\t' read -r st active enabled; do
    u="tps-${st}-playout.service"
    case "$enabled" in enabled) systemctl enable "$u" >/dev/null 2>&1 || true;; disabled) systemctl disable "$u" >/dev/null 2>&1 || true;; esac
    if [[ "$active" == active ]]; then systemctl start "$u" >/dev/null 2>&1 || true; else systemctl stop "$u" >/dev/null 2>&1 || true; fi
  done < "$OUT/tv.pre.tsv"
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

# ===== CERTIFICADO DEDICADO PARA tvteensweb (NÃO ALTERA CERTIFICADO DAS RÁDIOS) =====
cert_ok=0
if [[ -f "$CERT_DIR/fullchain.pem" && -f "$CERT_DIR/privkey.pem" ]]; then
  if openssl x509 -checkend 604800 -noout -in "$CERT_DIR/fullchain.pem" >/dev/null 2>&1 && \
     openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -text | grep -q 'DNS:tvteensweb.studiosatweb.com.br'; then cert_ok=1; fi
fi
if (( cert_ok == 0 )); then
  # DNS precisa existir antes do ACME. Se não resolver, aborta sem pausar nenhuma TV.
  getent ahostsv4 tvteensweb.studiosatweb.com.br > "$OUT/tvteensweb.dns.txt" || die TVTEENSWEB_DNS_NOT_RESOLVING
  mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
  cat > "$OUT/89-studiosat-tvteensweb-acme.conf" <<'NG'
server {
    listen 80;
    listen [::]:80;
    server_name tvteensweb.studiosatweb.com.br;
    location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; default_type text/plain; }
    location / { return 302 https://tvkidsweb.studiosatweb.com.br$request_uri; }
}
NG
  MUTATED=1
  install -o root -g root -m 0644 "$OUT/89-studiosat-tvteensweb-acme.conf" "$ACME_CONF"
  nginx -t | tee "$OUT/nginx.acme.txt"
  systemctl reload nginx
  certbot certonly --webroot -w /var/www/letsencrypt \
    -d tvteensweb.studiosatweb.com.br \
    --cert-name "$CERT_NAME" --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring
  [[ -f "$CERT_DIR/fullchain.pem" && -f "$CERT_DIR/privkey.pem" ]] || die TVTEENSWEB_CERT_NOT_CREATED
  openssl x509 -checkend 604800 -noout -in "$CERT_DIR/fullchain.pem" >/dev/null || die TVTEENSWEB_CERT_TOO_SHORT
  openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -text | grep -q 'DNS:tvteensweb.studiosatweb.com.br' || die TVTEENSWEB_CERT_WRONG_SAN
fi
echo TVTEENSWEB_TLS=PASS

# ===== MUTA SOMENTE TVs =====
MUTATED=1
for st in "${PAUSE_TVS[@]}"; do
  systemctl disable --now "tps-${st}-playout.service"
done
for f in "${RETIRE[@]}"; do [[ -n "$f" ]] && rm -f "$f"; done
rm -f "$ACME_CONF"
install -d -o www-data -g www-data -m 0755 "$WEBROOT" "$ASSET_DIR"
install -o www-data -g www-data -m 0644 "$PLAYER_SRC" "$INDEX.new-$TS"
mv -f "$INDEX.new-$TS" "$INDEX"
install -o www-data -g www-data -m 0644 "$OUT/hls.min.js" "$HLSJS.new-$TS"
mv -f "$HLSJS.new-$TS" "$HLSJS"
install -o root -g root -m 0644 "$CONF_SRC" "$CONF_DST"

nginx -t | tee "$OUT/nginx.post.txt"
nginx -T > "$OUT/nginx-T.post.txt" 2>&1 || die NGINX_T_POST_FAIL
systemctl reload nginx
sleep 3

# ===== PROVAS DO ESTADO FINAL =====
for st in "${PAUSE_TVS[@]}"; do
  [[ "$(systemctl is-active "tps-${st}-playout.service" 2>/dev/null || true)" == inactive ]] || die "TV_NOT_PAUSED:$st"
  [[ "$(systemctl is-enabled "tps-${st}-playout.service" 2>/dev/null || true)" == disabled ]] || die "TV_NOT_DISABLED:$st"
done
[[ "$(systemctl show tps-tvkids-playout.service -p MainPID --value)" == "$TVKIDS_PID" ]] || die TVKIDS_PID_CHANGED
ready="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null | jq -r '.items[]?|select(.name=="tvkids")|.ready' | head -1 || true)"
[[ "$ready" == true ]] || die TVKIDS_NOT_READY_POST

# TVKIDS + aliases TVTEENS devem exibir a mesma TVKIDS e HLS real.
LIVE_HOSTS=(tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br tvteensweb.studiosatweb.com.br)
for h in "${LIVE_HOSTS[@]}"; do
  hdr="$OUT/$h.headers"; body="$OUT/$h.html"; hls="$OUT/$h.m3u8"
  code="$(curl -kLsS --resolve "$h:443:127.0.0.1" -D "$hdr" --connect-timeout 4 --max-time 12 -o "$body" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 200 ]] || die "LIVE_HOST_ROOT_FAIL:$h:$code"
  grep -qi '^X-StudioSat-TV-Source: tvkids' "$hdr" || die "LIVE_HOST_WRONG_SOURCE:$h"
  grep -q '<video id="video"' "$body" || die "FLAT_PLAYER_BODY_FAIL:$h"
  hcode="$(curl -kLsS --resolve "$h:443:127.0.0.1" --connect-timeout 4 --max-time 15 -o "$hls" -w '%{http_code}' "https://$h/tvkids/index.m3u8" || true)"
  [[ "$hcode" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "LIVE_HOST_HLS_FAIL:$h:$hcode"
done
# Compatibilidade: antigo path tvteens também deve entregar o sinal TVKIDS nos hosts Teens.
for h in tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br tvteensweb.studiosatweb.com.br; do
  code="$(curl -kLsS --resolve "$h:443:127.0.0.1" --connect-timeout 4 --max-time 15 -o "$OUT/$h.tvteens-path.m3u8" -w '%{http_code}' "https://$h/tvteens/index.m3u8" || true)"
  [[ "$code" == 200 ]] && grep -q '^#EXTM3U' "$OUT/$h.tvteens-path.m3u8" || die "TVTEENS_COMPAT_HLS_FAIL:$h:$code"
done

for h in tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br; do
  hdr="$OUT/$h.paused.headers"
  code="$(curl -kIsS --resolve "$h:443:127.0.0.1" --connect-timeout 4 --max-time 10 -o /dev/null -D "$hdr" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 503 ]] || die "PAUSED_HOST_HTTP_FAIL:$h:$code"
  grep -qi '^X-StudioSat-TV-State: paused' "$hdr" || die "PAUSED_HOST_WRONG_STATE:$h"
done

# Confirma que somente TVKIDS está publicando internamente entre as TVs.
paths="$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9997/v3/paths/list 2>/dev/null || echo '{"items":[]}')"
for st in tvteens tvviva tvmaisjovem; do
  r="$(jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' <<<"$paths" | head -1)"; [[ -n "$r" ]] || r=false
  [[ "$r" != true ]] || die "PAUSED_TV_STILL_READY:$st"
done

# ===== GARANTIA FINAL: RÁDIOS E MEDIAMTX INTACTOS =====
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
echo TV_INITIAL_PLENA=PASS
echo PRE_INTALACAO_PLENA_BACKUP=PASS
echo TVKIDS_ONLY_INTERNAL_LIVE=PASS
echo TVTEENS_PUBLIC_ALIAS_TVKIDS=PASS
echo TVTEENSWEB_PUBLIC_ALIAS_TVKIDS=PASS
echo TVVIVA_PAUSED=PASS
echo TVMAISJOVEM_PAUSED=PASS
echo FLAT_SCREEN_PUBLIC_PLAYER=PASS
echo RADIO_UNTOUCHED=PASS
echo MEDIAMTX_UNTOUCHED=PASS
echo "backup=$BACKUP"
echo "evidence=$OUT"
