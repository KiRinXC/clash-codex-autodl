#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(
  CODEX_MIHOMO_CONTROLLER_URL="http://127.0.0.1:9" \
  CODEX_PROXY_GROUP="CodexProxy" \
  bash -lc "
    set -e
    source '$repo_root/lib/codex_common.sh'
    type proxy-pick
    proxy-pick
    echo after-proxy-pick
  " 2>&1
)"

grep -q "proxy-pick is a function" <<<"$output"
grep -q "无法连接 Mihomo 控制器" <<<"$output"
grep -q "after-proxy-pick" <<<"$output"

function_names="$(
  bash -lc "
    source '$repo_root/lib/codex_common.sh'
    type proxy-on proxy-off proxy-status codex-use-in codex-use-out codex-status codex-verify
  " 2>&1
)"

grep -q "proxy-on is a function" <<<"$function_names"
grep -q "proxy-off is a function" <<<"$function_names"
grep -q "proxy-status is a function" <<<"$function_names"
grep -q "codex-use-in is a function" <<<"$function_names"
grep -q "codex-use-out is a function" <<<"$function_names"
grep -q "codex-status is a function" <<<"$function_names"
grep -q "codex-verify is a function" <<<"$function_names"

old_names="$(
  bash -lc "
    source '$repo_root/lib/codex_common.sh'
    type proxy_on proxy_off proxy_pick proxy_status codex_use_domestic codex_use_overseas codex_relay_status codex_verify
  " 2>&1 || true
)"

grep -q "proxy_on: not found" <<<"$old_names"
grep -q "proxy_off: not found" <<<"$old_names"
grep -q "proxy_pick: not found" <<<"$old_names"
grep -q "proxy_status: not found" <<<"$old_names"
grep -q "codex_use_domestic: not found" <<<"$old_names"
grep -q "codex_use_overseas: not found" <<<"$old_names"
grep -q "codex_relay_status: not found" <<<"$old_names"
grep -q "codex_verify: not found" <<<"$old_names"
