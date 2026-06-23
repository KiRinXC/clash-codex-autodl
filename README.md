# clash-Autodl-codex

`clash-Autodl-codex` 是一个面向 AutoDL / SeetaCloud Linux 主机的 Codex 配置工具。

它会帮助用户完成三件事：

- 安装并启动 Mihomo/Clash 代理。
- 生成 Codex 需要的 `~/.codex/auth.json` 和 `~/.codex/config.toml`。
- 提供 `proxy_on`、`proxy_off`、`proxy_pick`，方便在终端里开启代理、关闭代理和切换节点。

## 适用场景

适合下面这种环境：

- 服务器运行在 AutoDL、SeetaCloud 或类似 Linux 云主机上。
- 用户有自己的 OpenAI 兼容中转站。
- 用户有 Clash/Mihomo 订阅地址。
- 部分中转站需要代理访问，部分中转站可以直连访问。

## 下载项目

在目标服务器上执行：

```bash
git clone https://github.com/KiRinXC/clash-Autodl-codex.git
cd clash-Autodl-codex
```

如果仓库目录名不是 `clash-Autodl-codex`，进入实际目录即可。

## 配置 `.env`

复制示例配置：

```bash
cp .env.example .env
vim .env
```

必须填写：

```bash
export OPENAI_API_KEY=''
export CLASH_URL=''
export CODEX_DOMESTIC_BASE_URL=''
export CODEX_OVERSEAS_BASE_URL=''
```

说明：

- `OPENAI_API_KEY`：Codex 使用的 API key。
- `CLASH_URL`：Clash/Mihomo 订阅地址。
- `CODEX_DOMESTIC_BASE_URL`：关闭代理时使用的中转站地址。
- `CODEX_OVERSEAS_BASE_URL`：开启代理时使用的中转站地址。

可选配置：

```bash
export CODEX_RELAY_MODE='auto'
export CODEX_PROXY_URL='http://127.0.0.1:7890'
export CODEX_MIHOMO_CONTROLLER_URL='http://127.0.0.1:6006'
export CODEX_PROXY_GROUP='CodexProxy'
export CODEX_MODEL='gpt-5.4'
export CODEX_REVIEW_MODEL='gpt-5.4'
export AUTO_PROXY_ON_SHELL_START='true'
```

通常不需要修改这些值。`AUTO_PROXY_ON_SHELL_START='true'` 表示新终端会自动加载代理命令，并默认执行 `proxy_on`。
如果你的 `7890` 或 `6006` 端口已经被占用，也可以改 `CODEX_PROXY_URL` 和 `CODEX_MIHOMO_CONTROLLER_URL`，脚本会同步写入 Mihomo 配置。

## 启动程序

执行：

```bash
bash start.sh .env
```

脚本会依次完成：

- 检查当前主机环境。
- 写入 `~/.codex/auth.json`。
- 写入 `~/.codex/config.toml`。
- 下载并启动 Mihomo/Clash。
- 创建 `CodexProxy` 节点选择组。
- 测试开启代理后的国外中转站。
- 测试关闭代理后的国内中转站。
- 运行 Codex 冒烟测试，确认 Codex 能回复 `CODEX_RELAY_READY`。

## 加载命令

首次启动完成后，重新打开一个终端即可。

如果不想重新打开终端，可以手动加载：

```bash
source ~/.codex/clash-autodl-codex.sh
```

加载成功后，终端会显示：

```text
[成功] clash-Autodl-codex 命令已加载: proxy_on, proxy_off, proxy_pick
```

## 常用命令

开启代理，并让 Codex 使用 `CODEX_OVERSEAS_BASE_URL`：

```bash
proxy_on
```

关闭当前终端的代理，并让 Codex 使用 `CODEX_DOMESTIC_BASE_URL`：

```bash
proxy_off
```

查看当前节点，并交互式切换 `CodexProxy` 节点：

```bash
proxy_pick
```

重新执行初始化（会重新安装/配置并做校验）：

```bash
bash bootstrap_codex.sh .env
```

只运行验证：

```bash
bash verify_codex.sh auto .env
```

## 切换节点

执行：

```bash
proxy_pick
```

它会显示：

- 当前 `CodexProxy` 选择的是 `DIRECT` 还是某个节点。
- 当前订阅中可选的所有节点。
- 输入编号后切换到对应节点。

如果当前是 `DIRECT`，访问某些站点可能仍然是直连。请选择一个可用节点后再测试 Codex。

## 修改配置后重新应用

修改 `.env` 后，重新执行：

```bash
bash start.sh .env
```

如果只是切换当前终端的国内/国外中转配置，也可以重新加载命令后执行：

```bash
source ~/.codex/clash-autodl-codex.sh
proxy_on
```

或者：

```bash
source ~/.codex/clash-autodl-codex.sh
proxy_off
```

## 健康检查

完整检查：

```bash
bash verify_codex.sh auto .env
```

按代理模式验证（仍会执行 Codex 冒烟测试）：

```bash
bash verify_codex.sh overseas .env
```

按直连模式验证（仍会执行 Codex 冒烟测试）：

```bash
bash verify_codex.sh domestic .env
```

验证成功时，应看到：

- 开启代理后，中转站可以访问。
- 关闭代理后，中转站可以访问。
- Codex 冒烟测试成功。

## 卸载

只移除 shell 启动钩子：

```bash
bash uninstall_codex_bootstrap.sh
```

同时删除生成的 Codex 配置：

```bash
bash uninstall_codex_bootstrap.sh --remove-codex-config
```

## 常见问题

### 为什么执行 `start.sh` 后还没有 `proxy_on`？

`proxy_on`、`proxy_off`、`proxy_pick` 是 shell 函数。首次安装后，需要重新打开终端，或者执行：

```bash
source ~/.codex/clash-autodl-codex.sh
```

### 为什么开启了代理还是访问失败？

先执行：

```bash
proxy_pick
```

如果当前节点是 `DIRECT`，说明还在直连。请选择一个可用节点后再测试。

### 为什么提示中转站地址为空？

仓库不会内置任何中转站地址。请在 `.env` 中填写自己的：

```bash
CODEX_DOMESTIC_BASE_URL
CODEX_OVERSEAS_BASE_URL
```

### 为什么不要提交 `.env`？

`.env` 里通常包含 API key、订阅地址和中转站地址。这些都属于敏感信息，不应该提交到公开仓库。

## 安全注意

不要提交这些内容：

- `.env`
- `~/.codex/auth.json`
- Clash/Mihomo 订阅 URL
- SSH 登录信息
- 生成的日志、缓存、二进制文件和运行配置

如果 API key 曾经出现在聊天记录、日志或错误输出里，建议及时轮换。
