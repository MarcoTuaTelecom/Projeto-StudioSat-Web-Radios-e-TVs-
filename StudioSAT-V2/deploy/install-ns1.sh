#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/target/release/studiosat-web"
NGINX="/etc/nginx/conf.d/studiosat-radio.conf"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="${NGINX}.studiosat-v2-backup-${TS}"

[[ $EUID -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
[[ -x "$BIN" ]] || { echo "Build ausente: $BIN" >&2; exit 1; }
[[ -f "$NGINX" ]] || { echo "Nginx ausente: $NGINX" >&2; exit 1; }

install -d -o root -g root -m 0755 /opt/studiosat-v2/bin
install -d -o www-data -g www-data -m 0755 /opt/studiosat-v2/web/static
install -m 0755 "$BIN" /opt/studiosat-v2/bin/studiosat-web
cp -a "$ROOT/apps/web-rust/static/." /opt/studiosat-v2/web/static/
chown -R www-data:www-data /opt/studiosat-v2/web
install -m 0644 "$ROOT/deploy/studiosat-v2-web.service" /etc/systemd/system/studiosat-v2-web.service

systemctl daemon-reload
systemctl enable --now studiosat-v2-web.service
sleep 2
curl -fsS http://127.0.0.1:8792/health >/dev/null

cp -a "$NGINX" "$BACKUP"
python3 - "$NGINX" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); text=p.read_text(); marker='# STUDIO-SAT-V2-LISTEN BEGIN'
if marker in text:
    print('NGINX_V2_ALREADY_PRESENT=YES'); raise SystemExit(0)
pos=text.find('www.radio.studiosatweb.com.br')
if pos < 0: raise SystemExit('server_name www.radio.studiosatweb.com.br nao encontrado')
start=text.rfind('server {',0,pos)
if start < 0: raise SystemExit('inicio do server block nao encontrado')
level=0; end=None
for i in range(start,len(text)):
    if text[i]=='{': level+=1
    elif text[i]=='}':
        level-=1
        if level==0: end=i; break
if end is None: raise SystemExit('fim do server block nao encontrado')
block="""
    # STUDIO-SAT-V2-LISTEN BEGIN
    location ^~ /listen-v2/ {
        proxy_pass http://127.0.0.1:8792;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        add_header Cache-Control "no-store" always;
    }
    # STUDIO-SAT-V2-LISTEN END
"""
text=text[:end]+block+text[end:]
tmp=p.with_name('.'+p.name+'.v2.tmp'); tmp.write_text(text); tmp.replace(p)
print('NGINX_V2_PATCHED=YES')
PY

if ! nginx -t; then
  cp -a "$BACKUP" "$NGINX"
  nginx -t
  systemctl reload nginx
  echo "Falha no nginx; rollback: $BACKUP" >&2
  exit 1
fi
systemctl reload nginx

curl -kfsS https://www.radio.studiosatweb.com.br/listen-v2/ | grep -q 'STUDIO SAT V2'
echo "INSTALADO=YES"
echo "URL=https://www.radio.studiosatweb.com.br/listen-v2/"
echo "NGINX_BACKUP=$BACKUP"
