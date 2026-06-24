#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
common="$repo_root/lib/codex_common.sh"

grep -q 'proxy_on()' "$common"
grep -q 'proxy_off()' "$common"
grep -q 'proxy_pick()' "$common"
grep -q 'proxy_status()' "$common"
grep -q 'codex_use_domestic()' "$common"
grep -q 'codex_use_overseas()' "$common"
grep -q 'codex_relay_status()' "$common"
grep -q 'codex_verify()' "$common"
grep -q 'shell_startup_status()' "$common"
grep -q 'clash-codex-autodl.sh' "$common"

grep -q 'bash start.sh' "$repo_root/README.md"
