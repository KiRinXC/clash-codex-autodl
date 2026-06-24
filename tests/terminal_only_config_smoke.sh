#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

help_output="$(bash "$repo_root/start.sh" --help)"

! grep -q -- '--import-env' <<<"$help_output"
! grep -q 'ENV_FILE' <<<"$help_output"
! grep -q -- '--import-env' "$repo_root/start.sh"
! grep -q 'import_env_file' "$repo_root/start.sh"
! grep -q 'load_env_file' "$repo_root/lib/codex_common.sh"

[ ! -e "$repo_root/.env.example" ]

! grep -q '\.env' "$repo_root/README.md"
! grep -q '安全注意' "$repo_root/README.md"
! grep -q '不要提交或公开' "$repo_root/README.md"
