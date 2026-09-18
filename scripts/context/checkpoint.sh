#!/usr/bin/env bash
set -Eeuo pipefail

CORE_ROOT="${CORE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(dirname "$CORE_ROOT") }"
MOBILE_ROOT="${MOBILE_ROOT:-$WORKSPACE_ROOT/Radio-Studio-Sat-Mobile-App}"
PORTAL_ROOT="${PORTAL_ROOT:-$WORKSPACE_ROOT/portal}"
NOTE="${*:-checkpoint manual}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$CORE_ROOT/project-context/checkpoints"
OUT="$OUT_DIR/$TS.md"
mkdir -p "$OUT_DIR"

repo_block() {
  local name="$1" path="$2"
  printf '\n## %s\n\n' "$name"
  if [[ ! -d "$path/.git" ]]; then
    printf -- '- path: `%s`\n- status: repository not found\n' "$path"
    return
  fi
  printf -- '- path: `%s`\n' "$path"
  printf -- '- branch: `%s`\n' "$(git -C "$path" branch --show-current 2>/dev/null || true)"
  printf -- '- head: `%s`\n' "$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  printf -- '- origin: `%s`\n' "$(git -C "$path" remote get-url origin 2>/dev/null || true)"
  printf '\n### Working tree\n\n```text\n'
  git -C "$path" status --short 2>/dev/null || true
  printf '```\n'
  printf '\n### Últimos commits\n\n```text\n'
  git -C "$path" log -5 --oneline --decorate 2>/dev/null || true
  printf '```\n'
}

{
  printf '# Studio Sat — Checkpoint %s\n\n' "$TS"
  printf -- '- gerado em UTC: `%s`\n' "$TS"
  printf -- '- nota: %s\n' "$NOTE"
  printf -- '- modo: somente leitura do Git local; nenhum segredo é coletado.\n'
  repo_block 'Core / OPS' "$CORE_ROOT"
  repo_block 'Mobile' "$MOBILE_ROOT"
  repo_block 'Portal' "$PORTAL_ROOT"
  cat <<'EOF'

## Estado operacional confirmado

Preencher somente com resultado observado nesta sessão:

- NS1:
- NS2:
- Nginx:
- MediaMTX:
- cinco HLS:
- CMS/API:
- RadioBOSS/mirror:

## Problema atual

-

## Próximo passo exato

1.

## Rollback conhecido

-
EOF
} > "$OUT"

printf 'CHECKPOINT=%s\n' "$OUT"
