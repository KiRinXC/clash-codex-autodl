#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(
  CODEX_MIHOMO_CONTROLLER_URL="http://127.0.0.1:9" \
  CODEX_PROXY_GROUP="CodexProxy" \
  bash -lc "
    set -e
    source '$repo_root/lib/codex_common.sh'
    proxy-pick
    echo after-proxy-pick
  " 2>&1
)"

grep -q "Mihomo" <<<"$output"
grep -q "after-proxy-pick" <<<"$output"
