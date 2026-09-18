#!/usr/bin/env bash
set -Eeuo pipefail
CORE='studiosat-radioprincipal-v3-core.service'
ICE='studiosat-radioprincipal-v3-icecast.service'
SEL='studiosat-radioprincipal-selector.service'
systemctl disable --now "$CORE" 2>/dev/null || true
systemctl disable --now "$ICE" 2>/dev/null || true
systemctl enable "$SEL" 2>/dev/null || true
systemctl restart "$SEL"
echo "RESULTADO=V3_ROLLBACK_TO_SELECTOR"
