#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "用法: bash uninstall_codex_bootstrap.sh [--remove-codex-config] [--remove-local-config]"
  exit 0
fi

if [ -f "$HOME/.bashrc" ]; then
  sed -i '/# clash-autodl-codex begin/,/# clash-autodl-codex end/d' "$HOME/.bashrc"
  echo "[OK] 已从 ~/.bashrc 移除 clash-Autodl-codex 启动钩子"
fi

rm -f "$HOME/.codex/clash-autodl-codex.sh"
echo "[OK] 已移除代理钩子文件"

for arg in "$@"; do
  case "$arg" in
    --remove-codex-config)
      rm -f "$HOME/.codex/config.toml" "$HOME/.codex/auth.json"
      echo "[OK] 已移除 ~/.codex/config.toml 和 ~/.codex/auth.json"
      ;;
    --remove-local-config)
      rm -rf "${CODEX_AUTODL_CONFIG_DIR:-$HOME/.config/clash-autodl-codex}"
      echo "[OK] 已移除 clash-Autodl-codex 本机配置"
      ;;
  esac
done
