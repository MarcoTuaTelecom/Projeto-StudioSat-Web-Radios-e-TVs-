#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

VERSION="1.2.0-RAW-AAC"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/target/release/studiosat-web"
NGINX="/etc/nginx/conf.d/studiosat-radio.conf"
UNIT="/etc/systemd/system/studiosat-v2-web.service"
OPT="/opt/studiosat-v2"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SNAP="/root/StudioSAT-V2-PREINSTALL-${TS}"
NGINX_BACKUP="$SNAP/studiosat-radio.conf.before"
COMMITTED=0

say(){ printf '\n================================================================\n%s\n================================================================\n' "$*"; }
die(){ echo "ERRO: $*" >&2; return 1; }

rollback(){
  local rc=$?
  trap - ERR
  if [[ "$COMMITTED" = "1" ]]; then exit "$rc"; fi
  echo
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FALHA rc=$rc - ROLLBACK StudioSAT V2"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

  if [[ -f "$NGINX_BACKUP" ]]; then
    cp -a "$NGINX_BACKUP" "$NGINX" || true
    nginx -t || true
    systemctl reload nginx 2>/dev/null || true
  fi

  systemctl stop studiosat-v2-web.service 2>/dev/null || true

  if [[ -f "$SNAP/studiosat-v2-web.service.before" ]]; then
    cp -a "$SNAP/studiosat-v2-web.service.before" "$UNIT" || true
  else
    rm -f "$UNIT"
  fi

  if [[ -d "$SNAP/opt-studiosat-v2.before" ]]; then
    rm -rf "$OPT"
    cp -a "$SNAP/opt-studiosat-v2.before" "$OPT" || true
  fi

  systemctl daemon-reload || true
  if [[ -f "$SNAP/service-was-active" ]]; then
    systemctl restart studiosat-v2-web.service 2>/dev/null || true
  fi

  echo "ROLLBACK=CONCLUIDO"
  echo "SNAPSHOT=$SNAP"
  exit "$rc"
}
trap rollback ERR

[[ $EUID -eq 0 ]] || die "Execute como root."
for c in install cp curl python3 nginx systemctl grep sha256sum ffmpeg; do
  command -v "$c" >/dev/null 2>&1 || die "Comando ausente: $c"
done
[[ -x "$BIN" ]] || die "Build ausente: $BIN"
[[ -f "$NGINX" ]] || die "Nginx ausente: $NGINX"

say "StudioSAT V2 INSTALLER v$VERSION"

mkdir -p "$SNAP"
cp -a "$NGINX" "$NGINX_BACKUP"
[[ -f "$UNIT" ]] && cp -a "$UNIT" "$SNAP/studiosat-v2-web.service.before" || true
[[ -d "$OPT" ]] && cp -a "$OPT" "$SNAP/opt-studiosat-v2.before" || true
systemctl is-active --quiet studiosat-v2-web.service 2>/dev/null && touch "$SNAP/service-was-active" || true

sha256sum "$NGINX_BACKUP" > "$SNAP/SHA256SUMS.txt"
echo "SNAPSHOT=$SNAP"

say "1. INSTALANDO BINARIO + STATIC"

install -d -o root -g root -m 0755 "$OPT/bin"
install -d -o www-data -g www-data -m 0755 "$OPT/web/static"
install -m 0755 "$BIN" "$OPT/bin/studiosat-web"
rm -rf "$OPT/web/static/"*
cp -a "$ROOT/apps/web-rust/static/." "$OPT/web/static/"
chown -R www-data:www-data "$OPT/web"

install -m 0644 "$ROOT/deploy/studiosat-v2-web.service" "$UNIT"
systemctl daemon-reload
systemctl enable studiosat-v2-web.service >/dev/null
systemctl restart studiosat-v2-web.service

say "2. PROVA LOCAL DO RUST"

for i in $(seq 1 20); do
  if curl -fsS --max-time 3 http://127.0.0.1:8792/health >"$SNAP/health.json" 2>/dev/null; then
    break
  fi
  sleep 1
done

systemctl is-active --quiet studiosat-v2-web.service || {
  systemctl --no-pager -l status studiosat-v2-web.service || true
  journalctl -u studiosat-v2-web.service -n 120 --no-pager || true
  die "Servico V2 nao ficou active."
}

grep -q '"status":"ok"' "$SNAP/health.json" || die "Health local invalido."
echo "SERVICE=active"
cat "$SNAP/health.json"; echo

curl -fsS --max-time 5 http://127.0.0.1:8792/listen-v2/ >"$SNAP/local-portal.html"
grep -q 'STUDIO SAT V2' "$SNAP/local-portal.html" || die "HTML local V2 invalido."
echo "LOCAL_PORTAL=OK"

curl -fsS --max-time 5 http://127.0.0.1:8792/listen-v2/api/stations >"$SNAP/stations.json"
python3 - "$SNAP/stations.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
ids={x["id"] for x in d}
expected={"radioprincipal","radiopop","radiorock","radioclassicas","radiocountry"}
if ids != expected:
    raise SystemExit(f"catalogo invalido: {ids}")
print("CATALOGO_5_RADIOS=OK")
PY

say "2.1 PROVA LOCAL DO TRANSPORTE RAW AAC"

for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  python3 - "http://127.0.0.1:8792/listen-v2/live/$r/stream.aac" "$r" <<'PY'
import sys,urllib.request
url,name=sys.argv[1],sys.argv[2]
with urllib.request.urlopen(url,timeout=10) as resp:
    ctype=resp.headers.get('Content-Type','')
    transport=resp.headers.get('X-Studiosat-Transport','')
    data=resp.read(7)
if ctype.split(';')[0].strip()!='audio/aac':
    raise SystemExit(f"{name}: content-type inesperado: {ctype}")
if transport!='raw-aac-adts-copy':
    raise SystemExit(f"{name}: transporte inesperado: {transport}")
if not (len(data)>=2 and data[0]==0xff and data[1]&0xf0==0xf0):
    raise SystemExit(f"{name}: sync ADTS invalido: {data.hex()}")
print(f"{name} LOCAL_RAW_AAC=OK")
PY
done

say "3. PATCH TRANSACIONAL DO NGINX"

python3 - "$NGINX" <<'PY'
import re,sys
from pathlib import Path

p=Path(sys.argv[1])
text=p.read_text(encoding="utf-8",errors="strict")

# Remove bloco V2 anterior para tornar a operacao idempotente.
text=re.sub(
    r'\n\s*# STUDIO-SAT-V2-LISTEN BEGIN.*?# STUDIO-SAT-V2-LISTEN END\s*\n',
    '\n',
    text,
    flags=re.S,
)

matches=list(re.finditer(r'server_name\s+[^;]*www\.radio\.studiosatweb\.com\.br[^;]*;', text, re.S))
if len(matches) != 1:
    raise SystemExit(f"esperava exatamente 1 server_name com www.radio; encontrei {len(matches)}")

pos=matches[0].start()
start=text.rfind('server {',0,pos)
if start < 0:
    raise SystemExit('inicio do server block nao encontrado')

level=0
end=None
for i in range(start,len(text)):
    ch=text[i]
    if ch=='{': level+=1
    elif ch=='}':
        level-=1
        if level==0:
            end=i
            break
if end is None:
    raise SystemExit('fim do server block nao encontrado')

block=r'''
    # STUDIO-SAT-V2-LISTEN BEGIN
    location = /listen-v2 {
        return 308 /listen-v2/;
    }

    location ^~ /listen-v2/ {
        proxy_pass http://127.0.0.1:8792;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
        proxy_read_timeout 1h;
        send_timeout 1h;
        gzip off;
        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        add_header X-StudioSat-V2 "rust-native-media" always;
    }
    # STUDIO-SAT-V2-LISTEN END
'''

text=text[:end]+block+text[end:]
tmp=p.with_name('.'+p.name+'.studiosat-v2.tmp')
tmp.write_text(text,encoding="utf-8")
tmp.replace(p)
print("NGINX_V2_PATCH=OK")
PY

nginx -t
systemctl reload nginx
echo "NGINX_RELOAD=OK"

say "4. PROVA DO VHOST LOCAL HTTPS"

curl -kfsS --max-time 8   --resolve www.radio.studiosatweb.com.br:443:127.0.0.1   -D "$SNAP/vhost-local.headers"   https://www.radio.studiosatweb.com.br/listen-v2/   -o "$SNAP/vhost-local.html"

grep -q 'STUDIO SAT V2' "$SNAP/vhost-local.html" || die "Vhost local nao entrega o V2."
grep -qi '^X-StudioSat-V2: rust-native-media' "$SNAP/vhost-local.headers" || die "Header V2 ausente no vhost local."
echo "VHOST_LOCAL=OK"

say "5. PROVA PUBLICA"

curl -kfsS --max-time 12   -D "$SNAP/public.headers"   "https://www.radio.studiosatweb.com.br/listen-v2/?v=$TS"   -o "$SNAP/public.html"

grep -q 'STUDIO SAT V2' "$SNAP/public.html" || die "URL publica nao entrega o V2."
grep -qi '^X-StudioSat-V2: rust-native-media' "$SNAP/public.headers" || die "Header V2 ausente na URL publica."
echo "PUBLIC_PORTAL=OK"

curl -kfsS --max-time 10   "https://www.radio.studiosatweb.com.br/listen-v2/api/stations?v=$TS"   >"$SNAP/public-stations.json"

python3 - "$SNAP/public-stations.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
if len(d)!=5:
    raise SystemExit(f"esperava 5 radios, recebi {len(d)}")
print("PUBLIC_API_5_RADIOS=OK")
PY

say "5.1 PROVA PUBLICA DO TRANSPORTE RAW AAC"

for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  python3 - "https://www.radio.studiosatweb.com.br/listen-v2/live/$r/stream.aac" "$r" <<'PY'
import ssl,sys,urllib.request
url,name=sys.argv[1],sys.argv[2]
ctx=ssl._create_unverified_context()
req=urllib.request.Request(url,headers={'Cache-Control':'no-cache'})
with urllib.request.urlopen(req,timeout=12,context=ctx) as resp:
    ctype=resp.headers.get('Content-Type','')
    transport=resp.headers.get('X-Studiosat-Transport','')
    data=resp.read(7)
if ctype.split(';')[0].strip()!='audio/aac':
    raise SystemExit(f"{name}: content-type publico inesperado: {ctype}")
if transport!='raw-aac-adts-copy':
    raise SystemExit(f"{name}: transporte publico inesperado: {transport}")
if not (len(data)>=2 and data[0]==0xff and data[1]&0xf0==0xf0):
    raise SystemExit(f"{name}: sync ADTS publico invalido: {data.hex()}")
print(f"{name} PUBLIC_RAW_AAC=OK")
PY
done

say "6. STREAMS - NAO MODIFICADOS"

for r in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  curl -kfsS --max-time 10 "https://radio.studiosatweb.com.br/$r/index.m3u8"     | grep -q '^#EXTM3U' || die "$r HLS invalido"
  echo "$r HLS=OK"
done

COMMITTED=1
trap - ERR

say "INSTALACAO CONCLUIDA"
echo "RESULTADO=OK"
echo "SERVICE=studiosat-v2-web.service"
echo "URL=https://www.radio.studiosatweb.com.br/listen-v2/"\necho "RAW_PRINCIPAL=https://www.radio.studiosatweb.com.br/listen-v2/live/radioprincipal/stream.aac"
echo "REFERENCE=https://radio.studiosatweb.com.br/diag-bypass/"
echo "SNAPSHOT=$SNAP"
