#!/usr/bin/env bash
set -Eeuo pipefail

WORKSTREAM_ID="${1:-}"
[[ -n "$WORKSTREAM_ID" ]] || { echo "uso: $0 WORKSTREAM_ID" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MASTER="$ROOT/project-context/00-MASTER.md"
DECISIONS="$ROOT/project-context/02-DECISIONS.md"
BRIDGE="$ROOT/project-context/06-CHAT-BRIDGE.md"
ACTIVE="$ROOT/project-context/chats/active/${WORKSTREAM_ID}.md"
OUTDIR="$ROOT/project-context/generated"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUTDIR/HANDOFF-${WORKSTREAM_ID}-${TS}.md"

for f in "$MASTER" "$DECISIONS" "$BRIDGE" "$ACTIVE"; do
  [[ -f "$f" ]] || { echo "arquivo obrigatorio ausente: $f" >&2; exit 1; }
done

mkdir -p "$OUTDIR"

cat > "$OUT" <<EOF
# Studio Sat — Chat Handoff Pack

- WORKSTREAM_ID: \`$WORKSTREAM_ID\`
- generated_utc: \`$TS\`
- repository: \`MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-\`

## Instrução para a nova conversa

Você está continuando um workstream existente do projeto Studio Sat.
Não reinicie o projeto e não presuma que a conversa anterior é a fonte oficial.
Leia este pacote, trate o MASTER/DECISIONS/ACTIVE STATE como estado persistente e continue do próximo passo registrado.
Antes de mudanças destrutivas ou cutover, reconfirme o estado vivo.
Ao concluir uma etapa, produza um resumo estruturado para atualizar o arquivo ACTIVE deste workstream.

---

## MASTER

EOF
cat "$MASTER" >> "$OUT"
cat >> "$OUT" <<'EOF'

---

## DECISIONS

EOF
cat "$DECISIONS" >> "$OUT"
cat >> "$OUT" <<'EOF'

---

## CHAT BRIDGE

EOF
cat "$BRIDGE" >> "$OUT"
cat >> "$OUT" <<EOF

---

## ACTIVE WORKSTREAM — $WORKSTREAM_ID

EOF
cat "$ACTIVE" >> "$OUT"

cat <<EOF
HANDOFF_READY=$OUT

Cole na nova aba:

WORKSTREAM_ID: $WORKSTREAM_ID
Estou continuando este workstream do Studio Sat. Use o arquivo HANDOFF anexado como estado inicial. Não reinicie etapas já concluídas. Continue do próximo passo registrado e, ao final, gere o bloco de atualização do ACTIVE STATE.
EOF
