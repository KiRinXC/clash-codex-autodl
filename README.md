# clash-Autodl-codex

`clash-Autodl-codex` 用来在 AutoDL、SeetaCloud 或类似 Linux 云主机上快速配置 Mihomo/Clash 和 Codex CLI。

新租的机器通常没有 Clash，也没有 Codex。这个项目的目标是让你通过一个交互式脚本完成初始化，然后在之后的终端里直接使用代理和 Codex 中转站切换命令。

## 快速开始

在目标服务器上执行：

```bash
git clone https://github.com/KiRinXC/clash-Autodl-codex.git
cd clash-Autodl-codex
bash start.sh
```

脚本会依次提示你输入：

```text
Clash/Mihomo subscription URL
Domestic/direct Codex relay URL
Overseas/proxy Codex relay URL
OpenAI API key
```

这些内容会持久化到本机：

```text
~/.config/clash-autodl-codex/config.sh
~/.codex/auth.json
~/.codex/config.toml
~/.codex/clash-autodl-codex.sh
```

不需要手动复制或编辑 `.env`。

## 初始化流程

`bash start.sh` 会完成：

- 下载 Clash/Mihomo 订阅。
- 安装并启动 Mihomo。
- 创建 `CodexProxy` 节点选择组。
- 安装终端启动钩子。
- 显示代理开启、关闭、节点切换和状态命令。
- 检查 `codex` 命令是否可用，不可用时通过当前代理下载 Codex CLI。
- 写入 Codex API key 和 `~/.codex/config.toml`。
- 运行 Codex 冒烟测试，确认能回复 `CODEX_RELAY_READY`。

## 代理命令

代理命令只控制当前 shell 的代理环境变量和 Mihomo 节点，不会切换 Codex 中转站。

```bash
proxy_on
proxy_off
proxy_pick
proxy_status
```

- `proxy_on`：为当前 shell 设置 `http_proxy`、`https_proxy` 等代理环境变量。
- `proxy_off`：移除当前 shell 的代理环境变量。
- `proxy_pick`：交互式切换 `CodexProxy` 选择组里的节点。
- `proxy_status`：显示代理是否开启、Mihomo 是否运行、代理地址和当前节点。

## Codex 中转站命令

Codex 中转站命令只修改 `~/.codex/config.toml`，不会开启或关闭代理。

```bash
codex_use_domestic
codex_use_overseas
codex_relay_status
codex_verify
```

- `codex_use_domestic`：让 Codex 使用国内/直连中转站。
- `codex_use_overseas`：让 Codex 使用国外/代理中转站。
- `codex_relay_status`：显示当前 Codex 使用的中转站。
- `codex_verify`：运行 Codex 冒烟测试。

如果你想通过代理访问国外中转站，通常需要手动组合：

```bash
proxy_on
codex_use_overseas
codex_verify
```

如果你想回到直连：

```bash
proxy_off
codex_use_domestic
codex_verify
```

## 新终端自动检查

初始化完成后，新开的终端会自动加载：

```bash
source ~/.codex/clash-autodl-codex.sh
```

启动钩子会显示：

```text
[INFO] clash-Autodl-codex 命令已加载
[INFO] 代理: 已开启/未开启
[INFO] Mihomo: 运行中/未运行
[INFO] 当前节点: <node name>
[INFO] Codex 中转站: domestic/overseas <url>
[OK] Codex 可用
```

如果网络或中转站临时不可用，命令仍会加载，终端会给出失败提示和日志位置。

## 重新配置

重新配置全部内容：

```bash
bash start.sh --reconfigure
```

只重新配置 Clash/Mihomo 订阅：

```bash
bash start.sh --reconfigure-clash
```

只重新配置 Codex 中转站和 API key：

```bash
bash start.sh --reconfigure-codex
```

## 验证

检查当前 Codex 配置：

```bash
bash verify_codex.sh current
```

切到国内/直连中转站后验证：

```bash
bash verify_codex.sh domestic
```

切到国外/代理中转站后验证：

```bash
bash verify_codex.sh overseas
```

## 从旧 `.env` 导入

如果你已经有旧版 `.env`，可以导入到本机持久化配置：

```bash
bash start.sh --import-env .env
```

导入后 `.env` 不再是日常使用路径。

## 卸载

只移除 shell 启动钩子：

```bash
bash uninstall_codex_bootstrap.sh
```

同时删除 Codex 配置：

```bash
bash uninstall_codex_bootstrap.sh --remove-codex-config
```

同时删除本项目的本机配置：

```bash
bash uninstall_codex_bootstrap.sh --remove-local-config
```

## 安全注意

不要提交或公开这些内容：

- `~/.config/clash-autodl-codex/config.sh`
- `~/.codex/auth.json`
- Clash/Mihomo 订阅 URL
- OpenAI API key
- SSH 登录信息
- 生成的日志、缓存、二进制文件和运行配置

如果 API key 曾经出现在聊天记录、日志或错误输出里，建议及时轮换。
