#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V31-CUTOVER-${TS}"
SRC_ENV="/etc/studiosat/radioprincipal-selector.env"
ICECAST_CFG="/etc/icecast2/radioprincipal-v31.xml"
ICECAST_TEST_CFG="/etc/icecast2/radioprincipal-v31-test.xml"
ICECAST_UNIT="/etc/systemd/system/studiosat-radioprincipal-v31-icecast.service"
CORE_UNIT="/etc/systemd/system/studiosat-radioprincipal-v31-core.service"
CORE_DIR="/opt/studiosat/radio-principal-v31"
CORE_PY="$CORE_DIR/radioprincipal-core-v3.1.py"
V31_ENV="/etc/studiosat/radioprincipal-v31.env"
SELECTOR="studiosat-radioprincipal-selector.service"
SHADOW="studiosat-radioprincipal-shadow-ns1.service"
ICECAST_SVC="studiosat-radioprincipal-v31-icecast.service"
CORE_SVC="studiosat-radioprincipal-v31-core.service"
OLD_V3_CORE="studiosat-radioprincipal-v3-core.service"
OLD_V3_ICE="studiosat-radioprincipal-v3-icecast.service"
EMERGENCY="studiosat-radioprincipal-emergency-direct.service"

mkdir -p "$BK"

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe_rtmp(){
  timeout 7 ffprobe -v error -rw_timeout 4000000 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

path_ready(){
  timeout 5 curl -fsS "http://127.0.0.1:9997/v3/paths/get/$1" 2>/dev/null |
    grep -q '"ready":true'
}

rollback(){
  say "ROLLBACK_START"
  systemctl disable --now "$CORE_SVC" 2>/dev/null || true
  systemctl disable --now "$ICECAST_SVC" 2>/dev/null || true
  systemctl enable "$SELECTOR" 2>/dev/null || true
  systemctl restart "$SELECTOR" 2>/dev/null || true
  say "ROLLBACK_APPLIED"
}

[ "$(id -u)" -eq 0 ] || fail "RUN_AS_ROOT"

say "=============================================================="
say " STUDIO SAT RADIO PRINCIPAL V3.1 - REWRITE / CUTOVER"
say "=============================================================="
say "BACKUP=$BK"

say "1/11 SNAPSHOT / REQUIRE SHADOW"
cp -a /etc/studiosat/radioprincipal-selector.liq "$BK/" 2>/dev/null || true
cp -a "$SRC_ENV" "$BK/" 2>/dev/null || true
systemctl cat "$SELECTOR" >"$BK/selector.unit.txt" 2>&1 || true
systemctl cat "$SHADOW" >"$BK/shadow.unit.txt" 2>&1 || true

systemctl is-active --quiet "$SHADOW" || systemctl start "$SHADOW"
probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1' || fail "SHADOW_NOT_READY"
say "SHADOW_RTMP=READY"

say "2/11 REQUIRE INSTALLED ICECAST2"
command -v icecast2 >/dev/null 2>&1 || fail "ICECAST2_NOT_INSTALLED"
ICECAST_VER="$(icecast2 -v 2>&1 | head -1 || true)"
say "ICECAST_VERSION=$ICECAST_VER"
systemctl disable --now icecast2.service 2>/dev/null || true
ICEGROUP="$(id -gn icecast2)"

say "3/11 BUILD CORE"
install -d -m 0755 "$CORE_DIR"
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v3/radioprincipal-core-v3.1.py' \
-o "$CORE_PY"
chmod 0755 "$CORE_PY"
python3 -m py_compile "$CORE_PY"
say "PYTHON_COMPILE=OK"

[ -f "$SRC_ENV" ] || fail "SOURCE_ENV_MISSING"
set -a
. "$SRC_ENV"
set +a
[ -n "${RB_HARBOR_PASSWORD:-}" ] || fail "RB_HARBOR_PASSWORD_MISSING"

ADMIN_PASS="$(openssl rand -hex 24)"
export ADMIN_PASS RB_HARBOR_PASSWORD ICECAST_CFG ICECAST_TEST_CFG

install -d -m 0755 /etc/icecast2
install -d -o icecast2 -g "$ICEGROUP" -m 0755 /var/log/icecast2

python3 - <<'PY'
import os
from html import escape
from pathlib import Path
src=escape(os.environ["RB_HARBOR_PASSWORD"], quote=True)
adm=escape(os.environ["ADMIN_PASS"], quote=True)

def cfg(port):
    return f"""<icecast>
  <location>Studio Sat NS1</location>
  <admin>studio-sat@localhost</admin>
  <limits>
    <clients>100</clients>
    <sources>4</sources>
    <queue-size>1048576</queue-size>
    <client-timeout>30</client-timeout>
    <header-timeout>15</header-timeout>
    <source-timeout>10</source-timeout>
    <burst-on-connect>1</burst-on-connect>
    <burst-size>131072</burst-size>
  </limits>
  <authentication>
    <source-password>{src}</source-password>
    <relay-password>{adm}</relay-password>
    <admin-user>admin</admin-user>
    <admin-password>{adm}</admin-password>
  </authentication>
  <hostname>localhost</hostname>
  <listen-socket>
    <port>{port}</port>
    <bind-address>127.0.0.1</bind-address>
  </listen-socket>
  <mount>
    <mount-name>/radioprincipal-rb</mount-name>
    <public>0</public>
    <burst-size>131072</burst-size>
  </mount>
  <fileserve>1</fileserve>
  <paths>
    <basedir>/usr/share/icecast2</basedir>
    <logdir>/var/log/icecast2</logdir>
    <webroot>/usr/share/icecast2/web</webroot>
    <adminroot>/usr/share/icecast2/admin</adminroot>
  </paths>
  <logging>
    <accesslog>radioprincipal-v31-access.log</accesslog>
    <errorlog>radioprincipal-v31-error.log</errorlog>
    <loglevel>2</loglevel>
    <logsize>10000</logsize>
  </logging>
</icecast>
"""
Path(os.environ["ICECAST_CFG"]).write_text(cfg(18005))
Path(os.environ["ICECAST_TEST_CFG"]).write_text(cfg(18015))
PY

chown root:"$ICEGROUP" "$ICECAST_CFG" "$ICECAST_TEST_CFG"
chmod 0640 "$ICECAST_CFG" "$ICECAST_TEST_CFG"

say "4/11 PREFLIGHT ICECAST ON 18015"
sudo -u icecast2 /usr/bin/icecast2 -c "$ICECAST_TEST_CFG" >"$BK/icecast-test.log" 2>&1 &
TEST_ICE_PID=$!
sleep 2
if ! ss -ltn 2>/dev/null | grep -q '127.0.0.1:18015'; then
  kill "$TEST_ICE_PID" 2>/dev/null || true
  wait "$TEST_ICE_PID" 2>/dev/null || true
  cat "$BK/icecast-test.log" || true
  fail "ICECAST_PREFLIGHT_FAILED"
fi
curl -fsS http://127.0.0.1:18015/status-json.xsl >/dev/null
say "ICECAST_PREFLIGHT=PASS"
kill "$TEST_ICE_PID" 2>/dev/null || true
wait "$TEST_ICE_PID" 2>/dev/null || true

say "5/11 PREFLIGHT FALLBACK DECODE + ENCODER"
timeout 10 ffmpeg -hide_banner -loglevel error -nostdin \
  -rw_timeout 5000000 -i rtmp://127.0.0.1:1935/radioprincipal-ns1 \
  -map 0:a:0 -t 3 -f null - >/dev/null 2>&1 || fail "FALLBACK_DECODE_PREFLIGHT_FAILED"

timeout 8 ffmpeg -hide_banner -loglevel error -nostdin \
  -f lavfi -i anullsrc=r=48000:cl=stereo \
  -t 3 -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f flv "$BK/encoder-selftest.flv" \
  >/dev/null 2>&1 || fail "ENCODER_PREFLIGHT_FAILED"
[ -s "$BK/encoder-selftest.flv" ] || fail "ENCODER_SELFTEST_EMPTY"
say "MEDIA_PREFLIGHT=PASS"

cat >"$V31_ENV" <<'EOF'
LIVE_URL=http://127.0.0.1:18005/radioprincipal-rb
ICECAST_STATUS=http://127.0.0.1:18005/status-json.xsl
FALLBACK_RTMP=rtmp://127.0.0.1:1935/radioprincipal-ns1
PUBLIC_RTMP=rtmp://127.0.0.1:1935/radioprincipal
STATE_PATH=/run/studiosat/radioprincipal-v31-state.json
LIVE_STABLE_SEC=15
LIVE_STALL_SEC=1.5
CHECK_INTERVAL=1
EOF
chmod 0644 "$V31_ENV"

cat >"$ICECAST_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V3.1 Icecast ingest
After=network-online.target
Wants=network-online.target
Conflicts=$SELECTOR

[Service]
Type=simple
User=icecast2
Group=$ICEGROUP
ExecStart=/usr/bin/icecast2 -c $ICECAST_CFG
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/log/icecast2

[Install]
WantedBy=multi-user.target
EOF

cat >"$CORE_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V3.1 continuous public core
After=network-online.target tps-mediamtx.service $SHADOW $ICECAST_SVC
Requires=tps-mediamtx.service $SHADOW $ICECAST_SVC
Conflicts=$SELECTOR $EMERGENCY $OLD_V3_CORE

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=$V31_ENV
ExecStart=/usr/bin/python3 $CORE_PY
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/run/studiosat

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

say "6/11 CUTOVER"
systemctl disable --now "$EMERGENCY" 2>/dev/null || true
systemctl reset-failed "$EMERGENCY" 2>/dev/null || true
systemctl disable --now "$OLD_V3_CORE" "$OLD_V3_ICE" 2>/dev/null || true
systemctl disable --now "$SELECTOR" 2>/dev/null || true

for i in $(seq 1 10); do
  if ! ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005'; then
    break
  fi
  sleep 1
done

say "7/11 START ICECAST V3.1"
if ! systemctl enable --now "$ICECAST_SVC"; then
  rollback
  fail "ICECAST_START_FAILED"
fi
for i in $(seq 1 15); do
  if ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005'; then
    say "ICECAST_18005=LISTEN AFTER=${i}s"
    break
  fi
  sleep 1
done
ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005' || { rollback; fail "ICECAST_18005_NOT_LISTENING"; }

say "8/11 START CONTINUOUS PUBLIC CORE"
if ! systemctl enable --now "$CORE_SVC"; then
  rollback
  fail "V31_CORE_START_FAILED"
fi

say "9/11 REQUIRE PUBLIC RTMP"
PUBLIC_OK=0
for i in $(seq 1 25); do
  if path_ready radioprincipal && probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal'; then
    PUBLIC_OK=1
    say "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
if [ "$PUBLIC_OK" -ne 1 ]; then
  journalctl -u "$CORE_SVC" -n 120 --no-pager || true
  rollback
  fail "PUBLIC_RTMP_NOT_READY"
fi

say "10/11 WAIT LIVE CANDIDATE"
for i in $(seq 1 60); do
  SRC="$(python3 - <<'PY'
import json
try:
    d=json.load(open('/run/studiosat/radioprincipal-v31-state.json'))
    print(d.get('source') or 'unknown')
except Exception:
    print('unknown')
PY
)"
  say "SOURCE=$SRC WAIT=${i}s"
  [ "$SRC" = "live" ] && break
  sleep 1
done

say "11/11 FINAL"
SRC="$(python3 - <<'PY'
import json
try:
    d=json.load(open('/run/studiosat/radioprincipal-v31-state.json'))
    print(d.get('source') or 'unknown')
except Exception:
    print('unknown')
PY
)"

HLS_OK=0
for i in $(seq 1 20); do
  if timeout 6 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null | grep -q '^#EXTM3U'; then
    HLS_OK=1
    break
  fi
  sleep 1
done

echo "CORE=$(systemctl is-active "$CORE_SVC" 2>/dev/null || true)"
echo "ICECAST=$(systemctl is-active "$ICECAST_SVC" 2>/dev/null || true)"
echo "SHADOW=$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
echo "OLD_SELECTOR=$(systemctl is-active "$SELECTOR" 2>/dev/null || true)"
echo "PUBLIC_SOURCE=$SRC"
echo "PUBLIC_RTMP=READY"
[ "$HLS_OK" -eq 1 ] && echo "PUBLIC_HLS=READY" || echo "PUBLIC_HLS=PENDING_LOCAL_GENERATION"
echo "RADIOPRINCIPAL_V31=ACTIVE"
echo "RESULTADO=RADIOPRINCIPAL_V31_ON_AIR"
echo "BACKUP=$BK"
