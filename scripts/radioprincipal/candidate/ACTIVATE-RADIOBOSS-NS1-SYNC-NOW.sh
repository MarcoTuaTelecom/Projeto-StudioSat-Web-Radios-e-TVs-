#!/usr/bin/env bash
# Nome: ACTIVATE-RADIOBOSS-NS1-SYNC-NOW.sh
# Versão: 1.1 / 2026-09-17
# Owner: Rádio
# Safety class: controlled-production-support
# Change ID: RADIOPRINCIPAL-NS1-C07
# Propósito: rearmar recepção NS1, importar playlist atual e manter réplica candidate a cada 5s.
set -euo pipefail

SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
CAND='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica'
RUNNER='/root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh'
CANDPY='/root/authority-replica-candidate.py'
UNIT='/etc/systemd/system/studiosat-radioprincipal-authority-candidate.service'
RUNNER_URL='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/candidate/RUN-AUTHORITY-REPLICA-CANDIDATE.sh'

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

echo '============================================================'
echo ' STUDIO SAT - RADIOBOSS -> NS1 - ATIVACAO IMEDIATA'
echo '============================================================'
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"

ensure_service() {
  local u="$1"
  if systemctl is-active --quiet "$u"; then
    echo "SERVICE_OK=$u"
  else
    echo "SERVICE_START=$u"
    systemctl start "$u"
    sleep 1
    systemctl is-active --quiet "$u" || { echo "ERRO_SERVICE=$u"; exit 20; }
  fi
}

ensure_service studiosat-radioboss-sync.service
ensure_service studiosat-media-transfer.service
ensure_service studiosat-radioprincipal-shadow-ns1.service
ensure_service studiosat-radioprincipal-selector.service

echo
echo '===== HARBOR 18005 ====='
if ss -ltnp 2>/dev/null | grep -qE '127\.0\.0\.1:18005|\[::ffff:127\.0\.0\.1\]:18005'; then
  echo 'HARBOR_LISTEN=YES'
else
  echo 'HARBOR_LISTEN=NO'
  echo 'SELECTOR_REARM=YES'
  systemctl restart studiosat-radioprincipal-selector.service
  sleep 3
  if ss -ltnp 2>/dev/null | grep -qE '127\.0\.0\.1:18005|\[::ffff:127\.0\.0\.1\]:18005'; then
    echo 'HARBOR_LISTEN_AFTER_REARM=YES'
  else
    echo 'HARBOR_LISTEN_AFTER_REARM=NO'
    exit 21
  fi
fi

echo
echo '===== ATUALIZAR CANDIDATE AGORA ====='
curl -fsSL "$RUNNER_URL" -o "$RUNNER"
chmod 700 "$RUNNER"
bash -n "$RUNNER"
echo 'RUNNER_SYNTAX=OK'
"$RUNNER" --once

echo
echo '===== INSTALAR WATCH 5s ====='
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
ExecStart=$CANDPY --watch --interval 5
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
systemctl enable --now studiosat-radioprincipal-authority-candidate.service
sleep 2
systemctl is-active --quiet studiosat-radioprincipal-authority-candidate.service
echo 'AUTHORITY_WATCH_5S=ACTIVE'

echo
echo '===== SNAPSHOT ATUAL ====='
python3 - "$SYNC" <<'PY'
import json,sys,time
from pathlib import Path
p=Path(sys.argv[1])
for n in ('playlist.json','playback.json','schedule.json','librarymanifest.json','heartbeat.json'):
    f=p/n
    if not f.exists():
        print(f'{n}=MISSING');continue
    d=json.loads(f.read_text(encoding='utf-8'))
    print(f'{n}.AGE_SEC={time.time()-f.stat().st_mtime:.1f}')
    print(f'{n}.REVISION={d.get("revision")}')
    pl=d.get('payload',{})
    if isinstance(pl,dict):
        print(f'{n}.RADIOBOSS_ONLINE={pl.get("radioboss_online")}')
        x=pl.get('data',{})
        if n=='playback.json' and isinstance(x,dict):
            c=x.get('current') if isinstance(x.get('current'),dict) else {}
            q=x.get('next') if isinstance(x.get('next'),dict) else {}
            print('PLAYBACK_STATE='+str(x.get('state')))
            print('PLAYLISTPOS='+str(x.get('playlistpos')))
            print('CURRENT='+str(c.get('ITEMTITLE') or c.get('CASTTITLE') or c.get('FILENAME') or ''))
            print('NEXT='+str(q.get('ITEMTITLE') or q.get('CASTTITLE') or q.get('FILENAME') or ''))
PY

echo
echo '===== CANDIDATE STATUS RESUMIDO ====='
python3 - "$CAND/status.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
for k in ('version','status','program_hint','items','available','missing','unresolved','playlist_revision_id','schedule_revision_id'):
    print(f'{k.upper()}={d.get(k)}')
print('SOURCE_ONLINE='+str(d.get('freshness',{}).get('source_online')))
print('PLAYBACK_FRESH='+str(d.get('freshness',{}).get('playback_fresh')))
print('REPLICA_COMPLETE='+str(d.get('readiness',{}).get('replica_complete')))
print('QUEUE_ALIGNED='+str(d.get('readiness',{}).get('queue_aligned')))
PY

echo
echo '===== RADIOBOSS LIVE / HARBOR ====='
LISTEN="$(ss -ltnp 2>/dev/null | grep -E '127\.0\.0\.1:18005|\[::ffff:127\.0\.0\.1\]:18005' || true)"
ESTAB="$(ss -tnp state established 2>/dev/null | grep -E ':18005[[:space:]]|[[:space:]]127\.0\.0\.1:18005' || true)"
[ -n "$LISTEN" ] && echo 'HARBOR_LISTEN_FINAL=YES' || echo 'HARBOR_LISTEN_FINAL=NO'
if [ -n "$ESTAB" ]; then
  echo 'RADIOBOSS_LIVE_TCP=CONNECTED'
  echo "$ESTAB"
else
  echo 'RADIOBOSS_LIVE_TCP=NOT_CONNECTED'
fi

echo
echo '===== SELECTOR ULTIMOS EVENTOS ====='
journalctl -u studiosat-radioprincipal-selector.service --since '3 minutes ago' --no-pager 2>/dev/null | tail -40 || true

echo
echo '===== RESULTADO ====='
echo 'PLAYLIST_SYNC_5S=ENABLED'
if [ -n "$ESTAB" ]; then
  echo 'LIVE_LINK=CONNECTED'
else
  echo 'LIVE_LINK=WAITING_FOR_STUDIO_TUNNEL_OR_ENCODER'
fi
echo 'RESULTADO=C07_APLICADO'
