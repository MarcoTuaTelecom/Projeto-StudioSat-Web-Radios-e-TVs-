#!/usr/bin/env bash
# Studio Sat RadioPrincipal C18 full forensic XRAY orchestrator.
# Runs the approved canonical XRAY V2, then the C18 incident supplement.
# No production service mutation. Only writes diagnostic files under /root.
set -Eeuo pipefail
REPO='MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-'
BRANCH='reorg/project-context-v2'
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
BASE_RUNNER='/root/RUN-RADIOPRINCIPAL-BASELINE.sh'
SUP='/root/C18-POSTMORTEM-SUPPLEMENT-READONLY.sh'
OBSERVE_SECONDS="${OBSERVE_SECONDS:-60}"

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

echo '============================================================'
echo ' STUDIO SAT - RADIOPRINCIPAL C18 FULL FORENSIC XRAY'
echo ' READ-ONLY PRODUCTION / NO DOWNTIME'
echo '============================================================'
echo "UTC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "OBSERVE_SECONDS=$OBSERVE_SECONDS"

echo '===== DOWNLOAD / SYNTAX ====='
curl -fsSL "$BASE_URL/scripts/radioprincipal/RUN-RADIOPRINCIPAL-BASELINE.sh" -o "$BASE_RUNNER"
curl -fsSL "$BASE_URL/scripts/radioprincipal/v2/C18-POSTMORTEM-SUPPLEMENT-READONLY.sh" -o "$SUP"
chmod 700 "$BASE_RUNNER" "$SUP"
bash -n "$BASE_RUNNER"
bash -n "$SUP"
echo 'SYNTAX=OK'

echo '===== CANONICAL XRAY V2 ====='
set +e
OBSERVE_SECONDS="$OBSERVE_SECONDS" bash "$BASE_RUNNER"
BASE_RC=$?
set -e
BASE_REPORT="$(find /root -maxdepth 1 -type f -name 'XRAY-RADIOPRINCIPAL-NS1-V2-*.txt' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
echo "BASE_RC=$BASE_RC"
echo "BASE_REPORT=${BASE_REPORT:-NAO_LOCALIZADO}"

SUP_REPORT="/root/XRAY-RADIOPRINCIPAL-C18-SUPPLEMENT-$(date -u +%Y%m%dT%H%M%SZ).txt"
echo '===== C18 INCIDENT SUPPLEMENT ====='
bash "$SUP" "$SUP_REPORT"

echo '===== FINAL ====='
echo "BASE_REPORT=${BASE_REPORT:-NAO_LOCALIZADO}"
echo "SUPPLEMENT_REPORT=$SUP_REPORT"
[ -f "$BASE_REPORT" ] && echo "BASE_SHA256=$(sha256sum "$BASE_REPORT" | awk '{print $1}')" || true
[ -f "$SUP_REPORT" ] && echo "SUPPLEMENT_SHA256=$(sha256sum "$SUP_REPORT" | awk '{print $1}')" || true
echo 'NO_PRODUCTION_MUTATION=YES'
echo 'RESULTADO=C18_FULL_XRAY_COMPLETE'
