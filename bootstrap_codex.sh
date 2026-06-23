#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/codex_common.sh
. "$SCRIPT_DIR/lib/codex_common.sh"

usage() {
  cat <<'USAGE'
用法: bash bootstrap_codex.sh [ENV_FILE]

为 clash-Autodl-codex 配置 Codex、Mihomo 和代理命令。
USAGE
}

write_codex_auth() {
  mkdir -p "$HOME/.codex"

  if command -v codex >/dev/null 2>&1; then
    if printf '%s\n' "$OPENAI_API_KEY" | codex login --with-api-key >/dev/null 2>&1; then
      chmod 600 "$HOME/.codex/auth.json" 2>/dev/null || true
      log_ok "已通过 codex login 导入 Codex API key"
      return 0
    fi
    log_warn "codex login 失败，改为直接写入 ~/.codex/auth.json"
  fi

  printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "$OPENAI_API_KEY" > "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json"
  log_ok "Codex 认证已写入 ~/.codex/auth.json"
}

ensure_codex_cli() {
  if command -v codex >/dev/null 2>&1; then
    log_ok "已找到 Codex CLI: $(command -v codex)"
    return 0
  fi

  log_info "未找到 Codex CLI，尝试官方独立安装器"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh; then
      if command -v codex >/dev/null 2>&1; then
        log_ok "已通过官方独立安装器安装 Codex CLI"
        return 0
      fi
    fi
    log_warn "独立安装器没有生成可用的 codex 命令"
  fi

  log_info "尝试使用 npm 方式安装 @openai/codex"
  if command -v npm >/dev/null 2>&1; then
    npm install -g @openai/codex
    if command -v codex >/dev/null 2>&1; then
      log_ok "已通过 npm 安装 Codex CLI"
      return 0
    fi
  fi

  log_error "缺少 Codex CLI。请先安装 Codex，或者安装 Node.js/npm 后重新执行脚本。"
  return 1
}

install_visible_proxy_hook() {
  local hook_file="$HOME/.codex/clash-autodl-codex.sh"

  mkdir -p "$HOME/.codex"
  cat > "$hook_file" <<EOF
# 由 clash-Autodl-codex 管理
export CODEX_AUTODL_REPO_ROOT="$SCRIPT_DIR"
export CODEX_AUTODL_ENV_FILE="$env_file_path"

# shellcheck source=/dev/null
if [ -f "\${CODEX_AUTODL_REPO_ROOT}/lib/codex_common.sh" ]; then
  . "\${CODEX_AUTODL_REPO_ROOT}/lib/codex_common.sh"
  load_env_file "\${CODEX_AUTODL_ENV_FILE}"
  echo -e "\\033[0;32m[成功]\\033[0m clash-Autodl-codex 命令已加载: proxy_on, proxy_off, proxy_pick"
  if [ "\${AUTO_PROXY_ON_SHELL_START}" = "true" ]; then
    proxy_on || true
  fi
else
    echo -e "\\033[1;33m[警告]\\033[0m clash-Autodl-codex 仓库不存在: \${CODEX_AUTODL_REPO_ROOT}"
fi
EOF
  chmod 600 "$hook_file" 2>/dev/null || true

  if [ "$AUTO_PROXY_ON_SHELL_START" = "true" ]; then
    touch "$HOME/.bashrc"
    sed -i '/# clash-autodl-codex begin/,/# clash-autodl-codex end/d' "$HOME/.bashrc"
    {
      echo "# clash-autodl-codex begin"
      echo "[ -f \"$hook_file\" ] && . \"$hook_file\""
      echo "# clash-autodl-codex end"
    } >> "$HOME/.bashrc"
    log_ok "已在 ~/.bashrc 中安装自动代理钩子"
  else
    log_warn "AUTO_PROXY_ON_SHELL_START 不是 true；已写入钩子文件，但未启用到 shell"
  fi
}

run_clash_bootstrap() {
  log_info "正在从 CLASH_URL 启动 Clash/Mihomo 安装流程"
  bash "$SCRIPT_DIR/setup_mihomo.sh" "$env_file_path"
}

check_overseas_relay_with_proxy() {
  log_info "正在测试开启代理后的国外中转站"
  enable_proxy_env
  if relay_responds_via_proxy "$CODEX_OVERSEAS_BASE_URL" "$CODEX_PROXY_URL"; then
    log_ok "开启代理后国外中转站可访问: $CODEX_OVERSEAS_BASE_URL"
    return 0
  fi
  log_error "开启代理后国外中转站不可访问: $CODEX_OVERSEAS_BASE_URL"
  return 1
}

check_domestic_relay_without_proxy() {
  log_info "正在测试关闭代理后的国内中转站"
  disable_proxy_env
  if relay_responds_direct "$CODEX_DOMESTIC_BASE_URL"; then
    log_ok "关闭代理后国内中转站可访问: $CODEX_DOMESTIC_BASE_URL"
    return 0
  fi
  log_error "关闭代理后国内中转站不可访问: $CODEX_DOMESTIC_BASE_URL"
  return 1
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

env_file="${1:-.env}"
if [[ "$env_file" = /* ]]; then
  env_file_path="$env_file"
else
  env_file_path="$SCRIPT_DIR/$env_file"
fi

load_env_file "$env_file_path"

codex_audit_host "$env_file_path"
validate_codex_relay_urls

if [ -z "${OPENAI_API_KEY:-}" ]; then
  log_error "OPENAI_API_KEY 为空。请先在目标主机的 $env_file_path 中填写，或在运行前导出该变量。"
  exit 1
fi

if [ -z "${CLASH_URL:-}" ]; then
  log_error "CLASH_URL 为空。请先在目标主机的 $env_file_path 中填写 Clash 订阅地址。"
  exit 1
fi

write_codex_auth
run_clash_bootstrap
enable_proxy_env
ensure_codex_cli
install_visible_proxy_hook
check_overseas_relay_with_proxy
check_domestic_relay_without_proxy

if [ "$AUTO_PROXY_ON_SHELL_START" = "true" ]; then
  enable_proxy_env
fi

codex_switch_relay_mode auto "$env_file_path"
log_ok "clash-Autodl-codex 初始化完成"
