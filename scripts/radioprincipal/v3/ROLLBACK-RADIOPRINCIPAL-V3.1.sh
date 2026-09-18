#!/usr/bin/env bash
set -Eeuo pipefail
CORE='studiosat-radioprincipal-v31-core.service'
ICE='studiosat-radioprincipal-v31-icecast.service'
SEL='studiosat-radioprincipal-selector.service'
systemctl disable --now "$CORE" 2>/dev/null || true
systemctl disable --now "$ICE" 2>/dev/null || true
systemctl enable "$SEL" 2>/dev/null || true
systemctl restart "$SEL"
echo "RESULTADO=V31_ROLLBACK_TO_SELECTOR"
