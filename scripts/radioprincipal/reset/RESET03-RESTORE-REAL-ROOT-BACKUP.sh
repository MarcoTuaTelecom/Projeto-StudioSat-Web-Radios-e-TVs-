#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SVC='studiosat-radioprincipal-selector.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
CFG='/etc/studiosat/radioprincipal-selector.liq'
ENV='/etc/studiosat/radioprincipal-selector.env'
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/RESET03-${TS}"
mkdir -p "$BK"
cp -a "$CFG" "$BK/radioprincipal-selector.before.liq"
systemctl cat "$SVC" >"$BK/selector.unit.before.txt" 2>&1 || true

probe_rtmp(){
  timeout 6 ffprobe -v error -rw_timeout 3500000 \
    -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

echo "=============================================================="
echo " RESET03 - RESTORE LAST WORKING RADIO PRINCIPAL SELECTOR"
echo "=============================================================="
echo "BACKUP=$BK"

echo "===== 1. CORE STATE ====="
echo "SELECTOR=$(systemctl is-active "$SVC" 2>/dev/null || true)"
echo "SHADOW=$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
echo "MEDIAMTX=$(systemctl is-active tps-mediamtx.service 2>/dev/null || true)"
echo "NGINX=$(systemctl is-active nginx.service 2>/dev/null || true)"

echo "===== 2. ENSURE EXISTING NS1 SHADOW IS READY ====="
if ! probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
  echo "SHADOW_RTMP=NOT_READY_STARTING_EXISTING_SHADOW"
  systemctl reset-failed "$SHADOW" 2>/dev/null || true
  systemctl restart "$SHADOW"
  for i in $(seq 1 20); do
    sleep 1
    if probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
      echo "SHADOW_RTMP=READY AFTER=${i}s"
      break
    fi
  done
fi

if ! probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
  echo "FATAL=RADIOPRINCIPAL_NS1_SHADOW_NOT_READY"
  echo "NO_SELECTOR_CHANGE=YES"
  exit 20
fi
echo "SHADOW_RTMP=READY"

echo "===== 3. SEARCH REAL ROOT RESTORE POINTS ====="
ROOTS=(
  /root/STUDIOSAT-FORENSIC-NS1-20260917T023826Z
  /root/STUDIOSAT-NS1-CLEANUP-BACKUP-20260916-085221
  /root/studiosat-radioprincipal-mirror-v3-backup-20260916T000819Z
  /root/studiosat-radioprincipal-v2-backup-20260916-075244
  /root/studiosat-radioprincipal-consolidate-20260915-231431
)

CANDLIST="$BK/candidates.tsv"
: >"$CANDLIST"

for root in "${ROOTS[@]}"; do
  [ -e "$root" ] || continue
  echo "SEARCH_ROOT=$root"
  while IFS= read -r -d '' f; do
    if grep -q 'radioprincipal_rb_harbor' "$f" 2>/dev/null &&
       grep -q 'radioprincipal_ns1_rtmp' "$f" 2>/dev/null &&
       grep -Eq '\[[[:space:]]*rb[[:space:]]*,[[:space:]]*ns1' "$f" 2>/dev/null; then
      mt="$(stat -c '%Y' "$f" 2>/dev/null || echo 0)"
      printf '%s\t%s\n' "$mt" "$f" >>"$CANDLIST"
      echo "CANDIDATE=$f"
    fi
  done < <(
    find "$root" -type f \
      \( -iname '*selector*.liq' -o -iname '*selector*.liq.*' -o -iname 'radioprincipal-selector*' \) \
      -print0 2>/dev/null
  )
done

if [ ! -s "$CANDLIST" ]; then
  echo "FATAL=NO_16_17_SELECTOR_WITH_RB_NS1_FAILOVER_FOUND"
  echo "NO_SELECTOR_CHANGE=YES"
  exit 21
fi

sort -rn "$CANDLIST" >"$BK/candidates.sorted.tsv"

echo "===== CANDIDATES ====="
cat "$BK/candidates.sorted.tsv"

echo "===== 4. VALIDATE CANDIDATES ====="
set -a
[ -f "$ENV" ] && . "$ENV"
set +a

SELECTED=''
while IFS=$'\t' read -r mt cand; do
  echo "CHECK=$cand"
  if /usr/bin/liquidsoap --check "$cand" >"$BK/check.out" 2>"$BK/check.err"; then
    if grep -q 'radioprincipal_rb_harbor' "$cand" &&
       grep -q 'radioprincipal_ns1_rtmp' "$cand" &&
       grep -Eq '\[[[:space:]]*rb[[:space:]]*,[[:space:]]*ns1' "$cand"; then
      SELECTED="$cand"
      echo "SELECTED=$SELECTED"
      break
    fi
  else
    echo "CHECK_FAIL=$cand"
    tail -40 "$BK/check.err" || true
  fi
done <"$BK/candidates.sorted.tsv"

if [ -z "$SELECTED" ]; then
  echo "FATAL=NO_VALIDATED_SELECTOR_CANDIDATE"
  echo "NO_SELECTOR_CHANGE=YES"
  exit 22
fi

cp -a "$SELECTED" "$BK/selected.liq"
echo "SELECTED_SHA=$(sha256sum "$SELECTED" | awk '{print $1}')"

echo "===== 5. SHOW SELECTED FALLBACK ====="
grep -nE 'radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|program = fallback|\[rb' "$SELECTED" || true

echo "===== 6. INSTALL SELECTOR RESTORE ====="
cp -a "$SELECTED" "$CFG"

if ! /usr/bin/liquidsoap --check "$CFG" >/dev/null 2>"$BK/final-check.err"; then
  echo "FATAL=FINAL_CHECK_FAILED_ROLLBACK"
  cp -a "$BK/radioprincipal-selector.before.liq" "$CFG"
  echo "ROLLBACK_CONFIG=APPLIED"
  exit 23
fi

systemctl restart "$SVC"

listen=0
for i in $(seq 1 25); do
  sleep 1
  if ss -ltn 2>/dev/null | grep -q ':18005'; then
    listen=1
    echo "HARBOR_LISTEN=YES AFTER=${i}s"
    break
  fi
done
if [ "$listen" -ne 1 ]; then
  echo "FATAL=HARBOR_NOT_BACK_ROLLBACK"
  cp -a "$BK/radioprincipal-selector.before.liq" "$CFG"
  systemctl restart "$SVC" || true
  echo "ROLLBACK=APPLIED"
  exit 24
fi

echo "===== 7. PUBLIC AUDIO ====="
pub=0
for i in $(seq 1 30); do
  if probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal'; then
    pub=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

if [ "$pub" -ne 1 ]; then
  echo "FATAL=PUBLIC_NOT_READY_ROLLBACK"
  cp -a "$BK/radioprincipal-selector.before.liq" "$CFG"
  systemctl restart "$SVC" || true
  echo "ROLLBACK=APPLIED"
  exit 25
fi

echo "===== 8. HLS ====="
if timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 | head -20; then
  echo "PUBLIC_HLS=READY"
else
  echo "PUBLIC_HLS=NOT_READY"
fi

echo "===== 9. ACTIVE SOURCE / EVENTS ====="
journalctl -u "$SVC" --since '4 minutes ago' --no-pager |
  grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|emergency_blank|Feeding stopped|New metadata' |
  tail -160 || true

latest="$(journalctl -u "$SVC" --since '4 minutes ago' --no-pager | grep 'Switch to' | tail -1 || true)"
echo "LATEST_SWITCH=$latest"

if echo "$latest" | grep -Eq 'radioprincipal_rb_harbor|radioprincipal_ns1_rtmp'; then
  echo "RADIOPRINCIPAL_AUDIO_SOURCE=VALID"
else
  echo "RADIOPRINCIPAL_AUDIO_SOURCE=UNKNOWN_OR_SECURITY"
fi

echo "RESULTADO=RESET03_RADIOPRINCIPAL_RESTORED_WITH_RB_NS1_FAILOVER"
echo "SELECTED_RESTORE=$SELECTED"
echo "ROLLBACK_COPY=$BK/radioprincipal-selector.before.liq"
