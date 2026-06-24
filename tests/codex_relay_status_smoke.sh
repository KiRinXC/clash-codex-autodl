#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

output="$(
  CODEX_AUTODL_CONFIG_DIR="$tmp_dir" \
  bash -lc "
    set -euo pipefail
    source '$repo_root/lib/codex_common.sh'
    CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
    CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
    CODEX_ACTIVE_RELAY='domestic'
    save_project_config
    codex_relay_status
  " 2>&1
)"

grep -q "\[INFO\].*Codex 中转站: domestic https://domestic.example.invalid/api" <<<"$output"
