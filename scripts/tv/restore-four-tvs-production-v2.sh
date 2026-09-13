#!/usr/bin/env bash
set -Eeuo pipefail
cat >&2 <<'EOF'
FATAL=SUPERSEDED_SCRIPT
Este restore incremental foi aposentado.
Use somente a arquitetura canonica em duas fases:
1) scripts/tv/studiosat-tv-canonical-web-migrate-v1.1.sh
2) scripts/tv/studiosat-tv-canonical-runtime-migrate-v1.sh
EOF
exit 64
