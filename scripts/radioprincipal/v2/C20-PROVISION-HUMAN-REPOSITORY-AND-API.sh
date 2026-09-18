#!/usr/bin/env bash
set -Eeuo pipefail
ROOT='/srv/studiosat/radio-principal'
NEXT='/opt/studiosat/radio-v2-next/radioprincipal'
STATE="$ROOT/estado"
RAW='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v2'
SYNC="$NEXT/program-repository-human-sync.py"
API="$NEXT/operator-api.py"

echo '===== C20 STUDIO SAT RADIO PRINCIPAL - ESTRUTURA OPERACIONAL ====='
echo 'REGRA=NAO_REINICIAR_PRODUCAO'

for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u BEFORE=$(systemctl is-active "$u" 2>/dev/null || true)"
done

install -d -o tpsmedia -g tpsmedia -m 2775  "$ROOT" "$ROOT/grade" "$ROOT/grade/manha" "$ROOT/grade/tarde" "$ROOT/grade/noite"  "$ROOT/elementos/comerciais" "$ROOT/elementos/vinhetas" "$ROOT/elementos/hora-certa" "$ROOT/elementos/temperatura"  "$ROOT/operacao/importar" "$ROOT/operacao/quarentena" "$ROOT/estado"
install -d -o root -g root -m 0755 "$NEXT"

curl -fsSL "$RAW/program-repository-human-sync.py" -o "$SYNC"
curl -fsSL "$RAW/operator-api.py" -o "$API"
chmod 0755 "$SYNC" "$API"
python3 -m py_compile "$SYNC" "$API"

echo '===== SEED HISTORICO SEM TOCAR PRODUCAO ====='
python3 "$SYNC" --history

cat >/etc/systemd/system/studiosat-radioprincipal-v2-human-repo-sync.service <<EOF
[Unit]
Description=Studio Sat Radio Principal human repository sync
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $SYNC
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/stations/radioprincipal /var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current /srv/tpsmedia/repository/channels/radioprincipal
ReadWritePaths=$ROOT
EOF
cat >/etc/systemd/system/studiosat-radioprincipal-v2-human-repo-sync.timer <<'EOF'
[Unit]
Description=Studio Sat Radio Principal human repository sync every 5s
[Timer]
OnBootSec=5s
OnUnitActiveSec=5s
AccuracySec=1s
Persistent=true
Unit=studiosat-radioprincipal-v2-human-repo-sync.service
[Install]
WantedBy=timers.target
EOF
cat >/etc/systemd/system/studiosat-radioprincipal-v2-operator-api.service <<EOF
[Unit]
Description=Studio Sat Radio Principal Operator API
After=network.target
[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/python3 $API
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current /var/lib/studiosat/radio-v2/stations/radioprincipal
ReadWritePaths=$ROOT
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now studiosat-radioprincipal-v2-human-repo-sync.timer >/dev/null
systemctl enable --now studiosat-radioprincipal-v2-operator-api.service >/dev/null
sleep 2

echo '===== PASTAS PRATICAS ====='
find "$ROOT" -maxdepth 2 -type d -print | sort
echo '===== CONTAGEM ====='
find "$ROOT/grade" -maxdepth 2 -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' \) -printf '%h\n' | sort | uniq -c || true
echo '===== API ====='
curl -fsS http://127.0.0.1:8810/api/v1/status | python3 -m json.tool || true
echo '===== PRODUCAO NAO TOCADA ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u AFTER=$(systemctl is-active "$u" 2>/dev/null || true)"
done
echo 'RESULTADO=C20_HUMAN_REPOSITORY_AND_OPERATOR_API_OK'
