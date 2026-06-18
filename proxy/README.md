# selective-proxy 🧦

让**指定的工具**(编码 Agent、终端 CLI)无条件走代理节点,其余流量(浏览器等)
仍按订阅规则自动分流。适合在 VM / NAT 环境里:你的 AI Agent 需要"全局"才能联网,
但又不想把整机都塞进代理。

> 本文把具体的 Clash 客户端名和订阅/代理组名都隐去了。用的时候按下面的占位符替换:
> - `<PROXY_GROUP>` —— 你订阅里那个能切节点的主代理组名(在客户端「代理」页看标题)。
> - `<MIXED_PORT>` —— 你客户端的混合端口(常见默认 `7890`,本仓库示例脚本用 `7897`)。
> - 客户端需为**支持 TUN 模式 + `PROCESS-NAME` 进程规则**的 Clash 类客户端。

## 原理:两个互相独立的概念

Clash 里这两件事是分开的,搞混就会"一刀切":

1. **代理模式(规则 / 全局 / 直连)** —— 决定 Clash 收到流量后怎么转发。
2. **流量怎么进 Clash** —— 由"系统代理开关"或"TUN 模式"决定。

一刀切的做法是「系统代理 + 全局」,于是**所有** app 被强制代理。
我们要的是 **TUN 模式 + 规则模式 + 进程优先规则**:
TUN 透明接管全机流量(GUI 进程也能被规则匹配),规则模式让你写的
`PROCESS-NAME` 规则生效,把点名的进程**强制丢给代理组**,其余流量继续走订阅规则。

| 流量来源 | 走向 |
|---|---|
| Cursor / Claude Code / Codex CLI 等(多为 `node`) | 强制代理 ✅ |
| 终端里的 git / curl / npm / python 等 | 强制代理 ✅ |
| 浏览器及其它 app | 按订阅规则自动分流(该直连直连、该代理代理)✅ |

## 第一层:Clash 客户端配置(手动,跨平台通用)

1. **关闭"系统代理"**开关 —— TUN 接管后不需要它,留着可能重复代理。
2. **打开 TUN 模式(虚拟网卡)** —— 首次可能要安装服务 / 授权。
3. **代理模式选「规则」** —— 只有规则模式下 `PROCESS-NAME` 才生效。
4. **加进程优先规则**:别直接改订阅(更新会被覆盖),用客户端的
   **Merge / 全局扩展配置**功能,插入 `prepend-rules`:

```yaml
prepend-rules:
  - PROCESS-NAME,cursor,<PROXY_GROUP>
  - PROCESS-NAME,node,<PROXY_GROUP>      # Cursor 内置 AI / Claude Code / Codex CLI 多跑在 node 上
  - PROCESS-NAME,codex,<PROXY_GROUP>     # Codex CLI 兜底
  - PROCESS-NAME,fish,<PROXY_GROUP>      # 终端 shell(按你的 shell 改:bash/zsh...)
  - PROCESS-NAME,git,<PROXY_GROUP>
  - PROCESS-NAME,curl,<PROXY_GROUP>
  - PROCESS-NAME,wget,<PROXY_GROUP>
  - PROCESS-NAME,npm,<PROXY_GROUP>
  - PROCESS-NAME,python,<PROXY_GROUP>
  - PROCESS-NAME,python3,<PROXY_GROUP>
```

保存后回订阅页**重新激活一次**配置,让 `prepend-rules` 加载进去。

> **关键:`PROCESS-NAME` 匹配的是真正发起连接的那个进程,不是终端窗口。**
> 你在终端跑 `curl` 发包的是 `curl`,跑 `npm install` 发包的是 `node`。
> 所以"让终端里的一切走代理"得把常用 CLI 名字都列上;漏了哪个,去「连接」页看它
> 显示的真实进程名,补一条即可。
>
> **Windows 上进程名通常带 `.exe`**:写成 `Cursor.exe` / `node.exe` / `codex.exe`
> / `git.exe` / `curl.exe` / `pwsh.exe` 等。

## 第二层:Shell 环境变量(终端兜底)

进程规则覆盖不到的终端工具,用环境变量再兜一层(读 `http_proxy` 的 CLI 都吃这套)。
两层叠加,漏网概率极低。

### Linux(fish)

`./install.sh proxy` 会**幂等**地把下面这段写进
`~/.config/fish/config.fish`(已存在则跳过,不覆盖你的其它配置),
也可以手动粘贴:

```fish
set -gx http_proxy  http://127.0.0.1:<MIXED_PORT>
set -gx https_proxy http://127.0.0.1:<MIXED_PORT>
set -gx all_proxy   socks5://127.0.0.1:<MIXED_PORT>
set -gx no_proxy    localhost,127.0.0.1,::1

# 临时开关:本会话 unproxy 关、proxy 开
function proxy
    set -gx http_proxy  http://127.0.0.1:<MIXED_PORT>
    set -gx https_proxy http://127.0.0.1:<MIXED_PORT>
    set -gx all_proxy   socks5://127.0.0.1:<MIXED_PORT>
    set -gx no_proxy    localhost,127.0.0.1,::1
    echo "代理已开启"
end
function unproxy
    set -e http_proxy https_proxy all_proxy no_proxy
    echo "代理已关闭"
end
```

bash/zsh 同理,把 `set -gx X Y` 换成 `export X=Y` 放进 `~/.bashrc` / `~/.zshrc`。

### Windows(PowerShell)

在 `$PROFILE` 里加(`notepad $PROFILE`):

```powershell
$env:HTTP_PROXY  = "http://127.0.0.1:<MIXED_PORT>"
$env:HTTPS_PROXY = "http://127.0.0.1:<MIXED_PORT>"
$env:ALL_PROXY   = "socks5://127.0.0.1:<MIXED_PORT>"
$env:NO_PROXY    = "localhost,127.0.0.1,::1"

function proxy   { $env:HTTP_PROXY="http://127.0.0.1:<MIXED_PORT>"; $env:HTTPS_PROXY=$env:HTTP_PROXY; "代理已开启" }
function unproxy { Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY,Env:ALL_PROXY,Env:NO_PROXY -ErrorAction SilentlyContinue; "代理已关闭" }
```

## 验证

打开客户端「**连接**」页,操作一下目标工具,看那条连接:

- **进程(Process)列** —— 确认进程名,跟你写的规则对得上;对不上就照实际名字补一条。
- **规则 / 链路列** —— 应命中你的 `PROCESS-NAME` 规则、走了代理组节点。
- 顺手开浏览器访问国内站点,应走 `DIRECT`。

命令行快速自检:

```bash
echo $https_proxy                     # 应显示 http://127.0.0.1:<MIXED_PORT>
curl -s https://api.ipify.org; echo   # 出口 IP 应是代理节点的
```

## 排错

- **代理通但网页打不开 / 解析失败** —— 多半是开 TUN 后的 DNS 问题,检查客户端的
  DNS / fake-ip 配置(一般默认配置即可)。
- **某进程没走代理** —— 它发包的真实进程名不在规则里,去「连接」页看名字补上。
- **本地服务被代理影响** —— 确认 `no_proxy` 含 `localhost,127.0.0.1`。
- **改了 Merge 不生效** —— 没重新激活配置;切走再切回订阅,或点一次激活。

---

## 📱 移动端(草稿,WIP)

Android / iOS 的同款方案整理在 [`mobile.DRAFT.md`](mobile.DRAFT.md)——**尚未全部验证完**
(Android 代理路由已通过,ChatGPT 登录问题与 iOS 实测待办)。验证完成后会晋升到本文正文。
