#!/usr/bin/env bash

set -o pipefail

DEFAULT_DOMESTIC_BASE_URL=""
DEFAULT_OVERSEAS_BASE_URL=""
DEFAULT_PROXY_URL="http://127.0.0.1:7890"
DEFAULT_MIHOMO_CONTROLLER_URL="http://127.0.0.1:6006"
DEFAULT_CODEX_PROXY_GROUP="CodexProxy"
DEFAULT_CODEX_MODEL="gpt-5.4"

if [ -z "${CODEX_AUTODL_REPO_ROOT:-}" ]; then
  CODEX_AUTODL_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

log_info() { printf '\033[1;34m[信息]\033[0m %s\n' "$*"; }
log_ok() { printf '\033[0;32m[成功]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[1;33m[警告]\033[0m %s\n' "$*"; }
log_error() { printf '\033[0;31m[失败]\033[0m %s\n' "$*" >&2; }

load_env_file() {
  local env_file="${1:-.env}"

  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi

  CODEX_RELAY_MODE="${CODEX_RELAY_MODE:-auto}"
  CODEX_DOMESTIC_BASE_URL="${CODEX_DOMESTIC_BASE_URL:-$DEFAULT_DOMESTIC_BASE_URL}"
  CODEX_OVERSEAS_BASE_URL="${CODEX_OVERSEAS_BASE_URL:-$DEFAULT_OVERSEAS_BASE_URL}"
  CODEX_PROXY_URL="${CODEX_PROXY_URL:-$DEFAULT_PROXY_URL}"
  CODEX_MIHOMO_CONTROLLER_URL="${CODEX_MIHOMO_CONTROLLER_URL:-$DEFAULT_MIHOMO_CONTROLLER_URL}"
  CODEX_PROXY_GROUP="${CODEX_PROXY_GROUP:-$DEFAULT_CODEX_PROXY_GROUP}"
  CODEX_MODEL="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
  CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-$CODEX_MODEL}"
  AUTO_PROXY_ON_SHELL_START="${AUTO_PROXY_ON_SHELL_START:-true}"
}

validate_codex_relay_urls() {
  local missing=0

  if [ -z "${CODEX_DOMESTIC_BASE_URL:-}" ]; then
    log_error "CODEX_DOMESTIC_BASE_URL 为空。请先在 .env 中填写国内中转站地址。"
    missing=1
  fi

  if [ -z "${CODEX_OVERSEAS_BASE_URL:-}" ]; then
    log_error "CODEX_OVERSEAS_BASE_URL 为空。请先在 .env 中填写国外中转站地址。"
    missing=1
  fi

  return "$missing"
}

proxy_env_is_active() {
  [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]
}

local_proxy_is_listening() {
  local proxy_url="${1:-$CODEX_PROXY_URL}"
  local host_port port

  host_port="${proxy_url#http://}"
  host_port="${host_port#https://}"
  port="${host_port##*:}"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":${port}[[:space:]]"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i ":${port}" >/dev/null 2>&1
  else
    curl -sS --max-time 2 -x "$proxy_url" "$CODEX_OVERSEAS_BASE_URL" >/dev/null 2>&1
  fi
}

proxy_process_is_running() {
  ps -eo comm= 2>/dev/null | grep -Eq '^(mihomo|mihomo-linux|clash|clash-linux)'
}

detect_relay_mode() {
  case "${CODEX_RELAY_MODE:-auto}" in
    domestic | overseas)
      printf '%s\n' "$CODEX_RELAY_MODE"
      ;;
    auto)
      if proxy_env_is_active; then
        printf 'overseas\n'
      else
        printf 'domestic\n'
      fi
      ;;
    *)
      log_error "CODEX_RELAY_MODE 无效: $CODEX_RELAY_MODE"
      return 1
      ;;
  esac
}

relay_base_url_for_mode() {
  case "$1" in
    domestic)
      if [ -z "$CODEX_DOMESTIC_BASE_URL" ]; then
        log_error "CODEX_DOMESTIC_BASE_URL 为空。请先在 .env 中填写国内中转站地址。"
        return 1
      fi
      printf '%s\n' "$CODEX_DOMESTIC_BASE_URL"
      ;;
    overseas)
      if [ -z "$CODEX_OVERSEAS_BASE_URL" ]; then
        log_error "CODEX_OVERSEAS_BASE_URL 为空。请先在 .env 中填写国外中转站地址。"
        return 1
      fi
      printf '%s\n' "$CODEX_OVERSEAS_BASE_URL"
      ;;
    *)
      log_error "中转模式无效: $1"
      return 1
      ;;
  esac
}

enable_proxy_env() {
  export http_proxy="$CODEX_PROXY_URL"
  export https_proxy="$CODEX_PROXY_URL"
  export HTTP_PROXY="$CODEX_PROXY_URL"
  export HTTPS_PROXY="$CODEX_PROXY_URL"
  export no_proxy="127.0.0.1,localhost"
  export NO_PROXY="127.0.0.1,localhost"
  log_ok "代理已开启: $CODEX_PROXY_URL"
}

disable_proxy_env() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
  log_ok "代理已关闭"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "缺少命令: $1"
    return 1
  }
}

codex_audit_host() {
  local env_file="${1:-${CODEX_AUTODL_ENV_FILE:-.env}}"
  local mode

  load_env_file "$env_file"

  log_info "主机: $(hostname 2>/dev/null || echo unknown)"
  log_info "用户: $(id -un 2>/dev/null || echo unknown)"
  log_info "Shell: ${SHELL:-unknown}"
  log_info "Codex 配置: ${HOME}/.codex/config.toml"

  if [ -f "$HOME/.codex/config.toml" ]; then
    log_ok "Codex 配置文件存在"
  else
    log_warn "Codex 配置文件不存在"
  fi

  if [ -f "$HOME/.codex/auth.json" ]; then
    log_ok "Codex 认证文件存在"
  else
    log_warn "Codex 认证文件不存在"
  fi

  for cmd in codex curl wget python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log_ok "已找到 $cmd: $(command -v "$cmd")"
    else
      log_warn "未找到 $cmd"
    fi
  done

  if proxy_process_is_running; then
    log_ok "检测到 Mihomo/Clash 进程"
  else
    log_warn "未检测到 Mihomo/Clash 进程"
  fi

  if proxy_env_is_active; then
    log_ok "当前 shell 已设置代理环境变量"
  else
    log_warn "当前 shell 未设置代理环境变量"
  fi

  log_info "国内中转站: ${CODEX_DOMESTIC_BASE_URL:-未设置}"
  log_info "国外中转站: ${CODEX_OVERSEAS_BASE_URL:-未设置}"
  log_info "检测到的中转模式: $(detect_relay_mode)"
}

codex_switch_relay_mode() {
  local mode="$1"
  local env_file="${2:-${CODEX_AUTODL_ENV_FILE:-.env}}"

  load_env_file "$env_file"
  validate_codex_relay_urls || return 1
  CODEX_RELAY_MODE="$mode"

  mode="$(detect_relay_mode)" || return 1
  local base_url config_file
  base_url="$(relay_base_url_for_mode "$mode")" || return 1

  mkdir -p "$HOME/.codex"
  config_file="$HOME/.codex/config.toml"

  if [ -f "$config_file" ] && [ ! -f "$config_file.codex-bootstrap.bak" ]; then
    cp "$config_file" "$config_file.codex-bootstrap.bak"
  fi

  cat > "$config_file" <<EOF
model_provider = "OpenAI"
model = "$CODEX_MODEL"
review_model = "$CODEX_REVIEW_MODEL"
model_reasoning_effort = "xhigh"
disable_response_storage = true
network_access = "enabled"
windows_wsl_setup_acknowledged = true
model_context_window = 1000000
model_auto_compact_token_limit = 900000

[model_providers.OpenAI]
name = "OpenAI"
base_url = "$base_url"
wire_api = "responses"
requires_openai_auth = true
EOF

  chmod 600 "$config_file" 2>/dev/null || true
  log_ok "Codex 配置已切换到 $mode: $base_url"
}

proxy_on() {
  codex_switch_relay_mode overseas "${CODEX_AUTODL_ENV_FILE:-.env}" || return 1
  enable_proxy_env
  log_ok "proxy_on 已开启: $CODEX_PROXY_URL"
}

proxy_off() {
  disable_proxy_env
  codex_switch_relay_mode domestic "${CODEX_AUTODL_ENV_FILE:-.env}" || return 1
  log_ok "proxy_off 已关闭当前 shell 的代理"
}

proxy_pick() {
  require_command python3 || return 1

  local tmp_py
  tmp_py="$(mktemp)"
  cat > "$tmp_py" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base = os.environ.get("CODEX_MIHOMO_CONTROLLER_URL", "http://127.0.0.1:6006").rstrip("/")
group = os.environ.get("CODEX_PROXY_GROUP", "CodexProxy")


def fetch_state():
    with urllib.request.urlopen(f"{base}/proxies/{group}", timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def set_proxy(name):
    payload = json.dumps({"name": name}).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/proxies/{group}",
        data=payload,
        method="PUT",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def render_state(state):
    current = state.get("now") or "DIRECT"
    all_names = state.get("all") or []
    choices = ["DIRECT"]
    for name in all_names:
        if name != "DIRECT" and name not in choices:
            choices.append(name)
    print(f"当前选择: {current}")
    print(f"选择组: {group}")
    print("可用节点:")
    for idx, name in enumerate(choices, 1):
        marker = " [当前]" if name == current else ""
        print(f"  {idx}. {name}{marker}")
    return choices


try:
    choices = render_state(fetch_state())
except urllib.error.URLError as exc:
    print(f"无法连接 Mihomo 控制器 {base}: {exc}", file=sys.stderr)
    raise SystemExit(1)

while True:
    try:
        answer = input("请输入节点编号（r=刷新，q=退出）: ").strip().lower()
    except EOFError:
        print(file=sys.stderr)
        raise SystemExit(1)

    if answer in {"q", "quit", "exit"}:
        raise SystemExit(0)
    if answer in {"r", "refresh"}:
        choices = render_state(fetch_state())
        continue
    if answer.isdigit():
        index = int(answer)
        if 1 <= index <= len(choices):
            target = choices[index - 1]
            try:
                set_proxy(target)
            except urllib.error.URLError as exc:
                print(f"切换 {group} 失败: {exc}", file=sys.stderr)
                raise SystemExit(1)
            print(f"已选择: {target}")
            raise SystemExit(0)
    print("无效选择")
PY
  if CODEX_MIHOMO_CONTROLLER_URL="$CODEX_MIHOMO_CONTROLLER_URL" \
    CODEX_PROXY_GROUP="$CODEX_PROXY_GROUP" \
    python3 "$tmp_py"; then
    rm -f "$tmp_py"
    return 0
  else
    local status="$?"
    rm -f "$tmp_py"
    return "$status"
  fi
}

relay_responds_direct() {
  local url="$1"
  local candidate code

  for candidate in "$url" "${url%/}/responses" "${url%/}/v1/models"; do
    code="$(curl -sSIL --max-time 15 -o /dev/null -w '%{http_code}' "$candidate" 2>/dev/null || true)"
    if [ "$code" = "000" ] || [ -z "$code" ]; then
      code="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' "$candidate" 2>/dev/null || true)"
    fi
    if [ "$code" != "000" ] && [ -n "$code" ]; then
      return 0
    fi
  done

  return 1
}

relay_responds_via_proxy() {
  local url="$1"
  local proxy_url="${2:-$CODEX_PROXY_URL}"
  local candidate code

  for candidate in "$url" "${url%/}/responses" "${url%/}/v1/models"; do
    code="$(curl -sSIL --max-time 15 -x "$proxy_url" -o /dev/null -w '%{http_code}' "$candidate" 2>/dev/null || true)"
    if [ "$code" = "000" ] || [ -z "$code" ]; then
      code="$(curl -sS --max-time 15 -x "$proxy_url" -o /dev/null -w '%{http_code}' "$candidate" 2>/dev/null || true)"
    fi
    if [ "$code" != "000" ] && [ -n "$code" ]; then
      return 0
    fi
  done

  return 1
}
