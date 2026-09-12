#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
umask 077

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
CONF="/etc/nginx/conf.d/zz-tvkids-isolated.conf"
CERT="/etc/letsencrypt/live/studiosatweb-completo/fullchain.pem"
KEY="/etc/letsencrypt/live/studiosatweb-completo/privkey.pem"
BACKUP_ROOT="/var/backups/studiosat/CHG-TVWEB02"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"
TMP_BODY="/tmp/tvkids-body.$$"
TMP_CONF="/tmp/zz-tvkids-isolated.conf.$$"
OLD_CONF_PRESENT=0

log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'FAIL: %s\n' "$*" >&2; return 1; }

radio_health(){
  local ch state code
  for ch in "${RADIOS[@]}"; do
    state="$(systemctl is-active "tps-${ch}-playout.service" 2>/dev/null || true)"
    code="$(curl -sS -L --max-time 6 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8888/${ch}/index.m3u8" 2>/dev/null || true)"
    printf 'RADIO %-18s service=%-8s HLS=%s\n' "$ch" "$state" "$code"
    [[ "$state" == "active" && "$code" == "200" ]] || fail "rádio $ch não saudável" || return 1
  done
}

choose_tv_root(){
  if [[ -f /var/www/portais/www.tvkidsweb.studiosatweb.com.br/index.html ]]; then
    TV_ROOT="/var/www/portais/www.tvkidsweb.studiosatweb.com.br"
    TV_INDEX="index.html"
  elif [[ -f /var/www/portais/www.tvkids.studiosatweb.com.br/index.html ]]; then
    TV_ROOT="/var/www/portais/www.tvkids.studiosatweb.com.br"
    TV_INDEX="index.html"
  elif [[ -f /var/www/emissoras/tvkids.html ]]; then
    TV_ROOT="/var/www/emissoras"
    TV_INDEX="tvkids.html"
  else
    fail "nenhum conteúdo TVKIDS encontrado nos roots conhecidos"
    return 1
  fi
  echo "TV_ROOT=$TV_ROOT"
  echo "TV_INDEX=$TV_INDEX"
}

rollback(){
  local rc="${1:-1}"
  trap - ERR INT TERM
  log "ROLLBACK TVKIDS ONLY"
  if [[ "$OLD_CONF_PRESENT" == "1" && -f "$BACKUP/zz-tvkids-isolated.conf" ]]; then
    cp -a "$BACKUP/zz-tvkids-isolated.conf" "$CONF"
  else
    rm -f "$CONF"
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  radio_health || true
  rm -f "$TMP_BODY" "$TMP_CONF"
  echo "AUTO_ROLLBACK_DONE=1"
  exit "$rc"
}

log "PRECHECK rádios"
radio_health
[[ -f "$CERT" ]] || { echo "FAIL: certificado ausente: $CERT" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "FAIL: chave ausente: $KEY" >&2; exit 1; }
choose_tv_root

mkdir -p "$BACKUP"
if [[ -f "$CONF" ]]; then
  OLD_CONF_PRESENT=1
  cp -a "$CONF" "$BACKUP/zz-tvkids-isolated.conf"
fi
nginx -T > "$BACKUP/nginx-T.before.txt" 2>&1 || true
sha256sum "$CERT" "$KEY" > "$BACKUP/tls.sha256"

trap 'rollback $?' ERR INT TERM

cat > "$TMP_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkids.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br;
    return 301 https://\$host\$uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name www.tvkids.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br;

    ssl_certificate $CERT;
    ssl_certificate_key $KEY;

    root $TV_ROOT;

    location = / {
        if (\$arg_station != "") { return 302 https://\$host/; }
        try_files /$TV_INDEX =404;
    }

    location ^~ /tvkids/ {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_buffering off;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "no-cache" always;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name tvkids.studiosatweb.com.br;
    ssl_certificate $CERT;
    ssl_certificate_key $KEY;
    return 301 https://www.tvkids.studiosatweb.com.br\$uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name tvkidsweb.studiosatweb.com.br;
    ssl_certificate $CERT;
    ssl_certificate_key $KEY;
    return 301 https://www.tvkidsweb.studiosatweb.com.br\$uri;
}
EOF

install -o root -g root -m 0644 "$TMP_CONF" "$CONF"
nginx -t
systemctl reload nginx
sleep 2

log "VALIDANDO TVKIDS localmente via SNI"
for host in www.tvkidsweb.studiosatweb.com.br www.tvkids.studiosatweb.com.br; do
  url="https://${host}/?station=radioprincipal"
  effective="$(curl -k -sS -L --resolve "${host}:443:127.0.0.1" --max-redirs 5 --max-time 10 -o "$TMP_BODY" -w '%{url_effective}' "$url")"
  code="$(curl -k -sS -L --resolve "${host}:443:127.0.0.1" --max-redirs 5 --max-time 10 -o /dev/null -w '%{http_code}' "$url")"
  echo "TVKIDS host=$host HTTP=$code FINAL=$effective"
  [[ "$code" == "200" ]] || fail "$host HTTP=$code" || return 1
  [[ "$effective" != *"station="* ]] || fail "$host ainda preserva station=" || return 1
  if grep -Eqi 'RADIO STUDIO SAT|EMISSORA SELECIONADA|PRINCIPAL.*Programação ao vivo' "$TMP_BODY"; then
    fail "$host ainda está servindo o player de rádio"
    return 1
  fi
done

log "VALIDANDO HLS TVKIDS"
TV_HLS="$(curl -sS -L --max-time 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/tvkids/index.m3u8 2>/dev/null || true)"
echo "TVKIDS_HLS=$TV_HLS"
[[ "$TV_HLS" == "200" ]] || fail "HLS interno TVKIDS não está 200" || return 1

log "VALIDANDO rádios após reload gracioso"
radio_health

nginx -T > "$BACKUP/nginx-T.after.txt" 2>&1 || true
sha256sum "$CONF" > "$BACKUP/tvkids-conf.sha256"

trap - ERR INT TERM
rm -f "$TMP_BODY" "$TMP_CONF"

echo "TVKIDSWEB_NOT_RADIO_PLAYER=PASS"
echo "TVKIDS_QUERY_CLEAN=PASS"
echo "TVKIDS_HLS=PASS"
echo "NGINX_TVKIDS_ISOLATED=PASS"
echo "RADIOS_UNINTERRUPTED=PASS"
