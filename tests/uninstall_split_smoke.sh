#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
work_dir="$tmp_dir/work"
tmp_home="$tmp_dir/home"
tmp_state="$tmp_home/.config/clash-codex-autodl"

cleanup() {
  if [ -n "${proxy_pid:-}" ] && kill -0 "$proxy_pid" >/dev/null 2>&1; then
    kill "$proxy_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/lib" "$work_dir/bin" "$work_dir/conf" "$work_dir/logs" "$tmp_home/.codex" "$tmp_home/.local/bin" "$tmp_state"
cp "$repo_root/uninstall_codex_bootstrap.sh" "$work_dir/uninstall_codex_bootstrap.sh"
cp "$repo_root/lib/codex_common.sh" "$work_dir/lib/codex_common.sh"

touch "$work_dir/bin/mihomo-linux-amd64" "$work_dir/bin/yq"
touch "$work_dir/conf/config.yaml" "$work_dir/conf/geoip.metadb"
touch "$work_dir/logs/mihomo.log"
sleep 1000 &
proxy_pid="$!"
printf '%s\n' "$proxy_pid" > "$work_dir/mihomo.pid"

touch "$tmp_home/.codex/config.toml" "$tmp_home/.codex/auth.json"
touch "$tmp_home/.codex/clash-codex-autodl.sh" "$tmp_home/.codex/clash-autodl-codex.sh"
touch "$tmp_home/.local/bin/codex"
cat > "$tmp_home/.bashrc" <<'EOF'
# clash-autodl-codex begin
old hook
# clash-autodl-codex end
# clash-codex-autodl begin
new hook
# clash-codex-autodl end
EOF
cat > "$tmp_state/config.sh" <<'EOF'
AUTO_PROXY_ON_SHELL_START='true'
EOF
mkdir -p "$tmp_home/.config/clash-autodl-codex"
touch "$tmp_home/.config/clash-autodl-codex/config.sh"

HOME="$tmp_home" \
CLASH_CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash "$work_dir/uninstall_codex_bootstrap.sh" --proxy

! kill -0 "$proxy_pid" >/dev/null 2>&1
proxy_pid=""
[ ! -e "$work_dir/mihomo.pid" ]
[ ! -d "$work_dir/bin" ]
[ ! -d "$work_dir/conf" ]
[ ! -d "$work_dir/logs" ]
[ -f "$tmp_home/.codex/config.toml" ]
[ -f "$tmp_home/.codex/auth.json" ]
grep -q "AUTO_PROXY_ON_SHELL_START='false'" "$tmp_state/config.sh"

mkdir -p "$work_dir/bin" "$work_dir/conf" "$work_dir/logs"
touch "$work_dir/conf/config.yaml"

HOME="$tmp_home" \
CLASH_CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash "$work_dir/uninstall_codex_bootstrap.sh" --codex

[ ! -e "$tmp_home/.codex/config.toml" ]
[ ! -e "$tmp_home/.codex/auth.json" ]
[ ! -e "$tmp_home/.local/bin/codex" ]
[ -d "$work_dir/conf" ]

HOME="$tmp_home" \
CLASH_CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash "$work_dir/uninstall_codex_bootstrap.sh" --all

[ ! -e "$tmp_home/.codex/clash-codex-autodl.sh" ]
[ ! -e "$tmp_home/.codex/clash-autodl-codex.sh" ]
! grep -q 'clash-codex-autodl begin' "$tmp_home/.bashrc"
! grep -q 'clash-autodl-codex begin' "$tmp_home/.bashrc"
[ ! -d "$tmp_state" ]
[ ! -d "$tmp_home/.config/clash-autodl-codex" ]
