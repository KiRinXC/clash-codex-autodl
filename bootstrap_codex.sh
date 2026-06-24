#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/codex_common.sh
. "$SCRIPT_DIR/lib/codex_common.sh"

usage() {
  cat <<'USAGE'
用法: bash bootstrap_codex.sh [CONFIG_FILE]

为 clash-codex-autodl 安装 Codex CLI、认证和 shell 启动钩子。
USAGE
}

main() {
  case "${1:-}" in
    --help | -h)
      usage
      return 0
      ;;
  esac

  if [ -n "${1:-}" ] && [ -f "$1" ]; then
    load_project_config "$1"
  else
    load_project_config
  fi

  if [ -z "${OPENAI_API_KEY:-}" ]; then
    log_error "OPENAI_API_KEY 为空。请先在本机配置里填写，或通过 start.sh 完成初始化。"
    exit 1
  fi

  write_codex_auth
  ensure_codex_cli
  install_shell_hook
  log_ok "clash-codex-autodl Codex 初始化完成"
}

main "$@"
