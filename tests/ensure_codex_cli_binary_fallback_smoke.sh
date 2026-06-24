#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
tmp_home="$tmp_dir/home"
fake_bin="$tmp_dir/fake-bin"
payload_dir="$tmp_dir/payload"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_home" "$fake_bin" "$payload_dir"

cat > "$payload_dir/codex-x86_64-unknown-linux-musl" <<'SH'
#!/usr/bin/env bash
printf 'codex-cli fake\n'
SH
chmod +x "$payload_dir/codex-x86_64-unknown-linux-musl"
tar -C "$payload_dir" -czf "$tmp_dir/codex.tar.gz" codex-x86_64-unknown-linux-musl

cat > "$fake_bin/curl" <<SH
#!/usr/bin/env bash
set -euo pipefail

output_file=""
url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o)
      output_file="\$2"
      shift 2
      ;;
    http://*|https://*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

case "\$url" in
  *chatgpt.com/codex/install.sh*)
    exit 35
    ;;
  *openai/codex/releases/latest/download/codex-x86_64-unknown-linux-musl.tar.gz*)
    cp '$tmp_dir/codex.tar.gz' "\$output_file"
    exit 0
    ;;
esac

exit 22
SH
chmod +x "$fake_bin/curl"

cat > "$fake_bin/npm" <<'SH'
#!/usr/bin/env bash
exit 127
SH
chmod +x "$fake_bin/npm"

PATH="$fake_bin:/usr/bin:/bin" HOME="$tmp_home" bash -lc "
  set -euo pipefail
  source '$repo_root/lib/codex_common.sh'
  ensure_codex_cli
  command -v codex
  codex
" > "$tmp_dir/output"

grep -q "$tmp_home/.local/bin/codex" "$tmp_dir/output"
grep -q 'codex-cli fake' "$tmp_dir/output"
