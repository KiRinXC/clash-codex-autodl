#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/codex_common.sh
. "$SCRIPT_DIR/lib/codex_common.sh"

usage() {
  echo "用法: bash verify_codex.sh [auto|domestic|overseas] [ENV_FILE]"
}

check_relay() {
  local mode="$1"
  local url

  if ! url="$(relay_base_url_for_mode "$mode")"; then
    return 1
  fi
  log_info "正在检查 $mode 中转站: $url"

  if [ "$mode" = "overseas" ]; then
    enable_proxy_env
    if relay_responds_via_proxy "$url" "$CODEX_PROXY_URL"; then
      log_ok "开启代理后国外中转站可访问"
      return 0
    fi
    log_error "开启代理后国外中转站不可访问"
    return 1
  else
    disable_proxy_env
    if relay_responds_direct "$url"; then
      log_ok "关闭代理后国内中转站可访问"
      return 0
    fi
    log_error "关闭代理后国内中转站不可访问"
    return 1
  fi
}

run_codex_smoke_test() {
  local codex_status
  local smoke_timeout
  local tmp_log
  local tmp_output
  local prompt

  require_command codex
  smoke_timeout="${CODEX_SMOKE_TIMEOUT:-180}"
  tmp_log="$(mktemp)"
  tmp_output="$(mktemp)"
  prompt='请只回复: CODEX_RELAY_READY'

  log_info "正在运行 Codex 冒烟测试"
  if command -v timeout >/dev/null 2>&1; then
    set +e
    timeout --kill-after=10s "${smoke_timeout}s" \
      codex exec --skip-git-repo-check --ephemeral --output-last-message "$tmp_output" "$prompt" \
        </dev/null > "$tmp_log" 2>&1
    codex_status="$?"
    set -e
  else
    set +e
    codex exec --skip-git-repo-check --ephemeral --output-last-message "$tmp_output" "$prompt" \
      </dev/null > "$tmp_log" 2>&1
    codex_status="$?"
    set -e
  fi

  cp "$tmp_log" /tmp/codex-bootstrap-smoke.log 2>/dev/null || true

  if grep -q 'CODEX_RELAY_READY' "$tmp_output" || grep -q 'CODEX_RELAY_READY' "$tmp_log"; then
    if [ "$codex_status" = "124" ]; then
      log_warn "Codex 冒烟测试命令在输出预期回复后超时"
    fi
    log_ok "Codex 冒烟测试成功"
    rm -f "$tmp_output" "$tmp_log"
    return 0
  fi

  if [ "$codex_status" = "124" ]; then
    log_error "Codex 冒烟测试在 ${smoke_timeout}s 后超时"
  elif [ "$codex_status" != "0" ]; then
    log_error "Codex 冒烟测试命令失败，退出码为 $codex_status"
  fi
  log_error "Codex 冒烟测试回复中没有包含预期内容"
  cat "$tmp_log" >&2 || true
  rm -f "$tmp_output" "$tmp_log"
  return 1
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

requested_mode="${1:-auto}"
env_file="${2:-.env}"
load_env_file "$env_file"
CODEX_RELAY_MODE="$requested_mode"

codex_audit_host "$env_file"
validate_codex_relay_urls

case "$requested_mode" in
  auto)
    check_relay overseas
    check_relay domestic
    enable_proxy_env
    CODEX_RELAY_MODE="overseas"
    ;;
  domestic | overseas)
    check_relay "$requested_mode"
    ;;
  *)
    log_error "验证模式无效: $requested_mode"
    exit 1
    ;;
esac

codex_switch_relay_mode "$CODEX_RELAY_MODE" "$env_file"
run_codex_smoke_test
