#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${1:-.env}"

bash "$SCRIPT_DIR/bootstrap_codex.sh" "$env_file"
bash "$SCRIPT_DIR/verify_codex.sh" auto "$env_file"
