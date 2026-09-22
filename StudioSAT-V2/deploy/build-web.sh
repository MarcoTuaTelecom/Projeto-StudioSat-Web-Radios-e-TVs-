#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
cargo build --release -p studiosat-web
printf 'OK: %s\n' "$ROOT/target/release/studiosat-web"
