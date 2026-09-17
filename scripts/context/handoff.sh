#!/usr/bin/env bash
set -Eeuo pipefail

CORE_ROOT="${CORE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CTX="$CORE_ROOT/project-context"
OUT="${1:-$CTX/06-CHAT-HANDOFF.md}"
LATEST="$(find "$CTX/checkpoints" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | tail -n 1 || true)"

need_file() {
  [[ -f "$1" ]] || { echo "arquivo ausente: $1" >&2; exit 1; }
}

need_file "$CTX/00-MASTER.md"
need_file "$CTX/02-DECISIONS.md"
need_file "$CTX/03-NEXT-STEPS.md"

{
  cat <<'EOF'
# Studio Sat — Handoff para novo chat

> Documento gerado a partir do contexto canônico. Leia este arquivo antes de continuar a frente técnica.

EOF
  printf 'Gerado em UTC: `%s`\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n---\n\n'
  cat "$CTX/00-MASTER.md"
  printf '\n\n---\n\n'
  cat "$CTX/02-DECISIONS.md"
  printf '\n\n---\n\n'
  cat "$CTX/03-NEXT-STEPS.md"
  if [[ -n "$LATEST" ]]; then
    printf '\n\n---\n\n# Último checkpoint\n\n'
    cat "$LATEST"
  else
    printf '\n\n---\n\n# Último checkpoint\n\nNenhum checkpoint encontrado ainda.\n'
  fi
  cat <<'EOF'

---

# Instrução para o próximo chat

1. Não trate o projeto como iniciado do zero.
2. Use o MASTER como fonte do estado arquitetural.
3. Use o último checkpoint apenas para fatos operacionais que estejam explicitamente confirmados nele.
4. Não reverta decisões registradas sem explicar motivo, risco e rollback.
5. Analise primeiro o erro/log concreto antes de propor reinstalação ampla.
6. Ao concluir uma mudança real, gere novo checkpoint e atualize os documentos canônicos necessários.
EOF
} > "$OUT"

printf 'HANDOFF=%s\n' "$OUT"
