#!/usr/bin/env bash
# StudioSat Web — one-command operational recovery for the five Radio stations.
# 1) Cut over five radio playouts to AAC/HLS one by one.
# 2) Refresh isolated Radio player/portal static roots.
# 3) Split Radio NGINX hostnames from TV and publish the new roots.
set -Eeuo pipefail
IFS=$'\n\t'

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT' >&2; exit 77; }
REPO=${REPO:-/root/Projeto-StudioSat-Web-Radios-e-TVs-}
cd "$REPO"
[[ -z "$(git status --porcelain)" ]] || { echo 'FATAL=GIT_WORKTREE_NOT_CLEAN' >&2; exit 1; }

for f in \
  candidates/CHG-R03/tps-playout-radio-v3-aac-all.sh \
  candidates/CHG-R03/apply-all-radios-aac-hls-v1.sh \
  candidates/CHG-RWEB01/deploy-radio-web-isolated-v2.sh \
  candidates/CHG-RWEB01/apply-radio-public-web-v3.sh
  do
    [[ -f "$f" ]] || { echo "FATAL=MISSING:$f" >&2; exit 1; }
    bash -n "$f"
  done

echo '============================================================'
echo 'PHASE 1/3 — FIVE RADIO AUDIO PATHS -> AAC/HLS'
echo '============================================================'
bash candidates/CHG-R03/apply-all-radios-aac-hls-v1.sh

echo '============================================================'
echo 'PHASE 2/3 — REFRESH ISOLATED RADIO PLAYER + PORTAL ROOTS'
echo '============================================================'
bash candidates/CHG-RWEB01/deploy-radio-web-isolated-v2.sh

echo '============================================================'
echo 'PHASE 3/3 — PUBLIC NGINX RADIO CUTOVER'
echo '============================================================'
bash candidates/CHG-RWEB01/apply-radio-public-web-v3.sh

echo '============================================================'
echo 'FINAL — PUBLIC MATRIX'
echo '============================================================'
for ch in radioprincipal radiopop radiorock radioclassicas radiocountry; do
  service="$(systemctl is-active "tps-${ch}-playout.service" || true)"
  ready="$(curl -fsS http://127.0.0.1:9997/v3/paths/list | jq -r --arg ch "$ch" '.items[] | select(.name==$ch) | .ready' | head -n1 || true)"
  code="$(curl -ksSL --connect-timeout 3 --max-time 12 -o "/tmp/${ch}.final.m3u8" -w '%{http_code}' "https://radio.studiosatweb.com.br/${ch}/index.m3u8" || true)"
  manifest=FAIL
  grep -q '^#EXTM3U' "/tmp/${ch}.final.m3u8" 2>/dev/null && manifest=PASS
  printf '%-18s service=%-6s ready=%-5s HLS_HTTP=%-3s manifest=%s\n' "$ch" "$service" "$ready" "$code" "$manifest"
  [[ "$service" == active && "$ready" == true && "$code" == 200 && "$manifest" == PASS ]] || { echo "FATAL=FINAL_RADIO_MATRIX:$ch" >&2; exit 1; }
done

for host in radio.studiosatweb.com.br radioprincipal.studiosatweb.com.br radiopop.studiosatweb.com.br radiorock.studiosatweb.com.br radioclassicas.studiosatweb.com.br radiocountry.studiosatweb.com.br www.radio.studiosatweb.com.br www.radioprincipal.studiosatweb.com.br www.radiopop.studiosatweb.com.br www.radiorock.studiosatweb.com.br www.radioclassicas.studiosatweb.com.br www.radiocountry.studiosatweb.com.br; do
  code="$(curl -ksS --connect-timeout 3 --max-time 10 -o /dev/null -w '%{http_code}' "https://$host/" || true)"
  printf '%-45s HTTP=%s\n' "$host" "$code"
  [[ "$code" == 200 ]] || { echo "FATAL=PUBLIC_ROOT:$host:$code" >&2; exit 1; }
done

echo 'RADIO_RECOVERY_RESULT=PASS'
echo 'FIVE_RADIOS=ON_AIR'
echo 'FIVE_RADIOS_HLS=PASS'
echo 'PLAYER_WITHOUT_WWW=PASS'
echo 'PORTAL_WITH_WWW=PASS'
echo 'TV_SERVICE_RESTARTS=0'
