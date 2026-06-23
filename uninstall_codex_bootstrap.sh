#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "用法: bash uninstall_codex_bootstrap.sh [--remove-codex-config]"
  exit 0
fi

if [ -f "$HOME/.bashrc" ]; then
  sed -i '/# clash-autodl-codex begin/,/# clash-autodl-codex end/d' "$HOME/.bashrc"
  echo "[成功] 已从 ~/.bashrc 移除 clash-Autodl-codex 启动钩子"
fi

rm -f "$HOME/.codex/clash-autodl-codex.sh"
echo "[成功] 已移除代理钩子文件"

if [ "${1:-}" = "--remove-codex-config" ]; then
  rm -f "$HOME/.codex/config.toml" "$HOME/.codex/auth.json"
  echo "[成功] 已移除 ~/.codex/config.toml 和 ~/.codex/auth.json"
fi
