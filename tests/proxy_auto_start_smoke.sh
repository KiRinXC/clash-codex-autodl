#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_home" "$tmp_state"
}
trap cleanup EXIT

HOME="$tmp_home" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc '
  set -euo pipefail
  source "$1/lib/codex_common.sh"

  CODEX_PROXY_URL="http://127.0.0.1:17900"
  proxy_on >/dev/null
  [ "${http_proxy:-}" = "http://127.0.0.1:17900" ]
  grep -q "^AUTO_PROXY_ON_SHELL_START='\''true'\''" "$2/config.sh"

  proxy_off >/dev/null
  [ -z "${http_proxy:-}" ]
  grep -q "^AUTO_PROXY_ON_SHELL_START='\''false'\''" "$2/config.sh"
' _ "$repo_root" "$tmp_state"
