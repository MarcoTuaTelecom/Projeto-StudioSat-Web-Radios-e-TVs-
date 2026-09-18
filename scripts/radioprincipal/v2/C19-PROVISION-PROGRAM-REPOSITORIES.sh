#!/usr/bin/env bash
# C19 - provisiona repositórios-base Manhã/Tarde/Noite e sincronizador V2 em paralelo.
# NÃO reinicia/paralisa selector, shadow público, MediaMTX, Nginx ou Harbor.
set -Eeuo pipefail

REPO='MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-'
BRANCH='reorg/project-context-v2'
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
BASE='/srv/tpsmedia/repository/channels/radioprincipal/programacoes'
NEXT='/opt/studiosat/radio-v2-next/radioprincipal'
STATE='/var/lib/studiosat/radio-v2-next/radioprincipal/program-repositories'
PY="$NEXT/program-repository-sync.py"
CFG='/etc/studiosat/radioprincipal-program-repositories.json'
UNIT='/etc/systemd/system/studiosat-radioprincipal-v2-program-repo-sync.service'

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

echo '=============================================================='
echo ' C19 - REPOSITORIOS BASE MANHA / TARDE / NOITE'
echo ' SEM DOWNTIME / SEM RESTART DE AUDIO'
echo '=============================================================='

echo '===== 1. PRODUCTION GUARD ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u BEFORE=$(systemctl is-active "$u" 2>/dev/null || true)"
done

echo '===== 2. CRIAR PASTAS ====='
install -d -o tpsmedia -g tpsmedia -m 2775   "$BASE" "$BASE/manha" "$BASE/tarde" "$BASE/noite"
install -d -o root -g root -m 0755 "$NEXT"
install -d -o root -g root -m 0755 "$STATE"

cat > "$CFG" <<EOF
{
  "schema": "studiosat.radioprincipal.program-repositories.v1",
  "station_id": "radioprincipal",
  "base": "$BASE",
  "repositories": {
    "manha": "$BASE/manha",
    "tarde": "$BASE/tarde",
    "noite": "$BASE/noite"
  },
  "current_symlink": "$BASE/atual",
  "canonical_object_store": "/var/lib/studiosat/radio-v2/media-transfer/objects",
  "canonical_mirror_store": "/srv/tpsmedia/repository/channels/radioprincipal/mirror-store",
  "policy": {
    "radioboss_is_editorial_authority": true,
    "sync_max_seconds": 5,
    "production_cutover": false
  }
}
EOF
chmod 0644 "$CFG"

for p in manha tarde noite; do
  cat > "$BASE/$p/LEIA-ME.txt" <<EOF
STUDIO SAT - RADIO PRINCIPAL
Repositorio-base da programacao: $p

Voce pode colocar aqui os MP3 correspondentes a esta programacao.
Preserve, de preferencia, os mesmos nomes de arquivo usados pelo RadioBOSS.

Esta pasta NAO substitui diretamente a saida publica.
Ela e indexada/sincronizada pela reconstrucao V2 sem derrubar a emissora.
EOF
  chown tpsmedia:tpsmedia "$BASE/$p/LEIA-ME.txt"
  chmod 0664 "$BASE/$p/LEIA-ME.txt"
done

echo '===== 3. INSTALAR SYNC V2 5s ====='
curl -fsSL "$RAW/scripts/radioprincipal/v2/program-repository-sync.py" -o "$PY"
chmod 0755 "$PY"
python3 -m py_compile "$PY"

cat > "$UNIT" <<EOF
[Unit]
Description=Studio Sat RadioPrincipal V2 Program Repository Sync 5s
After=local-fs.target
Wants=local-fs.target

[Service]
Type=simple
User=root
Group=root
Environment=SS_INTERVAL=5
ExecStart=/usr/bin/python3 $PY --watch
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/stations/radioprincipal /var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current /srv/tpsmedia/repository/channels/radioprincipal/mirror-store
ReadWritePaths=$BASE $STATE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now studiosat-radioprincipal-v2-program-repo-sync.service >/dev/null
sleep 3

echo '===== 4. RESULTADO DOS REPOSITORIOS ====='
systemctl is-active studiosat-radioprincipal-v2-program-repo-sync.service
readlink -f "$BASE/atual" 2>/dev/null || true
du -sh "$BASE" "$BASE/manha" "$BASE/tarde" "$BASE/noite" 2>/dev/null || true
find "$BASE" -maxdepth 2 -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.m4a' \) -printf '%h\n' |
  sort | uniq -c || true

echo '===== 5. STATUS V2 ====='
cat "$STATE/status.json" 2>/dev/null || true

echo '===== 6. CONFIRMAR QUE PRODUCAO NAO FOI REINICIADA ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u AFTER=$(systemctl is-active "$u" 2>/dev/null || true)"
done

echo 'PROGRAM_REPOSITORIES_READY=YES'
echo 'PRODUCTION_AUDIO_RESTARTED=NO'
echo 'RESULTADO=C19_OK'
