#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo 'FATAL=RUN_AS_ROOT'; exit 1
fi

PORTAL_ROOT=${1:-}
PLAYER_ROOT=${2:-}
REPO=${REPO:-/root/Projeto-StudioSat-Web-Radios-e-TVs-}
PORTAL_SRC="$REPO/candidates/CHG-RWEB01/portal/index.html"
PLAYER_SRC="$REPO/candidates/CHG-RWEB01/player/index.html"
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="/var/backups/studiosat/CHG-RWEB01/$TS"

[[ -n "$PORTAL_ROOT" && -n "$PLAYER_ROOT" ]] || { echo 'USAGE: deploy-radio-web-v1.sh <www-root> <non-www-root>'; exit 2; }
[[ -f "$PORTAL_SRC" && -f "$PLAYER_SRC" ]] || { echo 'FATAL=CANDIDATE_MISSING'; exit 1; }
[[ -d "$PORTAL_ROOT" ]] || { echo "FATAL=PORTAL_ROOT_NOT_FOUND:$PORTAL_ROOT"; exit 1; }
[[ -d "$PLAYER_ROOT" ]] || { echo "FATAL=PLAYER_ROOT_NOT_FOUND:$PLAYER_ROOT"; exit 1; }

mkdir -p "$BACKUP"
for pair in "$PORTAL_ROOT/index.html:portal.previous.html" "$PLAYER_ROOT/index.html:player.previous.html"; do
  src=${pair%%:*}; dst=${pair##*:}
  [[ -f "$src" ]] && cp -a "$src" "$BACKUP/$dst"
done

install -o root -g root -m 0644 "$PORTAL_SRC" "$PORTAL_ROOT/index.html"
install -o root -g root -m 0644 "$PLAYER_SRC" "$PLAYER_ROOT/index.html"

nginx -t

printf 'PORTAL_SHA='; sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}'
printf 'PLAYER_SHA='; sha256sum "$PLAYER_ROOT/index.html" | awk '{print $1}'
echo "BACKUP=$BACKUP"
echo 'STATIC_FILES_DEPLOYED=PASS'
echo 'NGINX_RELOAD_REQUIRED=NO'
echo 'NOTE=Static index replacement only; no nginx reload was performed.'
