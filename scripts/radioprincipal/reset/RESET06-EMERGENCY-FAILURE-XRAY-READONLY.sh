#!/usr/bin/env bash
set -Eeuo pipefail
OUT="${1:-/root/RESET06-EMERGENCY-DIRECT-FAILURE-$(date -u +%Y%m%dT%H%M%SZ).txt}"
exec > >(tee "$OUT") 2>&1

sec(){ echo; echo "================================================================"; echo "$1"; echo "================================================================"; }

sec "IDENTITY"
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"
echo "READ_ONLY=YES"
echo "REPORT=$OUT"

sec "SERVICE MATRIX"
for u in \
  tps-mediamtx.service \
  nginx.service \
  studiosat-radioprincipal-selector.service \
  studiosat-radioprincipal-shadow-ns1.service \
  studiosat-radioprincipal-emergency-direct.service
do
  echo "--- $u ---"
  systemctl show "$u" \
    -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState \
    -p MainPID -p NRestarts -p Result -p ExecMainStatus -p ExecStart \
    2>&1 || true
done

sec "EMERGENCY DIRECT UNIT"
systemctl cat studiosat-radioprincipal-emergency-direct.service 2>&1 || true

sec "EMERGENCY DIRECT STATUS"
systemctl status studiosat-radioprincipal-emergency-direct.service --no-pager -l 2>&1 || true

sec "EMERGENCY DIRECT JOURNAL"
journalctl -u studiosat-radioprincipal-emergency-direct.service \
  --since '90 minutes ago' -o short-iso-precise --no-pager 2>&1 | tail -500 || true

sec "SELECTOR STATUS / JOURNAL"
systemctl status studiosat-radioprincipal-selector.service --no-pager -l 2>&1 || true
journalctl -u studiosat-radioprincipal-selector.service \
  --since '30 minutes ago' -o short-iso-precise --no-pager 2>&1 |
  grep -Ei 'Switch to|Feeding stopped|New metadata|Error|radioprincipal_rb_harbor|emergency_blank|ns1' |
  tail -300 || true

sec "SHADOW STATUS / JOURNAL"
systemctl status studiosat-radioprincipal-shadow-ns1.service --no-pager -l 2>&1 || true
journalctl -u studiosat-radioprincipal-shadow-ns1.service \
  --since '30 minutes ago' -o short-iso-precise --no-pager 2>&1 | tail -300 || true

sec "SOCKETS"
ss -ltnp 2>/dev/null | grep -E ':1935\b|:8888\b|:9997\b|:18005\b' || true
echo "--- established ---"
ss -tnp state established 2>/dev/null | grep -E ':1935\b|:18005\b' || true

sec "MEDIAMTX PATHS"
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb; do
  echo "--- $p ---"
  timeout 5 curl -fsS "http://127.0.0.1:9997/v3/paths/get/$p" 2>&1 || true
  echo
done

sec "RTMP PROBES"
for p in radioprincipal radioprincipal-ns1 radioprincipal-rb; do
  echo "--- $p ---"
  timeout 8 ffprobe -v error -rw_timeout 5000000 \
    -show_entries stream=codec_name,codec_type,sample_rate,channels \
    -of default=nw=1 "rtmp://127.0.0.1:1935/$p" 2>&1 || echo "PROBE_FAIL=$p"
done

sec "PUBLIC HLS"
timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>&1 | head -40 || echo "HLS_PROBE_FAIL=YES"

sec "CURRENT SELECTOR CONFIG"
sha256sum /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true
grep -nE 'input\.harbor|input\.rtmp|playlist\(|blank\(|program = fallback|\[rb|output\.url|rtmp://127\.0\.0\.1:1935/radioprincipal' \
  /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true

sec "FFMPEG PROCESSES"
ps -eo pid,ppid,user,lstart,stat,%cpu,%mem,args --width 500 |
  grep -E '[f]fmpeg|radioprincipal' || true

sec "RESULT"
echo "RESULTADO=RESET06_EMERGENCY_FAILURE_XRAY_COMPLETE"
echo "REPORT=$OUT"
