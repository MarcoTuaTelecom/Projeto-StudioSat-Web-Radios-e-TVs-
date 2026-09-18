#!/usr/bin/env bash
# Nome: RECOVER-AUTHORITY-WATCH-5S.sh
# Versão: 1.0 / 2026-09-17
# Change: RADIOPRINCIPAL-NS1-C10
# Safety: não reinicia selector, MediaMTX, Harbor ou shadow público.
set -euo pipefail

RUNNER_URL='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/candidate/RUN-AUTHORITY-REPLICA-CANDIDATE.sh'
RUNNER='/root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh'
SRC='/root/authority-replica-candidate.py'
DST_DIR='/opt/studiosat/radio-v2/radioprincipal-authority'
DST="$DST_DIR/authority-replica-candidate.py"
UNIT='/etc/systemd/system/studiosat-radioprincipal-authority-candidate.service'
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
CAND='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica'

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

echo '===== 1. BAIXAR/VALIDAR CANDIDATE ====='
curl -fsSL "$RUNNER_URL" -o "$RUNNER"
chmod 700 "$RUNNER"
bash -n "$RUNNER"
"$RUNNER" --once >/tmp/studiosat-authority-once.log
tail -20 /tmp/studiosat-authority-once.log

echo
echo '===== 2. INSTALAR BINARIO FORA DE /root ====='
install -d -m 0755 "$DST_DIR"
install -m 0755 "$SRC" "$DST"
python3 -m py_compile "$DST"
echo "CANDIDATE_BINARY=$DST"
echo 'PY_COMPILE=OK'

echo
echo '===== 3. INSTALAR UNIT 5s ====='
cat > "$UNIT" <<EOF
[Unit]
Description=Studio Sat RadioPrincipal Authority Replica Candidate 5s
After=network-online.target studiosat-radioboss-sync.service studiosat-media-transfer.service
Wants=network-online.target
Requires=studiosat-radioboss-sync.service studiosat-media-transfer.service

[Service]
Type=simple
User=root
Group=root
ExecStart=$DST --watch --interval 5 --heartbeat-max-age 15 --playback-max-age 10
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadWritePaths=$CAND
ReadOnlyPaths=$SYNC /var/lib/studiosat/radio-v2/media-transfer /srv/tpsmedia/repository/channels/radioprincipal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable studiosat-radioprincipal-authority-candidate.service >/dev/null
systemctl restart studiosat-radioprincipal-authority-candidate.service
sleep 3

echo
echo '===== 4. ESTADO DO SERVICO ====='
systemctl show studiosat-radioprincipal-authority-candidate.service   -p ActiveState -p SubState -p MainPID -p NRestarts -p ExecStart

systemctl is-active --quiet studiosat-radioprincipal-authority-candidate.service || {
  echo 'AUTHORITY_WATCH_5S=FAILED'
  journalctl -u studiosat-radioprincipal-authority-candidate.service -n 60 --no-pager
  exit 20
}

echo 'AUTHORITY_WATCH_5S=ACTIVE'

echo
echo '===== 5. STATUS ATUAL ====='
python3 - "$CAND/status.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
print('VERSION='+str(d.get('version')))
print('STATUS='+str(d.get('status')))
print('ITEMS='+str(d.get('items')))
print('AVAILABLE='+str(d.get('available')))
print('MISSING='+str(d.get('missing')))
print('UNRESOLVED='+str(d.get('unresolved')))
f=d.get('freshness',{})
r=d.get('readiness',{})
p=d.get('playback',{})
print('SOURCE_ONLINE='+str(f.get('source_online')))
print('PLAYBACK_FRESH='+str(f.get('playback_fresh')))
print('PLAYBACK_AGE_SEC='+str(f.get('playback_age_sec')))
print('REPLICA_COMPLETE='+str(r.get('replica_complete')))
print('CURRENT_ITEM_READY='+str(r.get('current_item_ready')))
print('CURRENT_MATCH='+str(r.get('current_matches_playlistpos')))
print('NEXT_MATCH='+str(r.get('next_matches_playlistpos_plus_1')))
print('QUEUE_ALIGNED='+str(r.get('queue_aligned')))
print('PLAYLISTPOS='+str(p.get('playlistpos')))
print('POS_MS='+str(p.get('pos_ms')))
print('CURRENT='+str(p.get('current_ref')))
print('NEXT='+str(p.get('next_ref')))
PY

echo
echo '===== 6. JOURNAL 30s ====='
journalctl -u studiosat-radioprincipal-authority-candidate.service --since '30 seconds ago' --no-pager | tail -40

echo
echo 'RESULTADO=C10_RECOVERY_OK'
