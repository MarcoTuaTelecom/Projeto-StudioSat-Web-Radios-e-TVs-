#!/usr/bin/env bash
set -Eeuo pipefail

ID="${1:-}"
REPO="${2:-}"
SCOPE="${3:-}"

[[ -n "$ID" ]] || { echo "uso: $0 WORKSTREAM_ID [repositorio] [escopo]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TARGET="$ROOT/project-context/chats/active/${ID}.md"
TEMPLATE="$ROOT/project-context/chats/ACTIVE-TEMPLATE.md"

[[ -f "$TEMPLATE" ]] || { echo "template ausente: $TEMPLATE" >&2; exit 1; }
[[ ! -e "$TARGET" ]] || { echo "workstream ja existe: $TARGET" >&2; exit 1; }

mkdir -p "$(dirname "$TARGET")"
cp "$TEMPLATE" "$TARGET"

python3 - "$TARGET" "$ID" "$REPO" "$SCOPE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
id=sys.argv[2]
repo=sys.argv[3] or '<repo>'
scope=sys.argv[4] or '<uma responsabilidade técnica>'
s=p.read_text(encoding='utf-8')
s=s.replace('<WORKSTREAM_ID>', id)
s=s.replace('<repo>', repo, 1)
s=s.replace('<uma responsabilidade técnica>', scope, 1)
p.write_text(s,encoding='utf-8')
PY

echo "WORKSTREAM_CREATED=$TARGET"
echo "Revise o arquivo, preencha estado comprovado e commit antes de iniciar a nova aba."
