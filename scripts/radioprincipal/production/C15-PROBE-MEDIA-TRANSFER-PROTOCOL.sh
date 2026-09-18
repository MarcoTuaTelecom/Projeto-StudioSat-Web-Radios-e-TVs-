#!/usr/bin/env bash
set -euo pipefail
F='/opt/studiosat/radio-v2/media-transfer/server.py'
[ -r "$F" ] || { echo "ERRO=SERVER_PY_INACESSIVEL"; exit 1; }
echo '===== MEDIA TRANSFER ROUTES ====='
grep -nE 'do_(GET|POST|PUT)|/v1/|exists|upload|ingest|incoming|sha256|repository_index|Content-Length|multipart' "$F" | sed -n '1,260p'
echo '===== MEDIA TRANSFER UNIT ====='
systemctl cat studiosat-media-transfer.service
echo '===== NGINX 8789 CONTEXT ====='
nginx -T 2>/dev/null | grep -n -B8 -A12 '127\.0\.0\.1:8789' | sed -n '1,220p'
