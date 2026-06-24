#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
用法:
  bash uninstall_codex_bootstrap.sh --proxy
  bash uninstall_codex_bootstrap.sh --codex
  bash uninstall_codex_bootstrap.sh --all

兼容旧参数:
  --remove-codex-config
  --remove-local-config
USAGE
}

log_ok() { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }

project_config_dir() {
  printf '%s\n' "${CLASH_CODEX_AUTODL_CONFIG_DIR:-${CODEX_AUTODL_CONFIG_DIR:-$HOME/.config/clash-codex-autodl}}"
}

remove_shell_hooks() {
  if [ -f "$HOME/.bashrc" ]; then
    sed -i '/# clash-autodl-codex begin/,/# clash-autodl-codex end/d' "$HOME/.bashrc"
    sed -i '/# clash-codex-autodl begin/,/# clash-codex-autodl end/d' "$HOME/.bashrc"
    log_ok "已从 ~/.bashrc 移除 clash-codex-autodl 启动钩子"
  fi

  rm -f "$HOME/.codex/clash-codex-autodl.sh" "$HOME/.codex/clash-autodl-codex.sh"
  log_ok "已移除 shell 启动钩子文件"
}

disable_auto_proxy() {
  local config_file
  local tmp_file

  config_file="$(project_config_dir)/config.sh"
  if [ ! -f "$config_file" ]; then
    return 0
  fi

  tmp_file="$(mktemp)"
  if grep -q '^AUTO_PROXY_ON_SHELL_START=' "$config_file"; then
    sed "s/^AUTO_PROXY_ON_SHELL_START=.*/AUTO_PROXY_ON_SHELL_START='false'/" "$config_file" > "$tmp_file"
  else
    cat "$config_file" > "$tmp_file"
    printf "AUTO_PROXY_ON_SHELL_START='false'\n" >> "$tmp_file"
  fi
  mv "$tmp_file" "$config_file"
}

stop_mihomo_processes() {
  local pid old_pids

  if [ -f "$SCRIPT_DIR/mihomo.pid" ]; then
    pid="$(cat "$SCRIPT_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  fi

  old_pids="$(ps -eo pid=,comm= 2>/dev/null | awk '$2 ~ /^(mihomo|mihomo-linux|clash|clash-linux)/ {print $1}' || true)"
  if [ -n "$old_pids" ]; then
    kill $old_pids >/dev/null 2>&1 || true
    sleep 1
    old_pids="$(ps -eo pid=,comm= 2>/dev/null | awk '$2 ~ /^(mihomo|mihomo-linux|clash|clash-linux)/ {print $1}' || true)"
    if [ -n "$old_pids" ]; then
      kill -9 $old_pids >/dev/null 2>&1 || true
    fi
  fi
}

uninstall_proxy() {
  stop_mihomo_processes
  rm -f "$SCRIPT_DIR/mihomo.pid"
  rm -rf "$SCRIPT_DIR/bin" "$SCRIPT_DIR/conf" "$SCRIPT_DIR/logs"
  disable_auto_proxy
  remove_shell_hooks
  log_ok "代理组件已卸载"
}

uninstall_codex() {
  rm -f "$HOME/.codex/config.toml" "$HOME/.codex/auth.json"
  rm -f "$HOME/.local/bin/codex"
  remove_shell_hooks
  log_ok "Codex 配置和本项目安装的 Codex CLI 已卸载"
}

remove_local_config() {
  rm -rf "$(project_config_dir)" "$HOME/.config/clash-autodl-codex"
  log_ok "已移除 clash-codex-autodl 本机配置"
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

did_work=false
for arg in "$@"; do
  case "$arg" in
    --help | -h)
      usage
      exit 0
      ;;
    --proxy)
      uninstall_proxy
      did_work=true
      ;;
    --codex)
      uninstall_codex
      did_work=true
      ;;
    --all)
      uninstall_proxy
      uninstall_codex
      remove_local_config
      did_work=true
      ;;
    --remove-codex-config)
      uninstall_codex
      did_work=true
      ;;
    --remove-local-config)
      remove_local_config
      did_work=true
      ;;
    *)
      log_warn "未知参数: $arg"
      usage
      exit 1
      ;;
  esac
done

if [ "$did_work" != "true" ]; then
  usage
  exit 1
fi
