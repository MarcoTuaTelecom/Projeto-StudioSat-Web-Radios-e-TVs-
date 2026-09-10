#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo 'FATAL=RUN_AS_ROOT'; exit 1
fi

REPO=${REPO:-/root/Projeto-StudioSat-Web-Radios-e-TVs-}
PORTAL_SRC="$REPO/candidates/CHG-RWEB01/portal/index.html"
PLAYER_SRC="$REPO/candidates/CHG-RWEB01/player/index.html"
PORTAL_ROOT=/var/www/studiosat-radio-portal
PLAYER_ROOT=/var/www/studiosat-radio-player
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/studiosat/CHG-RWEB01/$TS

[[ -f "$PORTAL_SRC" ]] || { echo 'FATAL=PORTAL_CANDIDATE_MISSING'; exit 1; }
[[ -f "$PLAYER_SRC" ]] || { echo 'FATAL=PLAYER_CANDIDATE_MISSING'; exit 1; }

mkdir -p "$BACKUP" "$PORTAL_ROOT" "$PLAYER_ROOT"

[[ -f "$PORTAL_ROOT/index.html" ]] && cp -a "$PORTAL_ROOT/index.html" "$BACKUP/portal.previous.html"
[[ -f "$PLAYER_ROOT/index.html" ]] && cp -a "$PLAYER_ROOT/index.html" "$BACKUP/player.previous.html"

install -o root -g root -m 0644 "$PORTAL_SRC" "$PORTAL_ROOT/index.html"
install -o root -g root -m 0644 "$PLAYER_SRC" "$PLAYER_ROOT/index.html"

cmp -s "$PORTAL_SRC" "$PORTAL_ROOT/index.html" || { echo 'FATAL=PORTAL_COPY_MISMATCH'; exit 1; }
cmp -s "$PLAYER_SRC" "$PLAYER_ROOT/index.html" || { echo 'FATAL=PLAYER_COPY_MISMATCH'; exit 1; }

printf 'PORTAL_ROOT=%s\n' "$PORTAL_ROOT"
printf 'PLAYER_ROOT=%s\n' "$PLAYER_ROOT"
printf 'PORTAL_SHA='; sha256sum "$PORTAL_ROOT/index.html" | awk '{print $1}'
printf 'PLAYER_SHA='; sha256sum "$PLAYER_ROOT/index.html" | awk '{print $1}'
printf 'BACKUP=%s\n' "$BACKUP"
echo 'ISOLATED_STATIC_DEPLOY=PASS'
echo 'SHARED_TV_ROOTS_TOUCHED=NO'
echo 'NGINX_CHANGED=NO'
echo 'NEXT=Patch explicit Radio NGINX server blocks after inspecting the active shared config and certificate paths.'
