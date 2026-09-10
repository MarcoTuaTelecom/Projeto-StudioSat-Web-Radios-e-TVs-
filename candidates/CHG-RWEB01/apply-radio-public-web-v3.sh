#!/usr/bin/env bash
# StudioSat Web — CHG-RWEB01 public cutover
# Split Radio hostnames away from the legacy shared Radio/TV NGINX blocks,
# preserve all TV hostnames, and point Radio to isolated player/portal roots.
set -Eeuo pipefail
IFS=$'\n\t'

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT' >&2; exit 77; }

REPO=${REPO:-/root/Projeto-StudioSat-Web-Radios-e-TVs-}
SHARED=/etc/nginx/conf.d/tps-9-emissoras.conf
RADIO_CONF=/etc/nginx/conf.d/tps-radio-web.conf
CAND_CONF="$REPO/candidates/CHG-RWEB01/nginx-radio-isolated-v1.conf"
PORTAL_ROOT=/var/www/studiosat-radio-portal
PLAYER_ROOT=/var/www/studiosat-radio-player
TS=$(date -u +%Y%m%dT%H%M%SZ)
BK=/var/backups/studiosat/CHG-RWEB01-NGINX/$TS
OUT=/tmp/CHG-RWEB01-NGINX-$TS
MUTATED=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in nginx systemctl python3 cp install mv mktemp curl grep sha256sum git; do need "$c"; done

mkdir -p "$BK" "$OUT"
exec > >(tee "$OUT/REPORT.txt") 2>&1

rollback(){
  echo 'ROLLBACK=START'
  if [[ -f "$BK/tps-9-emissoras.conf.previous" ]]; then cp -a "$BK/tps-9-emissoras.conf.previous" "$SHARED"; fi
  if [[ -f "$BK/tps-radio-web.conf.previous" ]]; then
    cp -a "$BK/tps-radio-web.conf.previous" "$RADIO_CONF"
  else
    rm -f "$RADIO_CONF"
  fi
  nginx -t || true
  systemctl reload nginx || true
  echo 'ROLLBACK=DONE'
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT
fail(){ echo "FATAL=$*" >&2; return 1; }

echo 'CHG-RWEB01 — RADIO PUBLIC PLAYER/PORTAL CUTOVER'
echo "UTC=$TS"
echo "BACKUP=$BK"

echo '=== A. GATES ==='
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || fail 'GIT_WORKTREE_NOT_CLEAN'
[[ -f "$SHARED" ]] || fail 'SHARED_NGINX_CONF_MISSING'
[[ -f "$CAND_CONF" ]] || fail 'RADIO_NGINX_CANDIDATE_MISSING'
[[ -f "$PORTAL_ROOT/index.html" ]] || fail 'PORTAL_INDEX_MISSING'
[[ -f "$PLAYER_ROOT/index.html" ]] || fail 'PLAYER_INDEX_MISSING'
nginx -t

echo '=== B. REQUIRE FIVE HLS STREAMS BEFORE WEB CUTOVER ==='
for ch in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  code="$(curl -sSL --connect-timeout 2 --max-time 10 -o "$OUT/$ch.pre.m3u8" -w '%{http_code}' "http://127.0.0.1:8888/$ch/index.m3u8" || true)"
  echo "$ch local_hls_http=$code"
  [[ "$code" == 200 ]] || fail "LOCAL_HLS_NOT_200:$ch:$code"
  grep -q '^#EXTM3U' "$OUT/$ch.pre.m3u8" || fail "LOCAL_HLS_NOT_MANIFEST:$ch"
done

echo '=== C. BACKUP ==='
cp -a "$SHARED" "$BK/tps-9-emissoras.conf.previous"
[[ -f "$RADIO_CONF" ]] && cp -a "$RADIO_CONF" "$BK/tps-radio-web.conf.previous"
sha256sum "$SHARED" > "$BK/SHA256SUMS.before.txt"

echo '=== D. REMOVE ONLY RADIO HOSTNAMES FROM LEGACY SHARED SERVER_NAME LINES ==='
TMP_SHARED="$(mktemp /etc/nginx/conf.d/.tps-9-emissoras.CHG-RWEB01.XXXXXX)"
python3 - "$SHARED" "$TMP_SHARED" <<'PY'
import sys
src,dst=sys.argv[1:]
radio={
 'radio.studiosatweb.com.br','radioprincipal.studiosatweb.com.br','radiopop.studiosatweb.com.br',
 'radiorock.studiosatweb.com.br','radioclassicas.studiosatweb.com.br','radiocountry.studiosatweb.com.br',
 'www.radio.studiosatweb.com.br','www.radioprincipal.studiosatweb.com.br','www.radiopop.studiosatweb.com.br',
 'www.radiorock.studiosatweb.com.br','www.radioclassicas.studiosatweb.com.br','www.radiocountry.studiosatweb.com.br'
}
changed=0
out=[]
with open(src,encoding='utf-8') as f:
    for line in f:
        stripped=line.strip()
        if stripped.startswith('server_name ') and stripped.endswith(';'):
            indent=line[:len(line)-len(line.lstrip())]
            names=stripped[len('server_name '):-1].split()
            if any(n in radio for n in names):
                kept=[n for n in names if n not in radio]
                if not kept:
                    raise SystemExit('would create empty server_name')
                line=indent+'server_name '+' '.join(kept)+';\n'
                changed += 1
        out.append(line)
if changed != 4:
    raise SystemExit(f'expected 4 shared server_name changes, got {changed}')
text=''.join(out)
# TV identities must remain in the legacy blocks.
for required in ('tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br','tvteens.studiosatweb.com.br','www.tvteens.studiosatweb.com.br'):
    if required not in text:
        raise SystemExit(f'missing preserved TV hostname: {required}')
with open(dst,'w',encoding='utf-8') as f:
    f.write(text)
print('SHARED_SERVER_NAME_PATCHES=4')
print('TV_HOSTNAMES_PRESERVED=PASS')
PY

install -o root -g root -m 0644 "$TMP_SHARED" "$SHARED"
rm -f "$TMP_SHARED"
install -o root -g root -m 0644 "$CAND_CONF" "$RADIO_CONF"
MUTATED=1

echo '=== E. NGINX TEST + RELOAD ==='
nginx -t
systemctl reload nginx
sleep 2
systemctl is-active --quiet nginx || fail 'NGINX_NOT_ACTIVE_AFTER_RELOAD'
echo 'NGINX_RELOAD=PASS'

echo '=== F. PLAYER + PORTAL ROOTS ==='
player_code="$(curl -ksS --resolve radio.studiosatweb.com.br:443:127.0.0.1 -o "$OUT/player.html" -w '%{http_code}' https://radio.studiosatweb.com.br/)"
portal_code="$(curl -ksS --resolve www.radio.studiosatweb.com.br:443:127.0.0.1 -o "$OUT/portal.html" -w '%{http_code}' https://www.radio.studiosatweb.com.br/)"
echo "player_http=$player_code portal_http=$portal_code"
[[ "$player_code" == 200 ]] || fail "PLAYER_HTTP:$player_code"
[[ "$portal_code" == 200 ]] || fail "PORTAL_HTTP:$portal_code"
grep -q 'Radio Studio Sat — Player' "$OUT/player.html" || fail 'PLAYER_CONTENT_MISMATCH'
grep -q '<title>Radio Studio Sat</title>' "$OUT/portal.html" || fail 'PORTAL_CONTENT_MISMATCH'
echo 'PLAYER_ROOT=PASS'
echo 'PORTAL_ROOT=PASS'

echo '=== G. FIVE PUBLIC HLS PATHS THROUGH NEW RADIO BLOCK ==='
for ch in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  code="$(curl -ksSL --resolve radio.studiosatweb.com.br:443:127.0.0.1 --connect-timeout 3 --max-time 12 -o "$OUT/$ch.public.m3u8" -w '%{http_code}' "https://radio.studiosatweb.com.br/$ch/index.m3u8" || true)"
  echo "$ch public_hls_http=$code"
  [[ "$code" == 200 ]] || fail "PUBLIC_HLS_NOT_200:$ch:$code"
  grep -q '^#EXTM3U' "$OUT/$ch.public.m3u8" || fail "PUBLIC_HLS_NOT_MANIFEST:$ch"
done

echo '=== H. TV HOSTS STILL ROUTED ==='
for host in tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br; do
  code="$(curl -ksS --resolve "$host:443:127.0.0.1" -o /dev/null -w '%{http_code}' "https://$host/" || true)"
  echo "$host HTTP=$code"
  [[ "$code" =~ ^(200|301|302|403|404)$ ]] || fail "TV_HOST_UNREACHABLE:$host:$code"
done

echo '=== I. RESULT ==='
sha256sum "$SHARED" "$RADIO_CONF" | tee "$OUT/nginx.sha256"
echo 'CHG_RWEB01_RESULT=PASS'
echo 'RADIO_PLAYER_PUBLIC=PASS'
echo 'RADIO_PORTAL_PUBLIC=PASS'
echo 'FIVE_RADIO_HLS_PUBLIC=PASS'
echo 'TV_SERVER_NAMES_PRESERVED=PASS'
echo 'TV_SERVICE_RESTARTS=0'
echo "BACKUP=$BK"
trap - EXIT
