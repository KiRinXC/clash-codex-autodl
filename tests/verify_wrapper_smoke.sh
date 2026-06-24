#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
fake_bin="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_home" "$tmp_state" "$fake_bin"
}
trap cleanup EXIT

cat > "$fake_bin/codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  echo "CODEX_RELAY_READY"
  exit 0
fi
exit 0
SH
chmod +x "$fake_bin/codex"

cat > "$tmp_state/config.sh" <<'EOF'
CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
CODEX_ACTIVE_RELAY='domestic'
CODEX_PROXY_URL='http://127.0.0.1:7890'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:6006'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
AUTO_CODEX_CHECK_ON_SHELL_START='false'
EOF

output="$(
  HOME="$tmp_home" \
  PATH="$fake_bin:$PATH" \
  CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
  bash "$repo_root/verify_codex.sh" current 2>&1
)"

grep -q "\[INFO\].*Codex 中转站: domestic https://domestic.example.invalid/api" <<<"$output"
grep -q "\[OK\].*Codex 可用" <<<"$output"
