#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="$repo_root/bootstrap_codex.sh"
common="$repo_root/lib/codex_common.sh"

grep -q 'proxy_on()' "$common"
grep -q 'proxy_off()' "$common"
grep -q 'proxy_pick()' "$common"
grep -q 'proxy_status()' "$common"
grep -q 'codex_use_domestic()' "$common"
grep -q 'codex_use_overseas()' "$common"
grep -q 'codex_relay_status()' "$common"
grep -q 'codex_verify()' "$common"
grep -q 'clash-Autodl-codex 命令已加载' "$common"
grep -q 'clash-autodl-codex.sh' "$common"

grep -qx "export CODEX_DOMESTIC_BASE_URL=''" "$repo_root/.env.example"
grep -qx "export CODEX_OVERSEAS_BASE_URL=''" "$repo_root/.env.example"

grep -q 'bash start.sh' "$repo_root/README.md"
