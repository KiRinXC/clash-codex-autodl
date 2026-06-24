# Interactive AutoDL Bootstrap Design

## Summary

`clash-Autodl-codex` should become a fast first-run setup tool for newly rented AutoDL or similar Linux machines. A new machine usually has neither Clash/Mihomo nor Codex CLI installed, so the main path should be:

1. Ask for a Clash/Mihomo subscription URL in the terminal.
2. Install and start Mihomo.
3. Install shell commands for proxy control and node switching.
4. Use the working proxy to install Codex CLI if it is missing.
5. Ask for Codex relay URLs and API key in the terminal.
6. Persist the local configuration.
7. Verify Clash, Codex CLI, relay selection, and Codex response.
8. On every new terminal, show status and run a lightweight Codex availability check.

The project should no longer require users to copy or edit `.env` for the normal workflow.

## Goals

- Make a new AutoDL machine usable with Clash/Mihomo and Codex through one interactive command.
- Persist user input locally so users only type subscription URL, relay URLs, and API key during setup or reconfiguration.
- Keep proxy control separate from Codex relay URL switching.
- Show users how to enable/disable proxy, switch nodes, and see the current node immediately after Clash is installed.
- Automatically install Codex CLI after proxy setup if `codex` is not already available.
- Provide clear startup status for each new terminal: proxy state, current node, current Codex relay, and Codex availability.
- Avoid committing or printing sensitive values such as API keys and subscription URLs.

## Non-Goals

- Do not manage system-wide services with root-only systemd units.
- Do not require users to edit shell startup files manually.
- Do not make proxy state imply Codex relay state.
- Do not make Codex relay state imply proxy state.
- Do not require `.env` for the normal install path.

## User-Facing Flow

### First Run

The main entry remains:

```bash
bash start.sh
```

The script should ask for:

```text
Clash/Mihomo subscription URL:
```

After this input, it installs or reuses Mihomo, downloads the subscription, injects the `CodexProxy` selector, starts Mihomo, and installs the shell hook.

Once Mihomo is running, the script prints the daily proxy commands:

```bash
proxy_on
proxy_off
proxy_pick
proxy_status
```

Then it checks `codex`. If `codex` is missing, it turns proxy environment variables on for the installer process and downloads Codex CLI.

After Codex CLI is available, the script asks for:

```text
Domestic/direct Codex relay URL:
Overseas/proxy Codex relay URL:
OpenAI API key:
```

The API key input should not echo when the terminal supports hidden input.

Then the script writes local config, switches Codex to a default relay, verifies both relay URLs when possible, runs the Codex smoke test, and prints a final status summary.

### Daily Terminal Startup

The shell hook should load commands and print a compact status block:

```text
[INFO] clash-Autodl-codex 命令已加载
[INFO] 代理: 已开启/未开启
[INFO] Mihomo: 运行中/未运行
[INFO] 当前节点: <node name>
[INFO] Codex 中转站: domestic/overseas <url>
[OK] Codex 可用
```

If the smoke test is too slow or fails because of temporary network issues, the message should be clear and non-destructive. Users should still have commands available.

### Reconfiguration

Users should not edit files for common changes. Provide command entry points:

```bash
bash start.sh --reconfigure
bash start.sh --reconfigure-clash
bash start.sh --reconfigure-codex
```

`--reconfigure-clash` asks only for subscription URL and restarts Mihomo.

`--reconfigure-codex` asks only for relay URLs and API key.

## Persistent Local State

Store project-managed state under:

```text
~/.config/clash-autodl-codex/config.sh
~/.codex/auth.json
~/.codex/config.toml
~/.codex/clash-autodl-codex.sh
```

`config.sh` is a local shell config owned by this project. It should be mode `600` and contain non-repo secrets and settings:

```bash
CLASH_URL='...'
CODEX_DOMESTIC_BASE_URL='...'
CODEX_OVERSEAS_BASE_URL='...'
CODEX_ACTIVE_RELAY='domestic'
CODEX_PROXY_URL='http://127.0.0.1:7890'
CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:6006'
CODEX_PROXY_GROUP='CodexProxy'
CODEX_MODEL='gpt-5.4'
CODEX_REVIEW_MODEL='gpt-5.4'
AUTO_CODEX_CHECK_ON_SHELL_START='true'
```

`OPENAI_API_KEY` should be written to `~/.codex/auth.json`, not kept in the repo.

`.env.example` can stay as a reference for advanced or non-interactive use, but README should make the interactive path primary.

## Command Boundaries

Proxy commands manage only proxy state:

- `proxy_on`: exports `http_proxy`, `https_proxy`, `HTTP_PROXY`, `HTTPS_PROXY`, `no_proxy`, and `NO_PROXY` for the current shell.
- `proxy_off`: unsets those variables for the current shell.
- `proxy_pick`: talks to Mihomo controller and switches `CodexProxy` node.
- `proxy_status`: prints whether Mihomo is running, whether the current shell has proxy variables, the proxy URL, and current `CodexProxy` node.

Codex relay commands manage only Codex config:

- `codex_use_domestic`: writes `~/.codex/config.toml` using `CODEX_DOMESTIC_BASE_URL`.
- `codex_use_overseas`: writes `~/.codex/config.toml` using `CODEX_OVERSEAS_BASE_URL`.
- `codex_relay_status`: prints the active relay and current configured base URL.
- `codex_verify`: runs a Codex smoke test against the current Codex config.

No proxy command should call a Codex relay switch. No Codex relay command should enable or disable proxy variables.

## Internal Architecture

Keep shell scripts, but split responsibilities more clearly:

- `start.sh`: user-facing dispatcher for first run and reconfiguration flags.
- `setup_mihomo.sh`: install/restart Mihomo from a subscription URL and inject controller/proxy group config.
- `bootstrap_codex.sh`: install Codex CLI when missing, write auth/config, and install shell hook.
- `verify_codex.sh`: verify relay URLs and Codex smoke test without changing proxy state unless explicitly requested.
- `lib/codex_common.sh`: shared logging, config loading/saving, proxy commands, relay commands, status helpers, and smoke-test helpers.

The current `.env` loader should be replaced or downgraded to an optional compatibility path. Normal command loading should use `~/.config/clash-autodl-codex/config.sh`.

## Error Handling

- Missing subscription URL: prompt again unless running in non-interactive mode.
- Mihomo download failure: show which download failed and suggest rerunning after checking network.
- Invalid subscription format: keep the current converter fallback and explain that a Clash YAML subscription is preferred.
- Mihomo controller unreachable: `proxy_pick` and `proxy_status` should explain that Mihomo may not be running.
- Missing Codex CLI: install after Clash is ready, using proxy variables for the installer process.
- Invalid relay URL: reject empty values and values without `http://` or `https://`.
- Codex smoke-test failure: show the log path and current relay, but do not delete user config.

## Security

- API key input should avoid terminal echo when possible.
- Local config and auth files should be `chmod 600`.
- README should remind users not to paste secrets into public issues, logs, or repositories.
- `codex_audit_host` and status output should not print the full API key or full Clash subscription URL.

## Testing

Add or update smoke tests for:

- First-run prompt flow using piped input and fake installers.
- Config persistence to `~/.config/clash-autodl-codex/config.sh`.
- Proxy commands do not modify Codex relay config.
- Codex relay commands do not modify proxy environment variables.
- `proxy_status` displays current node from a fake Mihomo controller.
- `codex_relay_status` displays the active relay.
- Existing `proxy_pick` controller behavior.
- Existing custom proxy/controller port behavior.

CI should keep Bash syntax checks, ShellCheck, helper command checks, smoke tests, and secret scans.

## Migration From Current Version

Existing users with `.env` should still be able to run a compatibility command or first-run migration:

```bash
bash start.sh --import-env .env
```

This imports values into `~/.config/clash-autodl-codex/config.sh`, writes Codex auth/config, and keeps `.env` untouched.

If no `.env` exists, `bash start.sh` should use the new interactive path directly.

## README Update

README should lead with:

```bash
git clone https://github.com/KiRinXC/clash-Autodl-codex.git
cd clash-Autodl-codex
bash start.sh
```

Then it should show daily commands grouped by responsibility:

```text
代理命令:
proxy_on
proxy_off
proxy_pick
proxy_status

Codex 中转站命令:
codex_use_domestic
codex_use_overseas
codex_relay_status
codex_verify
```

The `.env` section should be removed from the primary path and moved to an advanced compatibility note if kept at all.
