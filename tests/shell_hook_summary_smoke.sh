#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
fake_bin="$(mktemp -d)"
codex_called="$tmp_home/codex-called"

cleanup() {
  rm -rf "$tmp_home" "$tmp_state" "$fake_bin"
}
trap cleanup EXIT

mkdir -p "$tmp_state" "$fake_bin"

cat > "$tmp_state/config.sh" <<'EOF'
CLASH_URL='https://subscription.example.invalid/clash.yaml'
CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
CODEX_ACTIVE_RELAY='domestic'
CODEX_PROXY_URL='http://127.0.0.1:17900'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:16900'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
AUTO_PROXY_ON_SHELL_START='true'
AUTO_CODEX_CHECK_ON_SHELL_START='true'
EOF

cat > "$fake_bin/codex" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = "exec" ]; then
  touch '$codex_called'
  echo "CODEX_RELAY_READY"
  exit 0
fi
exit 0
SH
chmod +x "$fake_bin/codex"

cat > "$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '香港W01'
SH
chmod +x "$fake_bin/python3"

HOME="$tmp_home" \
PATH="$fake_bin:$PATH" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc "
  set -euo pipefail
  source '$repo_root/lib/codex_common.sh'
  install_shell_hook >/dev/null
"

output="$(
  HOME="$tmp_home" \
  PATH="$fake_bin:$PATH" \
  CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
  bash -lc '
    set -euo pipefail
    source "$HOME/.codex/clash-autodl-codex.sh"
    printf "http_proxy=%s\n" "${http_proxy:-}"
  ' 2>&1
)"

grep -q '\[OK\].*代理: 已开启' <<<"$output"
grep -q '\[OK\].*当前节点: 香港W01' <<<"$output"
grep -q '\[OK\].*Codex 中转站: domestic https://domestic.example.invalid/api' <<<"$output"
grep -q 'http_proxy=http://127.0.0.1:17900' <<<"$output"

[ ! -f "$codex_called" ]
! grep -q 'CODEX_RELAY_READY' <<<"$output"
! grep -q 'Codex 可用' <<<"$output"

! grep -q 'clash-Autodl-codex 命令已加载' <<<"$output"
! grep -q '代理地址' <<<"$output"
! grep -q 'Mihomo' <<<"$output"
