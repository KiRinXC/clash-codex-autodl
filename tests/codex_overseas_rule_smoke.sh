#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_repo="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_repo"
}
trap cleanup EXIT

mkdir -p "$tmp_repo/conf" "$tmp_repo/bin"

cat > "$tmp_repo/conf/config.yaml" <<'EOF'
proxies:
  - name: Node A
rules: []
proxy-groups:
  - name: Existing
    type: select
    proxies: [Node A]
EOF

cat > "$tmp_repo/bin/yq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "eval" ] && [ "${2:-}" = "-i" ]; then
  expression="${3:-}"
  case "$expression" in
    *'if '*)
      printf 'fake yq: unsupported conditional expression\n' >&2
      exit 7
      ;;
  esac

  config_file="${@: -1}"
  {
    printf 'mixed-port: 7890\n'
    printf 'external-controller: 127.0.0.1:6006\n'
    printf 'overseas-host: %s\n' "${CODEX_OVERSEAS_HOST:-}"
    printf 'proxy-groups: CodexProxy\n'
  } > "$config_file"
  exit 0
fi

if [ "${1:-}" = "eval" ]; then
  printf '1\n'
  exit 0
fi

exit 0
SH
chmod +x "$tmp_repo/bin/yq"

output="$(
  CODEX_AUTODL_REPO_ROOT="$tmp_repo" \
  CODEX_AUTODL_CONFIG_DIR="$tmp_repo/state" \
  bash -lc "
    set -euo pipefail
    source '$repo_root/lib/codex_common.sh'
    CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
    CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
    save_project_config
    codex_use_overseas
  " 2>&1
)"

grep -q '\[OK\].*Codex 中转站已切换到 overseas' <<<"$output"
grep -q '\[OK\].*已更新 Mihomo 海外中转规则' <<<"$output"
grep -qx 'overseas-host: overseas.example.invalid' "$tmp_repo/conf/config.yaml"
