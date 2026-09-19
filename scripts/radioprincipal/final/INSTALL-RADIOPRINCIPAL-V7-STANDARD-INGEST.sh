#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/STANDARD-INGEST-V7-${TS}"
mkdir -p "$BK"

DOMAIN='radio.studiosatweb.com.br'
MOUNT='/radioprincipal-rb'
TESTMOUNT='/radioprincipal-preflight'
ICE_SERVICE='studiosat-radioprincipal-v31-icecast.service'
V32='studiosat-radioprincipal-v32-core.service'
ICECFG='/etc/icecast2/radioprincipal-v31.xml'
LOGIN='/root/RADIOPRINCIPAL-RADIOBOSS-LOGIN.txt'
NGINX_SNIPPET_MARK='# STUDIOSAT RADIOPRINCIPAL STANDARD INGEST V7'

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

rollback_nginx(){
  local f="${1:-}"
  [ -n "$f" ] || return 0
  if [ -f "$BK/nginx-target.before" ]; then
    cp -a "$BK/nginx-target.before" "$f"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
}

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"
command -v nginx >/dev/null || fail "NGINX_NOT_INSTALLED"
command -v python3 >/dev/null || fail "PYTHON_NOT_INSTALLED"
command -v ffmpeg >/dev/null || fail "FFMPEG_NOT_INSTALLED"
command -v ffprobe >/dev/null || fail "FFPROBE_NOT_INSTALLED"
[ -f "$ICECFG" ] || fail "ICECAST_CONFIG_NOT_FOUND"

say "=============================================================="
say " RADIO PRINCIPAL V7 - STANDARD RADIOBOSS INGEST"
say " ANY RADIOBOSS / NO PC AGENT / NO AUDIO TUNNEL"
say "=============================================================="
say "BACKUP=$BK"

say "1/10 PRESERVE CURRENT PUBLIC RADIO"
systemctl is-active --quiet "$V32" || fail "V32_NOT_ACTIVE"
timeout 8 ffprobe -v error -rw_timeout 5000000 \
  -show_entries stream=codec_name -of csv=p=0 \
  rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q . ||
  fail "PUBLIC_RTMP_NOT_READY"
echo "PUBLIC_BASELINE=READY"

say "2/10 BACKUP ICECAST + NGINX"
cp -a "$ICECFG" "$BK/icecast.xml.before"
nginx -T >"$BK/nginx-T.before.txt" 2>&1

say "3/10 GENERATE DEDICATED STANDARD SOURCE PASSWORD"
SOURCE_PASS="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(30))
PY
)"
[ "${#SOURCE_PASS}" -ge 32 ] || fail "PASSWORD_GENERATION_FAILED"

python3 - "$ICECFG" "$SOURCE_PASS" <<'PY'
import sys,xml.etree.ElementTree as ET
p,pw=sys.argv[1],sys.argv[2]
tree=ET.parse(p)
root=tree.getroot()
auth=root.find('authentication')
if auth is None:
    auth=ET.SubElement(root,'authentication')
sp=auth.find('source-password')
if sp is None:
    sp=ET.SubElement(auth,'source-password')
sp.text=pw
tree.write(p,encoding='utf-8',xml_declaration=True)
PY

systemctl restart "$ICE_SERVICE"
for i in $(seq 1 15); do
  if ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005'; then
    echo "ICECAST_18005=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005' || fail "ICECAST_18005_NOT_READY"

say "4/10 LOCATE HTTPS NGINX SERVER BLOCK"
NGINX_TARGET="$(python3 - "$DOMAIN" <<'PY'
import re,subprocess,sys
domain=sys.argv[1]
out=subprocess.check_output(['nginx','-T'],stderr=subprocess.STDOUT,text=True)
current=None
for line in out.splitlines():
    m=re.match(r'^# configuration file (.+):$',line)
    if m:
        current=m.group(1)
        continue
    if current and re.search(r'\bserver_name\b[^;]*\b'+re.escape(domain)+r'\b',line):
        print(current)
        break
PY
)"
[ -n "$NGINX_TARGET" ] && [ -f "$NGINX_TARGET" ] || fail "NGINX_DOMAIN_CONFIG_NOT_FOUND"
echo "NGINX_TARGET=$NGINX_TARGET"
cp -a "$NGINX_TARGET" "$BK/nginx-target.before"

say "5/10 ADD STANDARD ICECAST SOURCE PROXY ON EXISTING HTTPS 443"
python3 - "$NGINX_TARGET" "$DOMAIN" "$NGINX_SNIPPET_MARK" <<'PY'
import re,sys
p,domain,mark=sys.argv[1:4]
s=open(p,encoding='utf-8').read()
if mark in s:
    print("NGINX_INGEST_LOCATION=ALREADY_PRESENT")
    raise SystemExit(0)

m=re.search(r'\bserver_name\b[^;]*\b'+re.escape(domain)+r'\b[^;]*;',s)
if not m:
    raise SystemExit("server_name block not found")
start=s.rfind('server',0,m.start())
brace=s.find('{',start)
if start<0 or brace<0:
    raise SystemExit("server block start not found")
depth=0
end=None
quote=None
esc=False
for i,ch in enumerate(s[brace:],start=brace):
    if quote:
        if esc:
            esc=False
        elif ch=='\\':
            esc=True
        elif ch==quote:
            quote=None
        continue
    if ch in ("'",'"'):
        quote=ch
        continue
    if ch=='{':
        depth+=1
    elif ch=='}':
        depth-=1
        if depth==0:
            end=i
            break
if end is None:
    raise SystemExit("server block end not found")

snippet=r'''
    # STUDIOSAT RADIOPRINCIPAL STANDARD INGEST V7
    location = /radioprincipal-rb {
        proxy_pass http://127.0.0.1:18005/radioprincipal-rb;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Connection "";
    }

    location = /radioprincipal-preflight {
        proxy_pass http://127.0.0.1:18005/radioprincipal-preflight;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Connection "";
    }

    location = /admin/metadata {
        proxy_pass http://127.0.0.1:18005/admin/metadata;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
    }
'''
s=s[:end]+snippet+s[end:]
open(p,'w',encoding='utf-8').write(s)
print("NGINX_INGEST_LOCATION=INSERTED")
PY

if ! nginx -t; then
  rollback_nginx "$NGINX_TARGET"
  cp -a "$BK/icecast.xml.before" "$ICECFG"
  systemctl restart "$ICE_SERVICE" || true
  fail "NGINX_CONFIG_INVALID"
fi
systemctl reload nginx

say "6/10 END-TO-END PREFLIGHT THROUGH PUBLIC HTTPS WITHOUT TOUCHING PUBLIC RADIO"
TMPMP3="$BK/preflight.mp3"
ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'sine=frequency=523.25:sample_rate=48000' \
  -t 20 -c:a libmp3lame -b:a 128k "$TMPMP3"

(
  curl -kfsS --http1.1 \
    -X PUT \
    -u "source:$SOURCE_PASS" \
    -H 'Content-Type: audio/mpeg' \
    --limit-rate 128k \
    --data-binary @"$TMPMP3" \
    "https://$DOMAIN$TESTMOUNT" \
    >"$BK/preflight-source.out" 2>"$BK/preflight-source.err"
) &
SRC_PID=$!

TEST_OK=0
for i in $(seq 1 15); do
  if timeout 8 ffprobe -v error -rw_timeout 5000000 \
      -show_entries stream=codec_name,sample_rate,channels \
      -of csv=p=0 \
      "https://$DOMAIN$TESTMOUNT" 2>/dev/null | grep -q .; then
    TEST_OK=1
    echo "STANDARD_HTTPS_SOURCE_PREFLIGHT=PASS AFTER=${i}s"
    break
  fi
  sleep 1
done
kill "$SRC_PID" 2>/dev/null || true
wait "$SRC_PID" 2>/dev/null || true

if [ "$TEST_OK" -ne 1 ]; then
  cat "$BK/preflight-source.err" 2>/dev/null || true
  rollback_nginx "$NGINX_TARGET"
  cp -a "$BK/icecast.xml.before" "$ICECFG"
  systemctl restart "$ICE_SERVICE" || true
  fail "STANDARD_HTTPS_SOURCE_PREFLIGHT_FAILED"
fi

say "7/10 WRITE PORTABLE RADIOBOSS LOGIN"
umask 077
cat >"$LOGIN" <<EOF
STUDIO SAT - RADIO PRINCIPAL
STANDARD RADIOBOSS LOGIN

Server type: Icecast2
Server / Host: $DOMAIN
Port: 443
SSL / TLS: YES
Username: source
Password: $SOURCE_PASS
Mount point: $MOUNT

Recommended encoder:
MP3
128 kbps
48 kHz
Stereo

No Studio Sat script is required on the RadioBOSS computer.
No SSH tunnel is required.
No Windows service is required.

After entering these fields, enable/connect this encoder in RadioBOSS.
EOF
chmod 0600 "$LOGIN"

say "8/10 DISABLE OBSOLETE AUDIO TUNNEL SERVER-SIDE"
if id studiosat-rb-tunnel >/dev/null 2>&1; then
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-studiosat-disable-rb-tunnel.conf <<'EOF'
DenyUsers studiosat-rb-tunnel
EOF
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  pkill -u studiosat-rb-tunnel 2>/dev/null || true
  echo "OBSOLETE_AUDIO_TUNNEL=DISABLED_SERVER_SIDE"
else
  echo "OBSOLETE_AUDIO_TUNNEL_ACCOUNT=NOT_PRESENT"
fi

say "9/10 VERIFY PUBLIC BASELINE STILL ALIVE"
systemctl is-active --quiet "$V32" || fail "V32_STOPPED"
timeout 8 ffprobe -v error -rw_timeout 5000000 \
  -show_entries stream=codec_name -of csv=p=0 \
  rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q . ||
  fail "PUBLIC_RTMP_LOST"
echo "PUBLIC_BASELINE=STILL_READY"

say "10/10 RESULT"
echo "RADIOBOSS_STANDARD_SERVER=$DOMAIN"
echo "RADIOBOSS_STANDARD_PORT=443"
echo "RADIOBOSS_STANDARD_TLS=YES"
echo "RADIOBOSS_STANDARD_MOUNT=$MOUNT"
echo "RADIOBOSS_STANDARD_USERNAME=source"
echo "RADIOBOSS_STANDARD_PASSWORD=$SOURCE_PASS"
echo "LOGIN_FILE=$LOGIN"
echo "PC_AGENT_REQUIRED=NO"
echo "SSH_TUNNEL_REQUIRED=NO"
echo "ANY_RADIOBOSS_MACHINE=YES"
echo "V32_PUBLIC=$(systemctl is-active "$V32")"
echo "RESULTADO=RADIOPRINCIPAL_V7_STANDARD_INGEST_READY"
