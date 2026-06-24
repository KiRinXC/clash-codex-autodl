#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/codex_common.sh
. "$SCRIPT_DIR/lib/codex_common.sh"

usage() {
  echo "用法: bash verify_codex.sh [current|domestic|overseas]"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

mode="${1:-current}"
load_project_config

case "$mode" in
  current | auto)
    codex-verify
    ;;
  domestic)
    codex-use-in
    codex-verify
    ;;
  overseas)
    codex-use-out
    codex-verify
    ;;
  *)
    log_error "验证模式无效: $mode"
    usage
    exit 1
    ;;
esac
