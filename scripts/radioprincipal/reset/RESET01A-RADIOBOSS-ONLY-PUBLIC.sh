#!/usr/bin/env bash
set -Eeuo pipefail

SVC='studiosat-radioprincipal-selector.service'
CFG='/etc/studiosat/radioprincipal-selector.liq'
ENV='/etc/studiosat/radioprincipal-selector.env'
BK="/root/studiosat-backups/RESET01A-$(date -u +%Y%m%dT%H%M%SZ)"

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }
mkdir -p "$BK"
cp -a "$CFG" "$BK/radioprincipal-selector.liq.before"
systemctl cat "$SVC" >"$BK/selector.service.before.txt" 2>&1 || true

echo '===== RESET-01A RADIOBOSS-ONLY PUBLIC BASELINE ====='
echo "BACKUP=$BK"

echo '===== PRECHECK ====='
systemctl is-active "$SVC"
ss -ltnp | grep ':18005' || { echo 'ERRO=HARBOR_NOT_LISTENING'; exit 20; }

if ! grep -Fq '[rb, local, security]' "$CFG"; then
  echo 'ERRO=EXPECTED_SELECTOR_PATTERN_NOT_FOUND'
  grep -nE 'fallback|\[rb|radioprincipal_local_grade' "$CFG" || true
  exit 21
fi

echo '===== PATCH ====='
python3 - "$CFG" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
old='[rb, local, security]'
if s.count(old)!=1:
    raise SystemExit('selector pattern count != 1')
p.write_text(s.replace(old,'[rb, security]',1))
PY

echo '===== VALIDATE CONFIG ====='
set -a
. "$ENV"
set +a
/usr/bin/liquidsoap --check "$CFG"
echo 'LIQUIDSOAP_CHECK=OK'

echo '===== RESTART SELECTOR ONCE ====='
systemctl restart "$SVC"

listen=0
for i in $(seq 1 20); do
  sleep 1
  if ss -ltn 2>/dev/null | grep -q ':18005'; then
    listen=1
    echo "HARBOR_LISTEN=YES AFTER=${i}s"
    break
  fi
done
if [ "$listen" -ne 1 ]; then
  echo 'ERRO=HARBOR_DID_NOT_RETURN'
  cp -a "$BK/radioprincipal-selector.liq.before" "$CFG"
  systemctl restart "$SVC" || true
  echo 'ROLLBACK=APPLIED'
  exit 30
fi

echo '===== WAIT RADIOBOSS ====='
est=0
for i in $(seq 1 60); do
  if ss -tn state established 2>/dev/null | grep -q ':18005'; then
    est=1
    echo "HARBOR_ESTABLISHED=YES AFTER=${i}s"
    break
  fi
  [ $((i%10)) -eq 0 ] && echo "WAIT_RADIOBOSS=${i}s"
  sleep 1
done

echo '===== PUBLIC RTMP ====='
pub=0
for i in $(seq 1 20); do
  if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0 \
      rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q .; then
    pub=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

echo '===== SOURCE ====='
journalctl -u "$SVC" --since '3 minutes ago' --no-pager |
  grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_emergency_blank|New metadata|Feeding stopped|Error while reading' |
  tail -120 || true

latest="$(journalctl -u "$SVC" --since '3 minutes ago' --no-pager 2>/dev/null | grep 'Switch to' | tail -1 || true)"
echo "LATEST_SWITCH=$latest"

echo '===== HLS ====='
hls=0
if timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 | head -20; then
  hls=1
  echo 'PUBLIC_HLS=READY'
else
  echo 'PUBLIC_HLS=NOT_READY'
fi

echo '===== RESULT ====='
echo 'LOCAL_GRADE_PUBLIC_FALLBACK=DISABLED'
echo 'PUBLIC_FALLBACK=RADIOBOSS_THEN_BLANK'
if [ "$est" -eq 1 ] && echo "$latest" | grep -q 'radioprincipal_rb_harbor' && [ "$pub" -eq 1 ] && [ "$hls" -eq 1 ]; then
  echo 'PUBLIC_SOURCE=RADIOBOSS'
  echo 'RESULTADO=RESET01A_RADIOBOSS_ON_AIR'
else
  echo 'PUBLIC_SOURCE=NOT_CONFIRMED_RADIOBOSS'
  echo 'RESULTADO=RESET01A_BASELINE_APPLIED_BUT_RADIOBOSS_NEEDS_LIVE_RECOVERY'
  exit 40
fi
