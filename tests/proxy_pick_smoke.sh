#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
fake_bin="$tmp_dir/fake-bin"
controller_port=18080
controller_base="http://127.0.0.1:${controller_port}"
selected_file="$tmp_dir/selected"
server_log="$tmp_dir/server.log"
python_cmd=""

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$fake_bin"

for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    candidate_path="$(command -v "$candidate")"
    if "$candidate_path" - <<'PY' >/dev/null 2>&1
import sys
PY
    then
      python_cmd="$candidate_path"
      break
    fi
  fi
done

if [ -z "$python_cmd" ]; then
  echo "missing working python"
  exit 1
fi

cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
exec "$python_cmd" "\$@"
SH
chmod +x "$fake_bin/python3"

"$python_cmd" - "$controller_port" "$selected_file" >"$server_log" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])
selected_file = sys.argv[2]
state = {"now": "DIRECT", "all": ["DIRECT", "Node A", "Node B"]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _write_json(self, payload, code=200):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/proxies/CodexProxy":
            self._write_json({
                "name": "CodexProxy",
                "type": "Selector",
                "now": state["now"],
                "all": state["all"],
            })
            return
        self.send_error(404)

    def do_PUT(self):
        if self.path != "/proxies/CodexProxy":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length) or b"{}")
        state["now"] = payload["name"]
        with open(selected_file, "w", encoding="utf-8") as fh:
            fh.write(state["now"])
        self._write_json({"ok": True, "now": state["now"]})


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
server_pid=$!

sleep 1

output="$(
  CODEX_MIHOMO_CONTROLLER_URL="$controller_base" \
  CODEX_PROXY_GROUP="CodexProxy" \
  PATH="$fake_bin:$PATH" \
  bash -c "source '$repo_root/lib/codex_common.sh'; printf '2\n' | proxy-pick" 2>&1
)"

kill "$server_pid" >/dev/null 2>&1 || true
wait "$server_pid" >/dev/null 2>&1 || true
server_pid=""

grep -q "DIRECT" <<<"$output"
grep -q "Node A" <<<"$output"
grep -q "Node B" <<<"$output"
grep -qx "Node A" "$selected_file"
