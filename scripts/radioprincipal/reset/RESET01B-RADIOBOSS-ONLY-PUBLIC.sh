#!/usr/bin/env bash
set -Eeuo pipefail

SVC='studiosat-radioprincipal-selector.service'
CFG='/etc/studiosat/radioprincipal-selector.liq'
ENV='/etc/studiosat/radioprincipal-selector.env'
BK="/root/studiosat-backups/RESET01B-$(date -u +%Y%m%dT%H%M%SZ)"

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }
mkdir -p "$BK"
cp -a "$CFG" "$BK/radioprincipal-selector.liq.before"
systemctl cat "$SVC" >"$BK/selector.service.before.txt" 2>&1 || true

echo '=============================================================='
echo ' RESET-01B - RADIOBOSS ONLY PUBLIC SELECTOR'
echo '=============================================================='
echo "BACKUP=$BK"

echo '===== PRECHECK SERVICE / HARBOR ====='
systemctl is-active "$SVC"
ss -ltnp | grep ':18005' || { echo 'ERRO=HARBOR_NOT_LISTENING'; exit 20; }

if ! ss -tn state established 2>/dev/null | grep -q ':18005'; then
  echo 'ERRO=RADIOBOSS_NOT_ESTABLISHED_BEFORE_CHANGE'
  echo 'NO_CONFIG_CHANGE=YES'
  echo 'ACTION=RECOVER_WINDOWS_LIVE_TUNNEL'
  exit 21
fi
echo 'RADIOBOSS_ESTABLISHED_BEFORE_CHANGE=YES'

echo '===== CURRENT FALLBACK ====='
grep -nE 'security = blank|program = fallback|\[rb' "$CFG" || true

echo '===== BUILD CANDIDATE CONFIG ====='
CAND="$BK/radioprincipal-selector.candidate.liq"
python3 - "$CFG" "$CAND" <<'PY'
from pathlib import Path
import re,sys

src=Path(sys.argv[1]).read_text()
out=src

if not re.search(r'(?m)^\s*security\s*=\s*blank\s*\(', out):
    marker=re.search(r'(?m)^\s*program\s*=\s*fallback\s*\(', out)
    if not marker:
        raise SystemExit("ERRO=PROGRAM_FALLBACK_NOT_FOUND")
    block='''security = blank(
  id="radioprincipal_emergency_blank"
)

'''
    out=out[:marker.start()]+block+out[marker.start():]

patterns=[
    r'\[\s*rb\s*,\s*local\s*,\s*security\s*\]',
    r'\[\s*rb\s*,\s*local\s*\]',
    r'\[\s*rb\s*,\s*security\s*\]'
]
matched=None
for pat in patterns:
    if re.search(pat,out):
        matched=pat
        out=re.sub(pat,'[rb, security]',out,count=1)
        break

if matched is None:
    raise SystemExit("ERRO=SUPPORTED_FALLBACK_PATTERN_NOT_FOUND")

if 'radioprincipal_rb_harbor' not in out:
    raise SystemExit("ERRO=RB_SOURCE_MISSING")
if 'radioprincipal_emergency_blank' not in out:
    raise SystemExit("ERRO=SECURITY_SOURCE_MISSING")
if re.search(r'\[\s*rb\s*,\s*local',out):
    raise SystemExit("ERRO=LOCAL_STILL_IN_PUBLIC_FALLBACK")

Path(sys.argv[2]).write_text(out)
print("CANDIDATE_BUILD=OK")
PY

echo '===== CANDIDATE DIFF ====='
diff -u "$CFG" "$CAND" || true

echo '===== LIQUIDSOAP CHECK CANDIDATE ====='
set -a
. "$ENV"
set +a
if /usr/bin/liquidsoap --check "$CAND"; then
  echo 'LIQUIDSOAP_CHECK=OK'
else
  echo 'LIQUIDSOAP_CHECK=FAILED'
  echo 'PRODUCTION_UNCHANGED=YES'
  exit 22
fi

echo '===== INSTALL CONFIG ====='
cp -a "$CAND" "$CFG"
echo 'PUBLIC_FALLBACK_CONFIG=RB_THEN_SECURITY'

echo '===== RESTART SELECTOR ONCE ====='
if ! systemctl restart "$SVC"; then
  echo 'SELECTOR_RESTART=FAILED'
  cp -a "$BK/radioprincipal-selector.liq.before" "$CFG"
  systemctl restart "$SVC" || true
  echo 'ROLLBACK=APPLIED'
  exit 30
fi

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
  echo 'HARBOR_LISTEN=NO'
  cp -a "$BK/radioprincipal-selector.liq.before" "$CFG"
  systemctl restart "$SVC" || true
  echo 'ROLLBACK=APPLIED'
  exit 31
fi

echo '===== WAIT RADIOBOSS RECONNECT ====='
est=0
for i in $(seq 1 90); do
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
for i in $(seq 1 30); do
  if timeout 5 ffprobe -v error -rw_timeout 3000000 \
      -show_entries stream=codec_name -of csv=p=0 \
      rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q .; then
    pub=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

echo '===== SELECTOR EVENTS ====='
journalctl -u "$SVC" --since '5 minutes ago' --no-pager |
  grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_emergency_blank|radioprincipal_local_grade|New metadata|Feeding stopped|Error while reading' |
  tail -160 || true

latest="$(journalctl -u "$SVC" --since '5 minutes ago' --no-pager 2>/dev/null | grep 'Switch to' | tail -1 || true)"
echo "LATEST_SWITCH=$latest"

echo '===== VERIFY LOCAL REMOVED FROM FALLBACK ====='
grep -nE 'security = blank|program = fallback|\[rb' "$CFG" || true
if grep -Eq '\[\s*rb\s*,\s*local' "$CFG"; then
  echo 'ERRO=LOCAL_STILL_PUBLIC'
  exit 40
fi
echo 'LOCAL_GRADE_PUBLIC_FALLBACK=DISABLED'

echo '===== HLS ====='
hls=0
if timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 | head -20; then
  hls=1
  echo 'PUBLIC_HLS=READY'
else
  echo 'PUBLIC_HLS=NOT_READY'
fi

echo '===== RESULT ====='
echo 'PUBLIC_FALLBACK=RADIOBOSS_THEN_BLANK'
if [ "$est" -eq 1 ] && echo "$latest" | grep -q 'radioprincipal_rb_harbor' && [ "$pub" -eq 1 ] && [ "$hls" -eq 1 ]; then
  echo 'PUBLIC_SOURCE=RADIOBOSS'
  echo 'RESULTADO=RESET01B_RADIOBOSS_ON_AIR'
else
  echo 'PUBLIC_SOURCE=NOT_CONFIRMED_RADIOBOSS'
  echo 'RESULTADO=RESET01B_BASELINE_APPLIED_LIVE_NEEDS_RECOVERY'
  exit 41
fi
