#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
fake_bin="$(mktemp -d)"

cleanup() {
  if [ -f "$repo_root/mihomo.pid" ]; then
    pid="$(cat "$repo_root/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$tmp_home" "$tmp_state" "$fake_bin" "$repo_root/bin" "$repo_root/conf" "$repo_root/logs" "$repo_root/mihomo.pid"
}
trap cleanup EXIT

mkdir -p "$repo_root/bin" "$fake_bin"

cat > "$repo_root/bin/yq" <<'SH'
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
    printf 'mixed-port: %s\n' "${CODEX_PROXY_PORT:-}"
    printf 'external-controller: %s\n' "${CODEX_MIHOMO_CONTROLLER_BIND:-}"
    printf 'overseas-host: %s\n' "${CODEX_OVERSEAS_HOST:-}"
  } > "$config_file"
  exit 0
fi

if [ "${1:-}" = "eval" ]; then
  query="${2:-}"
  case "$query" in
    '.proxies | length')
      exit 0
      ;;
    *CodexProxy*length*)
      printf '1\n'
      exit 0
      ;;
  esac
fi

exit 0
SH
chmod +x "$repo_root/bin/yq"

cat > "$repo_root/bin/mihomo-linux-amd64" <<'SH'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do
  sleep 1
done
SH
chmod +x "$repo_root/bin/mihomo-linux-amd64"

cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "$output_file" ]; then
  if [ "${output_file##*/}" = "geoip.metadb" ]; then
    dd if=/dev/zero of="$output_file" bs=1048576 count=6 >/dev/null 2>&1
    exit 0
  fi

  cat > "$output_file" <<'YAML'
proxies:
  - name: Node A
    type: http
    server: example.invalid
    port: 443
rules: []
YAML
fi
SH
chmod +x "$fake_bin/curl"

cat > "$fake_bin/ss" <<'SH'
#!/usr/bin/env bash
printf 'LISTEN 0 128 127.0.0.1:7890 0.0.0.0:*\n'
SH
chmod +x "$fake_bin/ss"

cat > "$fake_bin/codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  echo "CODEX_RELAY_READY"
  exit 0
fi
exit 0
SH
chmod +x "$fake_bin/codex"

output="$(
  HOME="$tmp_home" \
  PATH="$fake_bin:$PATH" \
  CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
  bash "$repo_root/start.sh" <<'EOF'
https://subscription.example.invalid/clash.yaml
https://domestic.example.invalid/api
https://overseas.example.invalid/api
test-api-key
EOF
)"

grep -q 'proxy_status' <<<"$output"
grep -q 'codex_use_domestic' <<<"$output"
grep -q "CLASH_URL='https://subscription.example.invalid/clash.yaml'" "$tmp_state/config.sh"
grep -q "CODEX_ACTIVE_RELAY='domestic'" "$tmp_state/config.sh"
grep -q '"OPENAI_API_KEY": "test-api-key"' "$tmp_home/.codex/auth.json"
grep -q 'base_url = "https://domestic.example.invalid/api"' "$tmp_home/.codex/config.toml"
grep -q '\.local/bin:\$PATH' "$tmp_home/.codex/clash-autodl-codex.sh"
grep -q 'clash-autodl-codex.sh' "$tmp_home/.bashrc"
