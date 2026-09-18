#!/usr/bin/env bash
# C21 / P1 — RadioBOSS LIVE stability probe
# Safety: READ-ONLY against production. Writes only its report under /root.
set -Eeuo pipefail

SECONDS_TO_OBSERVE="${OBSERVE_SECONDS:-180}"
INTERVAL="${SAMPLE_INTERVAL:-1}"
OUT="${OUT:-/root/P1-RADIOBOSS-LIVE-STABILITY-$(date -u +%Y%m%dT%H%M%SZ).txt}"
SEL='studiosat-radioprincipal-selector.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
PB='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json'

case "$SECONDS_TO_OBSERVE" in
  ''|*[!0-9]*) echo "ERRO=OBSERVE_SECONDS_INVALIDO"; exit 2;;
esac
if [ "$SECONDS_TO_OBSERVE" -lt 30 ]; then
  echo "ERRO=OBSERVE_SECONDS_MIN_30"; exit 2
fi

exec > >(tee "$OUT") 2>&1

START_EPOCH="$(date +%s)"
START_UTC="$(date -u '+%Y-%m-%d %H:%M:%S')"

echo "=============================================================="
echo " C21 / P1 - RADIOBOSS LIVE STABILITY PROBE"
echo " READ-ONLY / NO PRODUCTION MUTATION"
echo "=============================================================="
echo "UTC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "OBSERVE_SECONDS=$SECONDS_TO_OBSERVE"
echo "SAMPLE_INTERVAL=$INTERVAL"
echo "REPORT=$OUT"

echo
echo "===== BASELINE ====="
for u in "$SEL" "$SHADOW" tps-mediamtx.service nginx.service studiosat-radioboss-sync.service; do
  echo "$u=$(systemctl is-active "$u" 2>/dev/null || true)"
done
echo "HARBOR_LISTEN=$(ss -ltn 2>/dev/null | grep -q ':18005' && echo YES || echo NO)"
echo "HARBOR_ESTABLISHED=$(ss -tn state established 2>/dev/null | grep -q ':18005' && echo YES || echo NO)"
echo "--- TCP 18005 ---"
ss -tinp state established 2>/dev/null | grep -A2 -B1 ':18005' || true

echo
echo "===== SAMPLES ====="
echo "epoch utc harbor_listen harbor_established selector shadow playback_age_sec public_ready shadow_ready"

total=0
established=0
listen_ok=0
selector_ok=0
shadow_ok=0
public_ok=0
shadow_rtmp_ok=0
max_pb_age=0

end=$((START_EPOCH + SECONDS_TO_OBSERVE))
next_media_probe=0

while [ "$(date +%s)" -lt "$end" ]; do
  now="$(date +%s)"
  utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  total=$((total+1))

  if ss -ltn 2>/dev/null | grep -q ':18005'; then hl=1; listen_ok=$((listen_ok+1)); else hl=0; fi
  if ss -tn state established 2>/dev/null | grep -q ':18005'; then he=1; established=$((established+1)); else he=0; fi

  sa="$(systemctl is-active "$SEL" 2>/dev/null || true)"
  [ "$sa" = active ] && selector_ok=$((selector_ok+1))
  sh="$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
  [ "$sh" = active ] && shadow_ok=$((shadow_ok+1))

  if [ -e "$PB" ]; then
    mt="$(stat -c %Y "$PB" 2>/dev/null || echo 0)"
    pa=$((now-mt))
  else
    pa=999999
  fi
  [ "$pa" -gt "$max_pb_age" ] && max_pb_age="$pa"

  pr='-'
  sr='-'
  if [ "$now" -ge "$next_media_probe" ]; then
    if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0       rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q .; then
      pr=1; public_ok=$((public_ok+1))
    else
      pr=0
    fi
    if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0       rtmp://127.0.0.1:1935/radioprincipal-ns1 2>/dev/null | grep -q .; then
      sr=1; shadow_rtmp_ok=$((shadow_rtmp_ok+1))
    else
      sr=0
    fi
    next_media_probe=$((now+10))
  fi

  printf '%s %s %s %s %s %s %s %s %s\n'     "$now" "$utc" "$hl" "$he" "$sa" "$sh" "$pa" "$pr" "$sr"

  sleep "$INTERVAL"
done

echo
echo "===== SELECTOR EVENTS IN OBSERVATION WINDOW ====="
JTMP="$(mktemp /root/.c21-selector.XXXXXX.log)"
trap 'rm -f "$JTMP"' EXIT
journalctl -u "$SEL" --since "$START_UTC" -o short-iso-precise --no-pager > "$JTMP" 2>/dev/null || true

grep -Ei 'Switch to|New metadata|Feeding stopped|Feeding started|Error while reading|Decoding failed|relaying stopped' "$JTMP" | tail -300 || true

rb_switch="$(grep -c 'Switch to radioprincipal_rb_harbor' "$JTMP" || true)"
ns1_switch="$(grep -c 'Switch to radioprincipal_ns1_rtmp' "$JTMP" || true)"
blank_switch="$(grep -c 'Switch to radioprincipal_emergency_blank' "$JTMP" || true)"
rb_metadata="$(grep -c 'radioprincipal_rb_harbor.*New metadata' "$JTMP" || true)"
rb_feed_stop="$(grep -c 'radioprincipal_rb_harbor.*Feeding stopped' "$JTMP" || true)"
rb_read_error="$(grep -c 'radioprincipal_rb_harbor.*Error while reading' "$JTMP" || true)"

echo
echo "===== CURRENT PLAYBACK ====="
python3 - "$PB" <<'PY' 2>/dev/null || true
import json,sys,os,time
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
q=d.get('payload',{}); x=q.get('data',q)
c=x.get('current') or {}; n=x.get('next') or {}
print("PLAYBACK_AGE_SEC=%.3f"%(time.time()-os.stat(p).st_mtime))
print("STATE="+str(x.get('state')))
print("PLAYLISTPOS="+str(x.get('playlistpos')))
print("POS_MS="+str(x.get('pos_ms')))
print("CURRENT="+str(c.get('ITEMTITLE') or c.get('CASTTITLE') or c.get('FILENAME')))
print("NEXT="+str(n.get('ITEMTITLE') or n.get('CASTTITLE') or n.get('FILENAME')))
PY

echo
echo "===== TCP 18005 FINAL ====="
ss -tinp state established 2>/dev/null | grep -A2 -B1 ':18005' || true

echo
echo "===== SUMMARY ====="
echo "SAMPLES=$total"
echo "HARBOR_LISTEN_SAMPLES=$listen_ok"
echo "HARBOR_ESTABLISHED_SAMPLES=$established"
echo "SELECTOR_ACTIVE_SAMPLES=$selector_ok"
echo "SHADOW_ACTIVE_SAMPLES=$shadow_ok"
echo "MAX_PLAYBACK_AGE_SEC=$max_pb_age"
echo "RB_SWITCHES=$rb_switch"
echo "NS1_SWITCHES=$ns1_switch"
echo "BLANK_SWITCHES=$blank_switch"
echo "RB_METADATA_EVENTS=$rb_metadata"
echo "RB_FEED_STOP_EVENTS=$rb_feed_stop"
echo "RB_READ_ERROR_EVENTS=$rb_read_error"

python3 - "$total" "$established" "$ns1_switch" "$blank_switch" "$rb_feed_stop" "$rb_read_error" <<'PY'
import sys
total,est,ns1,blank,stop,err=map(int,sys.argv[1:])
ratio=(est/total*100.0) if total else 0.0
print("HARBOR_ESTABLISHED_PERCENT=%.2f"%ratio)
if blank>0:
    print("P1_SAMPLE_STATUS=CRITICAL_BLANK")
elif ns1>0 or stop>0 or err>0 or ratio<99.0:
    print("P1_SAMPLE_STATUS=UNSTABLE")
else:
    print("P1_SAMPLE_STATUS=SAMPLE_PASS")
print("NOTE=SAMPLE_PASS_NAO_SUBSTITUI_SOAK_TEST_DE_LONGA_DURACAO")
PY

echo "NO_SYSTEMCTL_MUTATION=YES"
echo "NO_CONFIG_MUTATION=YES"
echo "RESULTADO=C21_P1_PROBE_COMPLETE"
