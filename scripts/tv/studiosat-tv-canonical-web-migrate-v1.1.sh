#!/usr/bin/env bash
# Nome: studiosat-tv-canonical-web-migrate-v1.1.sh
# Versão: 1.1
# Owner: TV + Core
# Safety class: production-change (NGINX/web only; no FFmpeg/MediaMTX restart)
# Change ID: CHG-TV-CANON-001
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CAND="$REPO/candidates/CHG-TV-CANON-001"
NGINX_SRC="$CAND/studiosat-tv.conf"
PLAYER_SRC="$CAND/index.html"
NGINX_DST="/etc/nginx/conf.d/studiosat-tv.conf"
WEBROOT="/var/www/studiosat-tv/current"
INDEX="$WEBROOT/index.html"
LOCK="/run/lock/studiosat-production-change.lock"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TV-CANON-001-WEB-$TS"
BACKUP="/var/backups/studiosat/CHG-TV-CANON-001/$TS"
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
TV_HOSTS=(
 tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br
 tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br
 tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br
 tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br
 tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br
)
MUTATED=0
INDEX_EXISTED=0
OWNERS_TAR=0

die(){ echo "FATAL=$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }

for c in git systemctl curl jq nginx sha256sum awk grep flock install cp mv rm mkdir find sort xargs diff tar date python3 basename head; do
  have "$c" || die "MISSING_TOOL:$c"
done
[[ ${EUID:-$(id -u)} -eq 0 ]] || die RUN_AS_ROOT

cd "$REPO"
git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die GIT_NOT_SYNCED
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die GIT_TRACKED_WORKTREE_DIRTY
[[ -f "$NGINX_SRC" && -f "$PLAYER_SRC" ]] || die CANDIDATE_MISSING
[[ -f /etc/letsencrypt/live/studiosatweb-completo/fullchain.pem ]] || die TLS_CERT_MISSING
[[ -f /etc/letsencrypt/live/studiosatweb-completo/privkey.pem ]] || die TLS_KEY_MISSING
bash -n "$0"

mkdir -p "$OUT" "$BACKUP"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>"$LOCK"
flock -n 9 || die ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK
jobs="$(systemctl list-jobs --no-legend 2>/dev/null || true)"
[[ -z "$jobs" ]] || { printf '%s\n' "$jobs" > "$OUT/systemd-jobs.txt"; die SYSTEMD_JOB_IN_PROGRESS; }

MTX_PRE="$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)"
[[ "$MTX_PRE" =~ ^[1-9][0-9]*$ ]] || die MEDIAMTX_NOT_RUNNING
: > "$OUT/radio.pre.tsv"
for st in "${RADIOS[@]}"; do
  unit="tps-${st}-playout.service"
  [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == active ]] || die "RADIO_NOT_ACTIVE:$st"
  pid="$(systemctl show "$unit" -p MainPID --value)"
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
  key="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$key.pre.sha256"
done
echo RADIO_BASELINE_PRE=PASS

nginx -t > "$OUT/nginx-pre-test.txt" 2>&1 || die NGINX_PRETEST_FAIL
nginx -T > "$OUT/nginx-T.pre.txt" 2>&1 || die NGINX_T_PRE_FAIL

if ! python3 - "$OUT/nginx-T.pre.txt" "$OUT/tv-owners.tsv" "$NGINX_DST" <<'PY'
import re,sys
src,out,canonical=sys.argv[1:4]
tv={
'tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br','tvkidsweb.studiosatweb.com.br','www.tvkidsweb.studiosatweb.com.br',
'tvteens.studiosatweb.com.br','www.tvteens.studiosatweb.com.br','tvviva.studiosatweb.com.br','www.tvviva.studiosatweb.com.br',
'tvmaisjovem.studiosatweb.com.br','www.tvmaisjovem.studiosatweb.com.br'}
radio={'radio.studiosatweb.com.br','www.radio.studiosatweb.com.br','radioprincipal.studiosatweb.com.br','www.radioprincipal.studiosatweb.com.br','radiopop.studiosatweb.com.br','www.radiopop.studiosatweb.com.br','radiorock.studiosatweb.com.br','www.radiorock.studiosatweb.com.br','radioclassicas.studiosatweb.com.br','www.radioclassicas.studiosatweb.com.br','radiocountry.studiosatweb.com.br','www.radiocountry.studiosatweb.com.br'}
cur=None;owners={}
for line in open(src,encoding='utf-8',errors='replace'):
    m=re.match(r'^# configuration file (.+):$',line.rstrip('\n'))
    if m:
        cur=m.group(1);continue
    if cur and 'server_name' in line:
        for h in tv:
            if h in line: owners.setdefault(cur,set()).add(h)
bad=[];rows=[]
for p,matched in sorted(owners.items()):
    if p==canonical:
        rows.append((p,'CANONICAL_EXISTING',','.join(sorted(matched))));continue
    try: text=open(p,encoding='utf-8',errors='replace').read()
    except OSError as e:
        bad.append(f'{p}:unreadable:{e}');continue
    names=[]
    for m in re.finditer(r'\bserver_name\s+([^;]+);',text,re.S): names+=m.group(1).split()
    foreign=[n for n in names if n not in tv and n not in {'_','""'}]
    radio_hits=sorted(set(names)&radio)
    if radio_hits: bad.append(f'{p}:contains_radio:{",".join(radio_hits)}')
    elif foreign: bad.append(f'{p}:contains_non_tv:{",".join(sorted(set(foreign)))}')
    else: rows.append((p,'RETIRE_TV_ONLY',','.join(sorted(matched))))
if bad:
    print('\n'.join(bad),file=sys.stderr);raise SystemExit(2)
with open(out,'w',encoding='utf-8') as f:
    for row in rows:f.write('\t'.join(row)+'\n')
PY
then
  die TV_OWNER_CLASSIFICATION_FAILED
fi

echo ACTIVE_TV_OWNERS_BEFORE:
cat "$OUT/tv-owners.tsv" || true
: > "$OUT/retire-files.txt"
while IFS=$'\t' read -r path action hosts; do
  [[ -n "${path:-}" ]] || continue
  [[ "$action" == RETIRE_TV_ONLY ]] && printf '%s\n' "$path" >> "$OUT/retire-files.txt"
done < "$OUT/tv-owners.tsv"
mapfile -t RETIRE < "$OUT/retire-files.txt"

BACKUP_PATHS=()
for f in "${RETIRE[@]}"; do [[ -n "$f" ]] && BACKUP_PATHS+=("$f"); done
if [[ -e "$NGINX_DST" || -L "$NGINX_DST" ]]; then BACKUP_PATHS+=("$NGINX_DST"); fi
if ((${#BACKUP_PATHS[@]})); then
  tar -czPf "$BACKUP/nginx-tv-owners.before.tar.gz" "${BACKUP_PATHS[@]}"
  OWNERS_TAR=1
fi
if [[ -f "$INDEX" ]]; then INDEX_EXISTED=1; cp -a "$INDEX" "$BACKUP/index.html.before"; fi
echo TV_OWNER_CLASSIFICATION=PASS

rollback(){
  set +e
  echo '=== ROLLBACK CHG-TV-CANON-001 WEB ==='
  rm -f "$NGINX_DST"
  for f in "${RETIRE[@]}"; do [[ -n "$f" ]] && rm -f "$f"; done
  if (( OWNERS_TAR == 1 )); then tar -xzPf "$BACKUP/nginx-tv-owners.before.tar.gz"; fi
  if (( INDEX_EXISTED == 1 )); then
    install -d -o www-data -g www-data -m 0755 "$WEBROOT"
    cp -a "$BACKUP/index.html.before" "$INDEX"
  else
    rm -f "$INDEX"
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  echo ROLLBACK=DONE
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

MUTATED=1
for f in "${RETIRE[@]}"; do [[ -n "$f" ]] && rm -f "$f"; done
install -d -o www-data -g www-data -m 0755 "$WEBROOT"
install -o www-data -g www-data -m 0644 "$PLAYER_SRC" "$INDEX.new-$TS"
mv -f "$INDEX.new-$TS" "$INDEX"
install -o root -g root -m 0644 "$NGINX_SRC" "$NGINX_DST"

nginx -t | tee "$OUT/nginx-post-test.txt"
nginx -T > "$OUT/nginx-T.post.txt" 2>&1 || die NGINX_T_POST_FAIL
if ! python3 - "$OUT/nginx-T.post.txt" "$NGINX_DST" <<'PY'
import re,sys
src,expected=sys.argv[1:3]
tv=['tvkids.studiosatweb.com.br','www.tvkids.studiosatweb.com.br','tvkidsweb.studiosatweb.com.br','www.tvkidsweb.studiosatweb.com.br','tvteens.studiosatweb.com.br','www.tvteens.studiosatweb.com.br','tvviva.studiosatweb.com.br','www.tvviva.studiosatweb.com.br','tvmaisjovem.studiosatweb.com.br','www.tvmaisjovem.studiosatweb.com.br']
cur=None;owners={h:set() for h in tv}
for line in open(src,encoding='utf-8',errors='replace'):
    m=re.match(r'^# configuration file (.+):$',line.rstrip('\n'))
    if m:cur=m.group(1);continue
    if cur and 'server_name' in line:
        for h in tv:
            if h in line:owners[h].add(cur)
bad={h:sorted(v) for h,v in owners.items() if v!={expected}}
if bad:
    for h,v in bad.items():print(h,':',','.join(v),file=sys.stderr)
    raise SystemExit(1)
PY
then
  die TV_HOST_OWNERSHIP_NOT_CANONICAL
fi

systemctl reload nginx
sleep 2

declare -A STATION_BY_HOST=(
 [tvkids.studiosatweb.com.br]=tvkids [www.tvkids.studiosatweb.com.br]=tvkids
 [tvkidsweb.studiosatweb.com.br]=tvkids [www.tvkidsweb.studiosatweb.com.br]=tvkids
 [tvteens.studiosatweb.com.br]=tvteens [www.tvteens.studiosatweb.com.br]=tvteens
 [tvviva.studiosatweb.com.br]=tvviva [www.tvviva.studiosatweb.com.br]=tvviva
 [tvmaisjovem.studiosatweb.com.br]=tvmaisjovem [www.tvmaisjovem.studiosatweb.com.br]=tvmaisjovem
)
: > "$OUT/tv-root-state.tsv"
for h in "${TV_HOSTS[@]}"; do
  st="${STATION_BY_HOST[$h]}"
  hdr="$OUT/$h.headers";body="$OUT/$h.root"
  code="$(curl -kLsS --resolve "$h:443:127.0.0.1" -D "$hdr" --connect-timeout 4 --max-time 12 -o "$body" -w '%{http_code}' "https://$h/" || true)"
  [[ "$code" == 200 ]] || die "TV_ROOT_FAIL:$h:$code"
  grep -qi '^X-StudioSat-TV-Owner: canonical-v1' "$hdr" || die "TV_OWNER_HEADER_FAIL:$h"
  grep -qi "^X-StudioSat-TV-Station: $st" "$hdr" || die "TV_STATION_HEADER_FAIL:$h"
  grep -q 'Studio Sat TV — Ao Vivo' "$body" || die "TV_PLAYER_BODY_FAIL:$h"
  printf '%s\t%s\tPASS\n' "$h" "$st" >> "$OUT/tv-root-state.tsv"
done

paths="$(curl -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:9997/v3/paths/list 2>/dev/null || echo '{"items":[]}')"
: > "$OUT/tv-stream-state.tsv"
for st in "${TVS[@]}"; do
  ready="$(jq -r --arg s "$st" '.items[]?|select(.name==$s)|.ready' <<<"$paths" | head -1)"
  [[ -n "$ready" ]] || ready=false
  if [[ "$ready" == true ]]; then
    case "$st" in
      tvkids) host=tvkidsweb.studiosatweb.com.br;;
      tvteens) host=tvteens.studiosatweb.com.br;;
      tvviva) host=tvviva.studiosatweb.com.br;;
      tvmaisjovem) host=tvmaisjovem.studiosatweb.com.br;;
    esac
    hls="$OUT/$st.m3u8"
    hc="$(curl -kLsS --resolve "$host:443:127.0.0.1" --max-time 15 -o "$hls" -w '%{http_code}' "https://$host/$st/index.m3u8" || true)"
    [[ "$hc" == 200 ]] && grep -q '^#EXTM3U' "$hls" || die "READY_STREAM_NOT_PUBLIC:$st:$hc"
    printf '%s\tREADY\tPUBLIC_HLS_PASS\n' "$st" >> "$OUT/tv-stream-state.tsv"
  else
    printf '%s\tNOT_READY\tWEB_CANONICAL_ONLY\n' "$st" >> "$OUT/tv-stream-state.tsv"
  fi
done

[[ "$(systemctl show tps-mediamtx.service -p MainPID --value 2>/dev/null || true)" == "$MTX_PRE" ]] || die MEDIAMTX_PID_CHANGED
while IFS=$'\t' read -r st pidpre shpre; do
  [[ "$(systemctl show "tps-${st}-playout.service" -p MainPID --value)" == "$pidpre" ]] || die "RADIO_PID_CHANGED:$st"
  [[ "$(sha "/srv/tpsmedia/repository/channels/$st/playlists/playlist.txt")" == "$shpre" ]] || die "RADIO_PLAYLIST_CHANGED:$st"
done < "$OUT/radio.pre.tsv"
while IFS=$'\t' read -r f spre; do
  [[ "$(sha "$f")" == "$spre" ]] || die "RADIO_NGINX_CHANGED:$f"
done < "$OUT/radio-nginx.pre.tsv"
for d in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  key="$(basename "$d")"
  find "$d" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/$key.post.sha256"
  diff -u "$OUT/$key.pre.sha256" "$OUT/$key.post.sha256" > "$OUT/$key.diff" || die "RADIO_WEBROOT_CHANGED:$d"
done

trap - EXIT
printf 'canonical_nginx_sha=%s\n' "$(sha "$NGINX_DST")"
printf 'canonical_player_sha=%s\n' "$(sha "$INDEX")"
echo CHG_TV_CANON_001_WEB=PASS
echo SINGLE_TV_NGINX_OWNER=PASS
echo TV_FULLSCREEN_PLAYER_V3=PASS
echo ALL_5_RADIOS_PRESERVED=PASS
echo MEDIAMTX_PRESERVED=PASS
echo "stream_state=$OUT/tv-stream-state.tsv"
echo "evidence=$OUT"
