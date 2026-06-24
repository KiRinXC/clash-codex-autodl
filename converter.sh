#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: bash converter.sh INPUT_FILE OUTPUT_FILE"
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

input_file="${1:-}"
output_file="${2:-}"

if [ -z "$input_file" ] || [ -z "$output_file" ]; then
  usage
  exit 1
fi

if [ ! -s "$input_file" ]; then
  echo "[FAIL] 输入订阅文件不存在或为空: $input_file" >&2
  exit 1
fi

tmp_file="$(mktemp)"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

decode_status=0
if python3 - "$input_file" "$tmp_file" <<'PY'
import base64
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_bytes().strip()
target = pathlib.Path(sys.argv[2])

def looks_like_yaml(data: bytes) -> bool:
    text = data.decode("utf-8", errors="ignore")
    return any(marker in text for marker in ("proxies:", "proxy-groups:", "rules:"))

if looks_like_yaml(source):
    target.write_bytes(source)
    sys.exit(0)

compact = b"".join(source.split())
padding = b"=" * (-len(compact) % 4)

for candidate in (compact, compact.replace(b"-", b"+").replace(b"_", b"/")):
    try:
        decoded = base64.b64decode(candidate + padding, validate=False)
    except Exception:
        continue
    if looks_like_yaml(decoded):
        target.write_bytes(decoded)
        sys.exit(0)

sys.exit(2)
PY
then
  decode_status=0
else
  decode_status=$?
fi

case "$decode_status" in
  0)
    mv "$tmp_file" "$output_file"
    echo "[OK] 已将订阅转换为 Clash YAML: $output_file"
    ;;
  2)
    echo "[FAIL] 订阅不是 Clash YAML，也不是 base64 包装的 Clash YAML。" >&2
    echo "[FAIL] 请使用返回 Clash YAML 的订阅 URL，例如带有 clash=3 的地址。" >&2
    exit 1
    ;;
  *)
    echo "[FAIL] 检查订阅格式失败。" >&2
    exit 1
    ;;
esac
