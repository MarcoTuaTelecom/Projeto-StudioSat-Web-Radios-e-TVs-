#!/usr/bin/env bash
set -Eeuo pipefail
NEW='studiosat-radioprincipal-shadow-v4.service'
OLD='studiosat-radioprincipal-shadow-ns1.service'
systemctl disable --now "$NEW" 2>/dev/null || true
systemctl enable "$OLD" 2>/dev/null || true
systemctl restart "$OLD"
echo "RESULTADO=V4_SHADOW_ROLLBACK_TO_LEGACY"
