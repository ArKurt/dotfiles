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

## 📱 移动端(Android / iOS,均已验证)

桌面是「系统代理 / TUN」二选一;**手机端(Android VpnService、iOS Network Extension)
本身就以 VPN 形式运行——你点「启动」那一下就等于桌面的 TUN**,流量已被透明接管。
所以手机上找不到独立的 TUN 开关是正常的,不影响使用。

目标同桌面:**指定流量强制走代理,其余按规则分流**。两平台认流量的机制不同:

| 平台 | 客户端 | 怎么匹配 | 规则类型 |
|---|---|---|---|
| Android | FlClash / Clash Meta | 按**包名**(同桌面进程规则) | `PROCESS-NAME` |
| iOS | Shadowrocket | iOS 不暴露 App 身份,只能按**域名** | `DOMAIN-SUFFIX` / `RULE-SET` |

### Android(FlClash)

1. 出站模式选 **规则**,启动 VPN(这就是 TUN);**「TUN 模式」开关不用额外开**。
2. 进 **订阅 → 覆写**(向导式表单,非手写 YAML),加一条:
   - 规则名称 → `PROCESS-NAME`(**别选** `PROCESS-PATH` / `-REGEX`)
   - 匹配值 → 安卓**包名**(如 ChatGPT 的 `com.openai.chatgpt`,纯包名无引号)
   - 策略 → `<PROXY_GROUP>`
   - 等价于 `PROCESS-NAME,com.openai.chatgpt,<PROXY_GROUP>`
3. 保存后**回订阅页重新激活一次**配置;其余 App 自动按订阅规则分流。

**「应用访问控制」(分应用代理)三种模式别设错:**
- **关闭** → 所有 App 都进 VPN(配合规则模式,这是**最终想要的状态**)。
- 白名单 → 只有勾选的 App 进 VPN(适合**隔离测试单个 App**,不是最终态)。
- 黑名单 → 勾选的 App 不进 VPN(适合排除银行 / 国内 App)。

> 验证:FlClash「连接」页应显示 `auth.openai.com → com.openai.chatgpt → <某美区节点> → <PROXY_GROUP>`,进程规则命中、走了正确地区节点。

### iOS(Shadowrocket)

iOS 拿不到 App 身份,改成**把目标服务的域名指向代理**,效果一样:

1. **全局路由**选 **配置 / Config**(规则模式);**别用 全局 / Proxy**,否则一刀切全代理。
2. 加 OpenAI 域名规则,二选一:
   - **规则集(推荐,域名自动更新)** —— 在 `[Rule]` 段加:
     ```
     RULE-SET,https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list,<PROXY_GROUP>
     ```
   - **手动域名规则:**
     ```
     DOMAIN-SUFFIX,openai.com,<PROXY_GROUP>
     DOMAIN-KEYWORD,openai,<PROXY_GROUP>
     DOMAIN-SUFFIX,chatgpt.com,<PROXY_GROUP>
     DOMAIN-SUFFIX,oaistatic.com,<PROXY_GROUP>
     DOMAIN-SUFFIX,oaiusercontent.com,<PROXY_GROUP>
     DOMAIN-SUFFIX,sora.com,<PROXY_GROUP>
     ```
   - 手动加规则时,「扩展匹配」「预匹配」两个开关**保持默认关闭**——域名规则用不上它们。
3. 其余流量继续按订阅规则分流。

> 验证:用 ChatGPT 发条消息,Shadowrocket 连接日志里 `*.openai.com` / `chatgpt.com` 的**策略列应是 `<PROXY_GROUP>`、节点在美区**;国内站应走 `DIRECT`。

### ⚠️ 两个共同的坑

1. **节点地区** —— OpenAI 封香港 / 大陆。`<PROXY_GROUP>` 必须停在**美 / 日 / 新 / 台 / 英**等支持区,
   别用可能飘到香港的 `Auto`,否则走了代理也报 `unsupported_country`。
   (`<PROXY_GROUP>` 是个可切换节点的组:规则负责把流量送进去,你要保证它的**出口节点**在支持区。)
2. **ChatGPT「Continue with Google」登录失败**(与代理无关) —— 报 Play 服务 / `-9` 之类,
   是 Google 登录 / Play Integrity 的问题,不是代理。**改用邮箱 + 密码登录**即可绕过
   (只用 Google 注册过的账号,先在登录页「忘记密码」给邮箱设个密码)。
