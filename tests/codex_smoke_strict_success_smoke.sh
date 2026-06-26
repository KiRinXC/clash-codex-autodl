#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_with_fake_codex() {
  local script_body="$1"
  local tmp_dir fake_bin output status

  tmp_dir="$(mktemp -d)"
  fake_bin="$tmp_dir/bin"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail

$script_body
EOF
  chmod +x "$fake_bin/codex"

  set +e
  output="$(
    PATH="$fake_bin:$PATH" \
    CODEX_SMOKE_TIMEOUT=1 \
    bash -lc "source '$repo_root/lib/codex_common.sh'; codex_smoke_test" 2>&1
  )"
  status="$?"
  set -e

  rm -rf "$tmp_dir"
  printf '%s\n' "$output"
  return "$status"
}

set +e
log_only_output="$(
  run_with_fake_codex '
out_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      out_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf "%s\n" "log mentions CODEX_RELAY_READY, but this is not the final answer" >&2
printf "%s\n" "NOT_READY" > "$out_file"
sleep 5
'
)"
log_only_status="$?"
set -e

if [ "$log_only_status" -eq 0 ]; then
  printf '%s\n' "$log_only_output"
  echo "expected log-only READY timeout case to fail"
  exit 1
fi

grep -q '\[FAIL\].*1s' <<<"$log_only_output"
grep -q '/tmp/codex-bootstrap-smoke.log' <<<"$log_only_output"
! grep -q '\[OK\].*Codex' <<<"$log_only_output"

set +e
nonzero_output="$(
  run_with_fake_codex '
out_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      out_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf "%s\n" "CODEX_RELAY_READY" > "$out_file"
exit 42
'
)"
nonzero_status="$?"
set -e

if [ "$nonzero_status" -eq 0 ]; then
  printf '%s\n' "$nonzero_output"
  echo "expected non-zero codex exit case to fail"
  exit 1
fi

grep -q '\[FAIL\].*42' <<<"$nonzero_output"
! grep -q '\[OK\].*Codex' <<<"$nonzero_output"
