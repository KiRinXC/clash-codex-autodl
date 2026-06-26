#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
tmp_repo="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_home" "$tmp_state" "$tmp_repo"
}
trap cleanup EXIT

mkdir -p "$tmp_repo/conf" "$tmp_repo/bin"

cat > "$tmp_repo/conf/config.yaml" <<'YAML'
proxies:
  - name: Node A
rules: []
YAML

cat > "$tmp_repo/bin/yq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "eval" ] && [ "${2:-}" = "-i" ]; then
  config_file="${@: -1}"
  {
    printf 'overseas-host: %s\n' "${CODEX_OVERSEAS_HOST:-}"
  } > "$config_file"
  exit 0
fi

exit 0
SH
chmod +x "$tmp_repo/bin/yq"

cat > "$tmp_state/config.sh" <<'EOF'
CLASH_URL='https://subscription.example.invalid/clash.yaml'
CODEX_DOMESTIC_BASE_URL='https://old-domestic.example.invalid/api'
CODEX_OVERSEAS_BASE_URL='https://old-overseas.example.invalid/api'
CODEX_PROXY_URL='http://127.0.0.1:17900'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:16900'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
CODEX_ACTIVE_RELAY='domestic'
AUTO_PROXY_ON_SHELL_START='true'
EOF

HOME="$tmp_home" \
CLASH_CODEX_AUTODL_REPO_ROOT="$tmp_repo" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc "
  set -euo pipefail
  source '$repo_root/lib/codex_common.sh'
  type codex-ex-in codex-ex-out

  codex-ex-in 'https://new-domestic.example.invalid/v1'
  grep -q \"CODEX_DOMESTIC_BASE_URL='https://new-domestic.example.invalid/v1'\" '$tmp_state/config.sh'
  grep -q 'base_url = \"https://new-domestic.example.invalid/v1\"' \"\$HOME/.codex/config.toml\"

  codex-ex-out 'https://new-overseas.example.invalid/v1'
  grep -q \"CODEX_OVERSEAS_BASE_URL='https://new-overseas.example.invalid/v1'\" '$tmp_state/config.sh'
  grep -q 'base_url = \"https://new-domestic.example.invalid/v1\"' \"\$HOME/.codex/config.toml\"
  grep -qx 'overseas-host: new-overseas.example.invalid' '$tmp_repo/conf/config.yaml'

  codex-use-out
  printf '%s\n' 'https://prompt-overseas.example.invalid/api' | codex-ex-out
  grep -q \"CODEX_OVERSEAS_BASE_URL='https://prompt-overseas.example.invalid/api'\" '$tmp_state/config.sh'
  grep -q 'base_url = \"https://prompt-overseas.example.invalid/api\"' \"\$HOME/.codex/config.toml\"
"
