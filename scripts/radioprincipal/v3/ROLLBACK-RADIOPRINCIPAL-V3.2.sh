#!/usr/bin/env bash
set -Eeuo pipefail
V32='studiosat-radioprincipal-v32-core.service'
V31='studiosat-radioprincipal-v31-core.service'
systemctl disable --now "$V32" 2>/dev/null || true
systemctl enable --now "$V31"
echo "RESULTADO=V32_ROLLBACK_TO_V31"
