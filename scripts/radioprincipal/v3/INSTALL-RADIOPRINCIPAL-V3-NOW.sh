#!/usr/bin/env bash
set -Eeuo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/V3-CUTOVER-${TS}"
SRC_ENV="/etc/studiosat/radioprincipal-selector.env"
ICECAST_CFG="/etc/icecast2/radioprincipal-v3.xml"
ICECAST_UNIT="/etc/systemd/system/studiosat-radioprincipal-v3-icecast.service"
CORE_UNIT="/etc/systemd/system/studiosat-radioprincipal-v3-core.service"
CORE_DIR="/opt/studiosat/radio-principal-v3"
CORE_PY="$CORE_DIR/radioprincipal-core.py"
V3_ENV="/etc/studiosat/radioprincipal-v3.env"
SELECTOR="studiosat-radioprincipal-selector.service"
SHADOW="studiosat-radioprincipal-shadow-ns1.service"
ICECAST_SVC="studiosat-radioprincipal-v3-icecast.service"
CORE_SVC="studiosat-radioprincipal-v3-core.service"
EMERGENCY="studiosat-radioprincipal-emergency-direct.service"

mkdir -p "$BK"

say(){ echo "[$(date -u +%H:%M:%S)] $*"; }
fail(){ echo "FATAL=$*" >&2; exit 1; }

probe_rtmp(){
  timeout 7 ffprobe -v error -rw_timeout 4000000 \
    -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -q .
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
say " STUDIO SAT RADIO PRINCIPAL V3 - PRODUCTION CUTOVER"
say "=============================================================="
say "BACKUP=$BK"

say "1/10 BACKUP CURRENT STATE"
cp -a /etc/studiosat/radioprincipal-selector.liq "$BK/" 2>/dev/null || true
cp -a "$SRC_ENV" "$BK/" 2>/dev/null || true
systemctl cat "$SELECTOR" >"$BK/selector.unit.txt" 2>&1 || true
systemctl cat "$SHADOW" >"$BK/shadow.unit.txt" 2>&1 || true
systemctl list-units --all --no-pager >"$BK/units.before.txt" 2>&1 || true

say "2/10 REQUIRE EXISTING SHADOW"
systemctl is-active --quiet "$SHADOW" || systemctl start "$SHADOW"
for i in $(seq 1 20); do
  if probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
    say "SHADOW_RTMP=READY"
    break
  fi
  sleep 1
done
probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1' || fail "SHADOW_NOT_READY"

say "3/10 INSTALL ICECAST2"
export DEBIAN_FRONTEND=noninteractive
if ! command -v icecast2 >/dev/null 2>&1; then
  apt-get update
  apt-get install -y icecast2
fi
command -v icecast2 >/dev/null 2>&1 || fail "ICECAST2_INSTALL_FAILED"
ICECAST_VER="$(icecast2 -v 2>&1 | head -1 || true)"
say "ICECAST_VERSION=$ICECAST_VER"
systemctl disable --now icecast2.service 2>/dev/null || true

id icecast2 >/dev/null 2>&1 || fail "ICECAST2_USER_MISSING"
ICEGROUP="$(id -gn icecast2)"

say "4/10 BUILD V3"
install -d -m 0755 "$CORE_DIR"
curl -fsSL \
'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v3/radioprincipal-core.py' \
-o "$CORE_PY"
chmod 0755 "$CORE_PY"
python3 -m py_compile "$CORE_PY"

[ -f "$SRC_ENV" ] || fail "SOURCE_ENV_MISSING"
set -a
. "$SRC_ENV"
set +a
[ -n "${RB_HARBOR_PASSWORD:-}" ] || fail "RB_HARBOR_PASSWORD_MISSING"

ADMIN_PASS="$(openssl rand -hex 24)"
export ADMIN_PASS RB_HARBOR_PASSWORD ICECAST_CFG

install -d -m 0755 /etc/icecast2
install -d -o icecast2 -g "$ICEGROUP" -m 0755 /var/log/icecast2

python3 - <<'PY'
import os
from html import escape
from pathlib import Path
src=escape(os.environ["RB_HARBOR_PASSWORD"], quote=True)
adm=escape(os.environ["ADMIN_PASS"], quote=True)
cfg=f"""<icecast>
  <location>Studio Sat NS1</location>
  <admin>studio-sat@localhost</admin>
  <limits>
    <clients>100</clients>
    <sources>4</sources>
    <queue-size>524288</queue-size>
    <client-timeout>30</client-timeout>
    <header-timeout>15</header-timeout>
    <source-timeout>10</source-timeout>
    <burst-on-connect>1</burst-on-connect>
    <burst-size>65535</burst-size>
  </limits>
  <authentication>
    <source-password>{src}</source-password>
    <relay-password>{adm}</relay-password>
    <admin-user>admin</admin-user>
    <admin-password>{adm}</admin-password>
  </authentication>
  <hostname>localhost</hostname>
  <listen-socket>
    <port>18005</port>
    <bind-address>127.0.0.1</bind-address>
  </listen-socket>
  <mount>
    <mount-name>/radioprincipal-rb</mount-name>
    <public>0</public>
  </mount>
  <fileserve>1</fileserve>
  <paths>
    <basedir>/usr/share/icecast2</basedir>
    <logdir>/var/log/icecast2</logdir>
    <webroot>/usr/share/icecast2/web</webroot>
    <adminroot>/usr/share/icecast2/admin</adminroot>
  </paths>
  <logging>
    <accesslog>radioprincipal-v3-access.log</accesslog>
    <errorlog>radioprincipal-v3-error.log</errorlog>
    <loglevel>2</loglevel>
    <logsize>10000</logsize>
  </logging>
</icecast>
"""
Path(os.environ["ICECAST_CFG"]).write_text(cfg)
PY

chown root:"$ICEGROUP" "$ICECAST_CFG"
chmod 0640 "$ICECAST_CFG"

cat >"$V3_ENV" <<'EOF'
LIVE_URL=http://127.0.0.1:18005/radioprincipal-rb
FALLBACK_RTMP=rtmp://127.0.0.1:1935/radioprincipal-ns1
PUBLIC_RTMP=rtmp://127.0.0.1:1935/radioprincipal
STATE_PATH=/run/studiosat/radioprincipal-v3-state.json
LIVE_STABLE_SEC=15
HEALTH_INTERVAL=2
LIVE_FAIL_CHECKS=2
EOF
chmod 0644 "$V3_ENV"

cat >"$ICECAST_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V3 Icecast ingest
After=network-online.target
Wants=network-online.target

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
Description=Studio Sat Radio Principal V3 core - live/fallback/public
After=network-online.target tps-mediamtx.service $SHADOW $ICECAST_SVC
Requires=tps-mediamtx.service $SHADOW
Wants=$ICECAST_SVC
Conflicts=$SELECTOR $EMERGENCY

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=$V3_ENV
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

say "5/10 PREFLIGHT CORE ON TEST PATH - PRODUCTION UNTOUCHED"
TEST_LOG="$BK/v3-preflight.log"
env \
  LIVE_URL=http://127.0.0.1:18015/radioprincipal-rb \
  FALLBACK_RTMP=rtmp://127.0.0.1:1935/radioprincipal-ns1 \
  PUBLIC_RTMP=rtmp://127.0.0.1:1935/radioprincipal-v3-test \
  STATE_PATH=/run/studiosat/radioprincipal-v3-preflight.json \
  LIVE_STABLE_SEC=15 \
  /usr/bin/python3 "$CORE_PY" >"$TEST_LOG" 2>&1 &
TPID=$!
sleep 5

if ! probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-v3-test'; then
  kill "$TPID" 2>/dev/null || true
  wait "$TPID" 2>/dev/null || true
  tail -80 "$TEST_LOG" || true
  fail "V3_PREFLIGHT_FAILED"
fi
say "V3_PREFLIGHT=PASS"
kill "$TPID" 2>/dev/null || true
wait "$TPID" 2>/dev/null || true
rm -f /run/studiosat/radioprincipal-v3-preflight.json 2>/dev/null || true
sleep 1

say "6/10 CUTOVER - STOP OLD SELECTOR / START V3 INGEST"
systemctl disable --now "$EMERGENCY" 2>/dev/null || true
systemctl disable --now "$SELECTOR" 2>/dev/null || true
systemctl reset-failed "$ICECAST_SVC" "$CORE_SVC" 2>/dev/null || true

if ! systemctl enable --now "$ICECAST_SVC"; then
  rollback
  fail "ICECAST_V3_START_FAILED"
fi

ice_listen=0
for i in $(seq 1 15); do
  if ss -ltnp 2>/dev/null | grep -q '127.0.0.1:18005'; then
    ice_listen=1
    say "ICECAST_18005=LISTEN AFTER=${i}s"
    break
  fi
  sleep 1
done
if [ "$ice_listen" -ne 1 ]; then
  journalctl -u "$ICECAST_SVC" -n 80 --no-pager || true
  rollback
  fail "ICECAST_18005_NOT_LISTENING"
fi

if ! systemctl enable --now "$CORE_SVC"; then
  rollback
  fail "V3_CORE_START_FAILED"
fi

say "7/10 REQUIRE PUBLIC RTMP"
public_ok=0
for i in $(seq 1 30); do
  if path_ready radioprincipal && probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal'; then
    public_ok=1
    say "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

if [ "$public_ok" -ne 1 ]; then
  journalctl -u "$CORE_SVC" -n 120 --no-pager || true
  rollback
  fail "PUBLIC_RTMP_NOT_READY"
fi

say "8/10 WAIT RADIOBOSS RECONNECT / FAILBACK CONTROL"
for i in $(seq 1 40); do
  SRC="$(python3 - <<'PY'
import json
try:
    d=json.load(open('/run/studiosat/radioprincipal-v3-state.json'))
    print(d.get('source') or 'unknown')
except Exception:
    print('unknown')
PY
)"
  say "SOURCE=$SRC WAIT=${i}s"
  [ "$SRC" = "live" ] && break
  sleep 1
done

say "9/10 HLS"
HLS_OK=0
for i in $(seq 1 20); do
  if timeout 6 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null | grep -q '^#EXTM3U'; then
    HLS_OK=1
    say "PUBLIC_HLS=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
[ "$HLS_OK" -eq 1 ] || say "PUBLIC_HLS=LOCAL_PROBE_PENDING_BUT_RTMP_READY"

say "10/10 FINAL"
systemctl is-active "$CORE_SVC" || true
systemctl is-active "$ICECAST_SVC" || true
systemctl is-active "$SHADOW" || true
systemctl is-active "$SELECTOR" || true

cat /run/studiosat/radioprincipal-v3-state.json 2>/dev/null || true
echo
curl -fsS http://127.0.0.1:9997/v3/paths/get/radioprincipal 2>/dev/null || true
echo

say "RADIOPRINCIPAL_V3=ACTIVE"
say "OLD_LIQUIDSOAP_SELECTOR=DISABLED"
say "PUBLIC_RTMP=READY"
if [ "$HLS_OK" -eq 1 ]; then
  say "PUBLIC_HLS=READY"
fi
say "RESULTADO=RADIOPRINCIPAL_V3_ON_AIR"
say "BACKUP=$BK"
