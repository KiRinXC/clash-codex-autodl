# Interactive AutoDL Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `clash-Autodl-codex` into a first-run terminal bootstrapper for fresh AutoDL machines, with local persistence, decoupled proxy and Codex relay controls, and automatic startup checks.

**Architecture:** Keep the shell-based toolchain, but split responsibilities cleanly. `start.sh` becomes the interactive orchestrator, `setup_mihomo.sh` becomes Clash/Mihomo install and subscription wiring, `bootstrap_codex.sh` becomes Codex CLI/auth/bootstrap support, and `lib/codex_common.sh` owns all shared state, persistence, status, and command helpers. User-entered values are stored locally under `~/.config/clash-autodl-codex/` and `~/.codex/`, not in repo-managed `.env` files.

**Tech Stack:** Bash, Python 3, curl, Mihomo, Codex CLI, shell smoke tests.

---

### Task 1: Add local state helpers and English status output

**Files:**
- Modify: `lib/codex_common.sh`
- Create: `tests/config_persistence_smoke.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"

HOME="$tmp_home" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc '
  source "$1/lib/codex_common.sh"
  CLASH_URL="https://example.invalid/sub.yaml"
  CODEX_DOMESTIC_BASE_URL="https://domestic.example.invalid/api"
  CODEX_OVERSEAS_BASE_URL="https://overseas.example.invalid/api"
  CODEX_PROXY_URL="http://127.0.0.1:17900"
  CODEX_MIHOMO_CONTROLLER_URL="http://127.0.0.1:16900"
  CODEX_PROXY_GROUP="CodexProxy"
  CODEX_MODEL="gpt-5.4"
  CODEX_REVIEW_MODEL="gpt-5.4"
  AUTO_CODEX_CHECK_ON_SHELL_START="true"
  save_project_config
  grep -qx "CLASH_URL='https://example.invalid/sub.yaml'" "$2/config.sh"
  grep -qx "CODEX_ACTIVE_RELAY=''" "$2/config.sh"
  ! grep -q "OPENAI_API_KEY" "$2/config.sh"
  load_project_config "$2/config.sh"
  [ "$CODEX_PROXY_URL" = "http://127.0.0.1:17900" ]
' _ "$repo_root" "$tmp_state"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/config_persistence_smoke.sh`
Expected: fail because `save_project_config` and `load_project_config` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Add:

```bash
PROJECT_CONFIG_DIR="${CODEX_AUTODL_CONFIG_DIR:-$HOME/.config/clash-autodl-codex}"
PROJECT_CONFIG_FILE="$PROJECT_CONFIG_DIR/config.sh"

load_project_config() { ... }
save_project_config() { ... }
project_status_line() { ... }
proxy_status() { ... }
codex_relay_status() { ... }
```

Use `printf '%q'` when writing shell values and keep `OPENAI_API_KEY` out of the local config file.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/config_persistence_smoke.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/codex_common.sh tests/config_persistence_smoke.sh
git commit -m "Add local config persistence helpers"
```

### Task 2: Split proxy commands from Codex relay commands

**Files:**
- Modify: `lib/codex_common.sh`
- Modify: `bootstrap_codex.sh`
- Modify: `uninstall_codex_bootstrap.sh`
- Create: `tests/command_boundary_smoke.sh`
- Modify: `tests/proxy_commands_smoke.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"

cat > "$tmp_state/config.sh" <<'EOF'
CODEX_DOMESTIC_BASE_URL='https://domestic.example.invalid/api'
CODEX_OVERSEAS_BASE_URL='https://overseas.example.invalid/api'
CODEX_PROXY_URL='http://127.0.0.1:17900'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:16900'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
CODEX_ACTIVE_RELAY='domestic'
AUTO_CODEX_CHECK_ON_SHELL_START='false'
EOF

HOME="$tmp_home" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash -lc '
  source "$1/lib/codex_common.sh"
  load_project_config "$2/config.sh"
  proxy_on
  ! grep -q "model = \"gpt-5.4\"" "$HOME/.codex/config.toml"
  codex_use_overseas
  [ "${http_proxy:-}" = "http://127.0.0.1:17900" ]
' _ "$repo_root" "$tmp_state"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/command_boundary_smoke.sh`
Expected: fail because `codex_use_domestic`, `codex_use_overseas`, and `load_project_config` are not separated yet.

- [ ] **Step 3: Write minimal implementation**

Refactor `lib/codex_common.sh` so:

```bash
proxy_on() { enable_proxy_env; }
proxy_off() { disable_proxy_env; }
proxy_pick() { ... }
proxy_status() { ... }
codex_use_domestic() { ... }
codex_use_overseas() { ... }
codex_relay_status() { ... }
codex_verify() { ... }
```

`bootstrap_codex.sh` should become a thin compatibility/bootstrap helper that installs Codex CLI, writes auth/config, and installs the shell hook, but it must not silently switch proxy state or relay state together.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/command_boundary_smoke.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/codex_common.sh bootstrap_codex.sh uninstall_codex_bootstrap.sh tests/command_boundary_smoke.sh tests/proxy_commands_smoke.sh
git commit -m "Decouple proxy and Codex relay commands"
```

### Task 3: Make Mihomo setup subscription-only first, then optional Codex rule injection

**Files:**
- Modify: `setup_mihomo.sh`
- Modify: `lib/codex_common.sh`
- Modify: `tests/setup_mihomo_env_smoke.sh`
- Create: `tests/setup_mihomo_codex_rule_smoke.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
work_dir="$tmp_dir/work"
fake_bin="$tmp_dir/fake-bin"

mkdir -p "$work_dir/bin" "$fake_bin"
cp "$repo_root/setup_mihomo.sh" "$work_dir/setup_mihomo.sh"
cp "$repo_root/lib/codex_common.sh" "$work_dir/lib/codex_common.sh"

cat > "$work_dir/config.sh" <<'EOF'
CLASH_URL='https://subscription.example.invalid/clash.yaml'
CODEX_PROXY_URL='http://127.0.0.1:17890'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:16006'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_DOMESTIC_BASE_URL=''
CODEX_OVERSEAS_BASE_URL=''
EOF
```

The test should assert:

1. `setup_mihomo.sh` can run with only `CLASH_URL` set.
2. `setup_mihomo.sh` writes `mixed-port` and `external-controller` from the local config.
3. Codex relay host injection happens only when `CODEX_OVERSEAS_BASE_URL` is present.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/setup_mihomo_env_smoke.sh`
Expected: fail because Mihomo setup still depends on relay URLs too early.

- [ ] **Step 3: Write minimal implementation**

Update `setup_mihomo.sh` to:

```bash
load_project_config
require only CLASH_URL for the install path
inject CodexProxy group always
inject overseas DOMAIN rule only when CODEX_OVERSEAS_BASE_URL is set
```

Keep the custom proxy/controller port support already verified by the existing smoke test.

- [ ] **Step 4: Run test to verify it passes**

Run:
`bash tests/setup_mihomo_env_smoke.sh && bash tests/setup_mihomo_codex_rule_smoke.sh`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add setup_mihomo.sh lib/codex_common.sh tests/setup_mihomo_env_smoke.sh tests/setup_mihomo_codex_rule_smoke.sh
git commit -m "Let Mihomo setup work before Codex relay input"
```

### Task 4: Rewrite `start.sh` as the interactive first-run and reconfigure entry point

**Files:**
- Modify: `start.sh`
- Modify: `lib/codex_common.sh`
- Create: `tests/start_interactive_smoke.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_state="$(mktemp -d)"
fake_bin="$(mktemp -d)"

cat > "$fake_bin/codex" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  echo "CODEX_RELAY_READY"
  exit 0
fi
if [ "${1:-}" = "login" ]; then
  cat >/dev/null
  exit 0
fi
exit 0
SH
chmod +x "$fake_bin/codex"

HOME="$tmp_home" \
PATH="$fake_bin:$PATH" \
CODEX_AUTODL_CONFIG_DIR="$tmp_state" \
bash "$repo_root/start.sh" <<'EOF'
https://subscription.example.invalid/clash.yaml
https://domestic.example.invalid/api
https://overseas.example.invalid/api
test-api-key
EOF

grep -q "CODEX_ACTIVE_RELAY='overseas'" "$tmp_state/config.sh"
grep -q '"OPENAI_API_KEY"' "$tmp_home/.codex/auth.json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/start_interactive_smoke.sh`
Expected: fail because `start.sh` still expects `.env` and does not prompt interactively.

- [ ] **Step 3: Write minimal implementation**

Implement:

```bash
bash start.sh
bash start.sh --reconfigure
bash start.sh --reconfigure-clash
bash start.sh --reconfigure-codex
bash start.sh --import-env .env
```

Interactive flow:

1. Ask for Clash subscription URL.
2. Install Mihomo and install the shell hook.
3. Show proxy commands and current node.
4. Ensure Codex CLI exists or install it through proxy.
5. Ask for domestic relay URL, overseas relay URL, and API key.
6. Persist the local config.
7. Run validation and a Codex smoke test.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/start_interactive_smoke.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add start.sh lib/codex_common.sh tests/start_interactive_smoke.sh
git commit -m "Make start.sh interactive"
```

### Task 5: Update startup hook, verification, README, and CI for the new model

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `.env.example`
- Modify: `verify_codex.sh`
- Modify: `tests/proxy_commands_smoke.sh`
- Modify: `tests/proxy_pick_smoke.sh`
- Modify: `tests/setup_mihomo_env_smoke.sh`

- [ ] **Step 1: Write the failing test**

Add or adjust smoke checks so CI validates:

```bash
bash tests/proxy_status_smoke.sh
bash tests/codex_relay_status_smoke.sh
```

These should expect English status tags like `[INFO]` and `[OK]`, a visible current node, and no reliance on `.env` for the normal path.

- [ ] **Step 2: Run test to verify it fails**

Run the updated smoke tests and CI-equivalent shell checks.

- [ ] **Step 3: Write minimal implementation**

Update the shell hook to:

```bash
source ~/.config/clash-autodl-codex/config.sh
show proxy status
show codex relay status
optionally run codex_verify on shell start
```

Update README so the top-level flow is:

```bash
git clone https://github.com/KiRinXC/clash-Autodl-codex.git
cd clash-Autodl-codex
bash start.sh
```

Keep `.env` only as a compatibility note, not the main onboarding path.

- [ ] **Step 4: Run test to verify it passes**

Run the full shell verification suite.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml README.md .env.example verify_codex.sh tests/proxy_commands_smoke.sh tests/proxy_pick_smoke.sh tests/setup_mihomo_env_smoke.sh
git commit -m "Update docs and CI for interactive bootstrap flow"
```
