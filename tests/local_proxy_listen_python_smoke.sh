#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/fake-bin"
port_file="$tmp_dir/port"

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$fake_bin"

cat > "$fake_bin/ss" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$fake_bin/ss"

cat > "$fake_bin/lsof" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$fake_bin/lsof"

python3 - "$port_file" <<'PY' &
import socket
import sys

sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 0))
sock.listen(8)

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(str(sock.getsockname()[1]))

while True:
    conn, _ = sock.accept()
    conn.close()
PY
server_pid="$!"

for _ in $(seq 1 50); do
  if [ -s "$port_file" ]; then
    break
  fi
  sleep 0.1
done

port="$(cat "$port_file")"
PATH="$fake_bin:$PATH" bash -lc "
  set -euo pipefail
  source '$repo_root/lib/codex_common.sh'
  local_proxy_is_listening 'http://127.0.0.1:$port'
"
