#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
controller_port=18081
controller_base="http://127.0.0.1:${controller_port}"
server_log="$tmp_dir/server.log"

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

python3 - "$controller_port" >"$server_log" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path == "/proxies/CodexProxy":
            body = json.dumps({
                "name": "CodexProxy",
                "type": "Selector",
                "now": "Node A",
                "all": ["DIRECT", "Node A"],
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
server_pid=$!
sleep 1

output="$(
  CODEX_AUTODL_CONFIG_DIR="$tmp_dir" \
  bash -lc "
    set -euo pipefail
    source '$repo_root/lib/codex_common.sh'
    CODEX_PROXY_URL='http://127.0.0.1:7890'
    CODEX_MIHOMO_CONTROLLER_URL='$controller_base'
    CODEX_PROXY_GROUP='CodexProxy'
    save_project_config
    export http_proxy='http://127.0.0.1:7890'
    proxy-status
  " 2>&1
)"

grep -q "\[INFO\].*代理: 已开启" <<<"$output"
grep -q "\[INFO\].*当前节点: Node A" <<<"$output"
