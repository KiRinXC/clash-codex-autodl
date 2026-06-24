#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_home" "$tmp_state"
}
trap cleanup EXIT

cat > "$tmp_state/config.sh" <<'EOF'
CLASH_URL='https://subscription.example.invalid/clash.yaml'
CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
CODEX_PROXY_URL='http://127.0.0.1:17900'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:16900'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
CODEX_ACTIVE_RELAY='domestic'
AUTO_CODEX_CHECK_ON_SHELL_START='false'
EOF

HOME="$tmp_home" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc '
  set -euo pipefail
  source "$1/lib/codex_common.sh"
  load_project_config "$2/config.sh"
  proxy-on
  [ "${http_proxy:-}" = "http://127.0.0.1:17900" ]
  [ ! -f "$HOME/.codex/config.toml" ]
  codex-use-out
  [ "${http_proxy:-}" = "http://127.0.0.1:17900" ]
  [ "$CODEX_ACTIVE_RELAY" = "overseas" ]
' _ "$repo_root" "$tmp_state"
