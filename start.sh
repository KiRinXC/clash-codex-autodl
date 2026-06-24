#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/codex_common.sh
. "$SCRIPT_DIR/lib/codex_common.sh"

usage() {
  cat <<'USAGE'
用法:
  bash start.sh
  bash start.sh --reconfigure
  bash start.sh --reconfigure-clash
  bash start.sh --reconfigure-codex
USAGE
}

prompt_required() {
  local label="$1"
  local current="${2:-}"
  local value

  while :; do
    if [ -n "$current" ]; then
      printf '%s [%s]: ' "$label" "$current" >&2
    else
      printf '%s: ' "$label" >&2
    fi
    IFS= read -r value
    if [ -z "$value" ] && [ -n "$current" ]; then
      value="$current"
    fi
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
    log_warn "$label 不能为空"
  done
}

prompt_secret() {
  local label="$1"
  local value

  while :; do
    if [ -t 0 ]; then
      printf '%s: ' "$label" >&2
      IFS= read -r -s value
      printf '\n' >&2
    else
      printf '%s: ' "$label" >&2
      IFS= read -r value
    fi
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
    log_warn "$label 不能为空"
  done
}

configure_clash() {
  local force="${1:-false}"

  load_project_config
  if [ "$force" = "true" ] || [ -z "${CLASH_URL:-}" ]; then
    CLASH_URL="$(prompt_required "Clash/Mihomo subscription URL" "${CLASH_URL:-}")"
  fi
  validate_http_url CLASH_URL "$CLASH_URL"
  save_project_config

  bash "$SCRIPT_DIR/setup_mihomo.sh" "$(project_config_file)"
  install_shell_hook
  print_daily_commands
}

configure_codex() {
  local force="${1:-false}"

  load_project_config
  if [ "$force" = "true" ] || [ -z "${CODEX_DOMESTIC_BASE_URL:-}" ]; then
    CODEX_DOMESTIC_BASE_URL="$(prompt_required "Domestic/direct Codex relay URL" "${CODEX_DOMESTIC_BASE_URL:-}")"
  fi
  if [ "$force" = "true" ] || [ -z "${CODEX_OVERSEAS_BASE_URL:-}" ]; then
    CODEX_OVERSEAS_BASE_URL="$(prompt_required "Overseas/proxy Codex relay URL" "${CODEX_OVERSEAS_BASE_URL:-}")"
  fi
  OPENAI_API_KEY="$(prompt_secret "OpenAI API key")"

  validate_codex_relay_urls
  save_project_config
  write_codex_auth
  codex-use-in
}

ensure_codex_with_proxy() {
  load_project_config
  proxy-on
  ensure_codex_cli
}

main() {
  show_source_hint=false
  case "${1:-}" in
    --help | -h)
      usage
      ;;
    --reconfigure)
      configure_clash true
      ensure_codex_with_proxy
      configure_codex true
      codex-verify
      show_source_hint=true
      ;;
    --reconfigure-clash)
      configure_clash true
      proxy-status
      show_source_hint=true
      ;;
    --reconfigure-codex)
      ensure_codex_with_proxy
      configure_codex true
      codex-verify
      show_source_hint=true
      ;;
    "")
      configure_clash false
      proxy-status || true
      ensure_codex_with_proxy
      configure_codex false
      codex-verify
      show_source_hint=true
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
if [ "${show_source_hint:-false}" = "true" ]; then
  log_info "要在当前终端立即使用命令，请运行: source ~/.codex/clash-codex-autodl.sh"
fi
