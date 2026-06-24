#!/usr/bin/env bash

set -o pipefail

DEFAULT_CLASH_URL=""
DEFAULT_DOMESTIC_BASE_URL=""
DEFAULT_OVERSEAS_BASE_URL=""
DEFAULT_PROXY_URL="http://127.0.0.1:7890"
DEFAULT_MIHOMO_CONTROLLER_URL="http://127.0.0.1:6006"
DEFAULT_CODEX_PROXY_GROUP="CodexProxy"
DEFAULT_CODEX_MODEL="gpt-5.4"
DEFAULT_ACTIVE_RELAY=""
DEFAULT_AUTO_CODEX_CHECK_ON_SHELL_START="true"

if [ -z "${CODEX_AUTODL_REPO_ROOT:-}" ]; then
  CODEX_AUTODL_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_ok() { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_error() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; }

project_config_dir() {
  printf '%s\n' "${CODEX_AUTODL_CONFIG_DIR:-$HOME/.config/clash-autodl-codex}"
}

project_config_file() {
  if [ -n "${CODEX_AUTODL_CONFIG_FILE:-}" ]; then
    printf '%s\n' "$CODEX_AUTODL_CONFIG_FILE"
  else
    printf '%s/config.sh\n' "$(project_config_dir)"
  fi
}

apply_project_defaults() {
  CLASH_URL="${CLASH_URL:-$DEFAULT_CLASH_URL}"
  CODEX_DOMESTIC_BASE_URL="${CODEX_DOMESTIC_BASE_URL:-$DEFAULT_DOMESTIC_BASE_URL}"
  CODEX_OVERSEAS_BASE_URL="${CODEX_OVERSEAS_BASE_URL:-$DEFAULT_OVERSEAS_BASE_URL}"
  CODEX_ACTIVE_RELAY="${CODEX_ACTIVE_RELAY:-$DEFAULT_ACTIVE_RELAY}"
  CODEX_RELAY_MODE="${CODEX_RELAY_MODE:-auto}"
  CODEX_PROXY_URL="${CODEX_PROXY_URL:-$DEFAULT_PROXY_URL}"
  CODEX_MIHOMO_CONTROLLER_URL="${CODEX_MIHOMO_CONTROLLER_URL:-$DEFAULT_MIHOMO_CONTROLLER_URL}"
  CODEX_PROXY_GROUP="${CODEX_PROXY_GROUP:-$DEFAULT_CODEX_PROXY_GROUP}"
  CODEX_MODEL="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
  CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-$CODEX_MODEL}"
  AUTO_CODEX_CHECK_ON_SHELL_START="${AUTO_CODEX_CHECK_ON_SHELL_START:-$DEFAULT_AUTO_CODEX_CHECK_ON_SHELL_START}"
  AUTO_PROXY_ON_SHELL_START="${AUTO_PROXY_ON_SHELL_START:-false}"
}

load_project_config() {
  local config_file="${1:-$(project_config_file)}"

  if [ -f "$config_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$config_file"
    set +a
  fi

  apply_project_defaults
}

load_env_file() {
  local env_file="${1:-.env}"

  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi

  apply_project_defaults
}

shell_single_quote() {
  local value="${1:-}"
  local escaped
  escaped="$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$escaped"
}

write_config_value() {
  local name="$1"
  local value="${!name:-}"

  printf '%s=' "$name"
  shell_single_quote "$value"
  printf '\n'
}

save_project_config() {
  local config_file="${1:-$(project_config_file)}"
  local config_dir
  local tmp_file

  apply_project_defaults
  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"
  tmp_file="$(mktemp)"

  {
    write_config_value CLASH_URL
    write_config_value CODEX_DOMESTIC_BASE_URL
    write_config_value CODEX_OVERSEAS_BASE_URL
    write_config_value CODEX_ACTIVE_RELAY
    write_config_value CODEX_PROXY_URL
    write_config_value CODEX_MIHOMO_CONTROLLER_URL
    write_config_value CODEX_PROXY_GROUP
    write_config_value CODEX_MODEL
    write_config_value CODEX_REVIEW_MODEL
    write_config_value AUTO_CODEX_CHECK_ON_SHELL_START
  } > "$tmp_file"

  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$config_file"
  chmod 600 "$config_file" 2>/dev/null || true
}

validate_http_url() {
  local name="$1"
  local value="$2"

  case "$value" in
    http://* | https://*) return 0 ;;
    *)
      log_error "$name 必须以 http:// 或 https:// 开头"
      return 1
      ;;
  esac
}

validate_codex_relay_urls() {
  local missing=0

  if [ -z "${CODEX_DOMESTIC_BASE_URL:-}" ]; then
    log_error "CODEX_DOMESTIC_BASE_URL 为空。请先配置国内/直连中转站地址。"
    missing=1
  else
    validate_http_url CODEX_DOMESTIC_BASE_URL "$CODEX_DOMESTIC_BASE_URL" || missing=1
  fi

  if [ -z "${CODEX_OVERSEAS_BASE_URL:-}" ]; then
    log_error "CODEX_OVERSEAS_BASE_URL 为空。请先配置国外/代理中转站地址。"
    missing=1
  else
    validate_http_url CODEX_OVERSEAS_BASE_URL "$CODEX_OVERSEAS_BASE_URL" || missing=1
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
    curl -sS --max-time 2 -x "$proxy_url" https://example.com >/dev/null 2>&1
  fi
}

proxy_process_is_running() {
  ps -eo comm= 2>/dev/null | grep -Eq '^(mihomo|mihomo-linux|clash|clash-linux)'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "缺少命令: $1"
    return 1
  }
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

proxy_on() {
  load_project_config
  enable_proxy_env
}

proxy_off() {
  disable_proxy_env
}

current_proxy_node() {
  local tmp_py
  tmp_py="$(mktemp)"
  cat > "$tmp_py" <<'PY'
import json
import os
import urllib.error
import urllib.request

base = os.environ.get("CODEX_MIHOMO_CONTROLLER_URL", "http://127.0.0.1:6006").rstrip("/")
group = os.environ.get("CODEX_PROXY_GROUP", "CodexProxy")

try:
    with urllib.request.urlopen(f"{base}/proxies/{group}", timeout=3) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    print(payload.get("now") or "DIRECT")
except Exception:
    print("unknown")
PY
  CODEX_MIHOMO_CONTROLLER_URL="$CODEX_MIHOMO_CONTROLLER_URL" \
    CODEX_PROXY_GROUP="$CODEX_PROXY_GROUP" \
    python3 "$tmp_py"
  rm -f "$tmp_py"
}

proxy_status() {
  load_project_config

  log_info "代理: $(proxy_env_is_active && printf '已开启' || printf '未开启')"
  log_info "代理地址: $CODEX_PROXY_URL"
  log_info "Mihomo: $(proxy_process_is_running && printf '运行中' || printf '未运行')"
  if command -v python3 >/dev/null 2>&1; then
    log_info "当前节点: $(current_proxy_node)"
  else
    log_warn "当前节点: 未检测，缺少 python3"
  fi
}

detect_relay_mode() {
  case "${CODEX_ACTIVE_RELAY:-${CODEX_RELAY_MODE:-auto}}" in
    domestic | overseas)
      printf '%s\n' "${CODEX_ACTIVE_RELAY:-$CODEX_RELAY_MODE}"
      ;;
    auto)
      if proxy_env_is_active; then
        printf 'overseas\n'
      else
        printf 'domestic\n'
      fi
      ;;
    "")
      printf 'domestic\n'
      ;;
    *)
      log_error "Codex 中转模式无效: ${CODEX_ACTIVE_RELAY:-$CODEX_RELAY_MODE}"
      return 1
      ;;
  esac
}

relay_base_url_for_mode() {
  case "$1" in
    domestic)
      if [ -z "$CODEX_DOMESTIC_BASE_URL" ]; then
        log_error "CODEX_DOMESTIC_BASE_URL 为空。请先配置国内/直连中转站地址。"
        return 1
      fi
      printf '%s\n' "$CODEX_DOMESTIC_BASE_URL"
      ;;
    overseas)
      if [ -z "$CODEX_OVERSEAS_BASE_URL" ]; then
        log_error "CODEX_OVERSEAS_BASE_URL 为空。请先配置国外/代理中转站地址。"
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

write_codex_config_for_mode() {
  local mode="$1"
  local base_url
  local config_file

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
  CODEX_ACTIVE_RELAY="$mode"
  save_project_config
  log_ok "Codex 中转站已切换到 $mode: $base_url"
}

inject_codex_overseas_rule_into_mihomo_config() {
  local config_file="$CODEX_AUTODL_REPO_ROOT/conf/config.yaml"
  local yq_binary="$CODEX_AUTODL_REPO_ROOT/bin/yq"
  local overseas_host

  load_project_config

  if [ -z "${CODEX_OVERSEAS_BASE_URL:-}" ]; then
    log_warn "未配置 CODEX_OVERSEAS_BASE_URL，跳过 Mihomo 海外规则更新"
    return 0
  fi

  if [ ! -f "$config_file" ]; then
    log_warn "未找到 Mihomo 配置文件: $config_file"
    return 0
  fi

  if [ ! -x "$yq_binary" ]; then
    log_warn "未找到 yq 工具: $yq_binary"
    return 0
  fi

  overseas_host="$(python3 - "$CODEX_OVERSEAS_BASE_URL" <<'PY'
import sys
from urllib.parse import urlparse

host = urlparse(sys.argv[1]).hostname
if not host:
    raise SystemExit(1)
print(host)
PY
)"

  CODEX_OVERSEAS_HOST="$overseas_host" "$yq_binary" eval -i '
    ."mixed-port" = (.["mixed-port"] // 7890) |
    .mode = "rule" |
    ."external-controller" = (.["external-controller"] // "127.0.0.1:6006") |
    ."external-ui" = (.["external-ui"] // "dashboard") |
    .rules = (
      if strenv(CODEX_OVERSEAS_HOST) == "" then
        (.rules // [])
      else
        ["DOMAIN," + strenv(CODEX_OVERSEAS_HOST) + ",CodexProxy"] +
        ((.rules // []) | map(select(. != ("DOMAIN," + strenv(CODEX_OVERSEAS_HOST) + ",CodexProxy"))))
      end
    ) |
    ."proxy-groups" = (
      if ((."proxy-groups" // []) | map(.name) | index("CodexProxy")) == null then
        ([{
          "name": "CodexProxy",
          "type": "select",
          "proxies": ((.proxies // []) | map(.name))
        }] + (."proxy-groups" // []))
      else
        (."proxy-groups" // [])
      end
    )
  ' "$config_file"

  log_ok "已更新 Mihomo 海外中转规则: $overseas_host"
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

write_codex_auth() {
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    log_error "OPENAI_API_KEY 为空，无法写入 Codex 认证。"
    return 1
  fi

  mkdir -p "$HOME/.codex"
  printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "$(json_escape "$OPENAI_API_KEY")" > "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json" 2>/dev/null || true
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

install_shell_hook() {
  local hook_file="$HOME/.codex/clash-autodl-codex.sh"
  local config_dir

  config_dir="$(project_config_dir)"
  mkdir -p "$HOME/.codex"
  cat > "$hook_file" <<EOF
# 由 clash-Autodl-codex 管理
export CODEX_AUTODL_REPO_ROOT="$CODEX_AUTODL_REPO_ROOT"
export CODEX_AUTODL_CONFIG_DIR="$config_dir"

# shellcheck source=/dev/null
if [ -f "\${CODEX_AUTODL_REPO_ROOT}/lib/codex_common.sh" ]; then
  . "\${CODEX_AUTODL_REPO_ROOT}/lib/codex_common.sh"
  load_project_config
  log_info "clash-Autodl-codex 命令已加载"
  proxy_status || true
  codex_relay_status || true
  if [ "\${AUTO_CODEX_CHECK_ON_SHELL_START}" = "true" ]; then
    codex_verify || true
  fi
else
  printf '\\033[1;33m[WARN]\\033[0m clash-Autodl-codex 仓库不存在: %s\\n' "\${CODEX_AUTODL_REPO_ROOT}"
fi
EOF
  chmod 600 "$hook_file" 2>/dev/null || true

  touch "$HOME/.bashrc"
  sed -i '/# clash-autodl-codex begin/,/# clash-autodl-codex end/d' "$HOME/.bashrc"
  {
    echo "# clash-autodl-codex begin"
    echo "[ -f \"$hook_file\" ] && . \"$hook_file\""
    echo "# clash-autodl-codex end"
  } >> "$HOME/.bashrc"
  log_ok "已在 ~/.bashrc 中安装 clash-Autodl-codex 启动钩子"
}

print_daily_commands() {
  cat <<'TEXT'

代理命令:
  proxy_on
  proxy_off
  proxy_pick
  proxy_status

Codex 中转站命令:
  codex_use_domestic
  codex_use_overseas
  codex_relay_status
  codex_verify
TEXT
}

codex_switch_relay_mode() {
  local mode="$1"
  local config_file="${2:-}"

  if [ -n "$config_file" ]; then
    if [ -f "$config_file" ]; then
      load_project_config "$config_file"
    else
      load_project_config
    fi
  else
    load_project_config
  fi

  case "$mode" in
    auto)
      mode="$(detect_relay_mode)" || return 1
      ;;
    domestic | overseas)
      ;;
    *)
      log_error "中转模式无效: $mode"
      return 1
      ;;
  esac

  write_codex_config_for_mode "$mode"
}

codex_use_domestic() {
  codex_switch_relay_mode domestic
}

codex_use_overseas() {
  codex_switch_relay_mode overseas
  inject_codex_overseas_rule_into_mihomo_config || true
}

codex_relay_status() {
  load_project_config

  local mode base_url
  mode="$(detect_relay_mode)" || return 1
  base_url="$(relay_base_url_for_mode "$mode")" || return 1
  log_info "Codex 中转站: $mode $base_url"
}

codex_audit_host() {
  load_project_config

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

  proxy_status
  codex_relay_status || true
}

proxy_pick() {
  load_project_config
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

codex_smoke_test() {
  local codex_status
  local smoke_timeout="${CODEX_SMOKE_TIMEOUT:-180}"
  local tmp_log
  local tmp_output
  local prompt='请只回复: CODEX_RELAY_READY'

  require_command codex || return 1
  tmp_log="$(mktemp)"
  tmp_output="$(mktemp)"

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
    rm -f "$tmp_output" "$tmp_log"
    log_ok "Codex 可用"
    return 0
  fi

  if [ "$codex_status" = "124" ]; then
    log_error "Codex 冒烟测试在 ${smoke_timeout}s 后超时"
  elif [ "$codex_status" != "0" ]; then
    log_error "Codex 冒烟测试命令失败，退出码为 $codex_status"
  fi
  log_error "Codex 冒烟测试回复中没有包含预期内容，日志: /tmp/codex-bootstrap-smoke.log"
  cat "$tmp_log" >&2 || true
  rm -f "$tmp_output" "$tmp_log"
  return 1
}

codex_verify() {
  load_project_config
  codex_relay_status
  codex_smoke_test
}
