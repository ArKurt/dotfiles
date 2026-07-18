# selective-proxy 🧦

给编码 Agent / 终端 CLI 提供可控代理。既支持「本机 Clash 按进程分流」,也支持
「网络已经由旁路由透明代理、本机 Clash 只作临时兜底」；两种架构不要叠加。

> 本文把具体的 Clash 客户端名和订阅/代理组名都隐去了。用的时候按下面的占位符替换:
> - `<PROXY_GROUP>` —— 你订阅里那个能切节点的主代理组名(在客户端「代理」页看标题)。
> - `<MIXED_PORT>` —— 你客户端的混合端口(常见默认 `7890`,本仓库示例脚本用 `7897`)。
> - 客户端需使用 Mihomo/Clash Meta 内核,并支持 TUN 模式与进程规则。

## 先选部署模式（互斥）

| 模式 | 本机系统代理 | 本机 TUN | Shell 环境变量 | 适用场景 |
|---|---:|---:|---:|---|
| **A · 本机按进程分流** | 关 | 开 | 默认关、必要时兜底 | 设备直接接普通网关,需要本机 Clash 决定哪些进程代理 |
| **B · 旁路由主路径** | 关 | 关 | 默认关、仅故障/A-B 测试时 `proxy` | 默认网关已经是 OpenWrt/ImmortalWrt 等透明代理旁路由 |

**不要同时开本机系统代理、TUN、常驻 `*PROXY` 和旁路由透明代理。** 多层接管会让
真实路径难以判断,还会让长驻进程硬依赖 `127.0.0.1:<MIXED_PORT>`；一旦关掉本机 Clash,
这些旧进程立即断联,不会自动回退旁路由。

## 原理:两个互相独立的概念

Clash 里这两件事是分开的,搞混就会"一刀切":

1. **代理模式(规则 / 全局 / 直连)** —— 决定 Clash 收到流量后怎么转发。
2. **流量怎么进 Clash** —— 由"系统代理开关"或"TUN 模式"决定。

一刀切的做法是「系统代理 + 全局」,于是**所有** app 被强制代理。
模式 A 要的是 **TUN 模式 + 规则模式 + 进程优先规则**:
TUN 透明接管全机流量(GUI 进程也能被规则匹配),规则模式让你写的
`PROCESS-NAME` 规则生效,把点名的进程**强制丢给代理组**,其余流量继续走订阅规则。

| 流量来源 | 走向 |
|---|---|
| Cursor / Claude Code / Codex CLI 等 | 强制代理 ✅ |
| 终端里的 git / curl / npm / python 等 | 强制代理 ✅ |
| 浏览器及其它 app | 按订阅规则自动分流(该直连直连、该代理代理)✅ |

## 模式 A:Clash 客户端配置(手动,跨平台通用)

> 这一节只适用于**本机按进程分流**。如果默认网关已指向旁路由,跳到模式 B。

1. **关闭"系统代理"**开关 —— TUN 接管后不需要它,留着可能重复代理。
2. **打开 TUN 模式(虚拟网卡)** —— 首次可能要安装服务 / 授权。
3. **代理模式选「规则」** —— 只有规则模式下 `PROCESS-NAME` 才生效。
4. **加进程优先规则**:别直接改订阅(更新会被覆盖),用客户端的覆写功能把规则插到
   订阅规则之前。以 **Clash Verge Rev 2.x** 为例,进入「订阅 → 全局扩展脚本」加入:

```javascript
function main(config) {
  const selectiveProxyRules = [
    "PROCESS-NAME,cursor,<PROXY_GROUP>",
    "PROCESS-NAME,codex,<PROXY_GROUP>",
    "PROCESS-NAME,Codex (Service),<PROXY_GROUP>", // macOS Codex 桌面端
    "PROCESS-NAME,git,<PROXY_GROUP>",
    "PROCESS-NAME,curl,<PROXY_GROUP>",
    "PROCESS-NAME,wget,<PROXY_GROUP>",
    "PROCESS-NAME,npm,<PROXY_GROUP>",
    // 可选宽匹配；会影响所有 Node/Python 程序,确认需要再打开:
    // "PROCESS-NAME,node,<PROXY_GROUP>",
    // "PROCESS-NAME,python3,<PROXY_GROUP>",
  ];
  config.rules = [...selectiveProxyRules, ...(config.rules || [])];
  return config;
}
```

如果其它客户端明确支持 `prepend-rules`,可以把它作为生成阶段的扩展；它不是 Mihomo
核心字段。**Clash Verge Rev 2.5.1 实测不能把 `prepend-rules` 留在最终配置顶层**——看似
保存成功,实际不会插入 `rules:`。因此 Merge/「全局扩展覆写配置」为空是正常的,规则应放
在「全局扩展脚本」。保存后重新激活订阅,再到「当前配置」确认规则真的位于 `rules:` 首部。

> **关键:`PROCESS-NAME` 匹配的是真正发起连接的那个进程,不是终端窗口。**
> 你在终端跑 `curl` 发包的是 `curl`,跑 `npm install` 发包的是 `node`。
> 所以"让终端里的一切走代理"得把常用 CLI 名字都列上;漏了哪个,去「连接」页看它
> 显示的真实进程名,补一条即可。
>
> **Windows 上进程名通常带 `.exe`**:写成 `Cursor.exe` / `node.exe` / `codex.exe`
> / `git.exe` / `curl.exe` / `pwsh.exe` 等。
>
> **macOS 的 GUI App 可能由 Helper 进程真正联网**。不要猜名字,直接在客户端「连接」页
> 看 Process/进程列；必要时用 `PROCESS-PATH` 精确匹配 App 内的 Helper,避免把所有
> `node` 进程都送进代理。

## Shell 环境变量(两种模式都只作显式兜底)

进程规则覆盖不到的终端工具,用环境变量再兜一层。安装器同时设置大小写两套变量,
并使用 `socks5h` 让 SOCKS 连接的域名也交给代理解析。

### macOS / Linux 自动安装

```bash
./install.sh proxy                    # 自动识别 zsh / bash / fish,默认端口 7897
CLASH_PORT=7890 ./install.sh proxy    # 自定义混合端口
source ~/.zshrc                       # macOS 默认 shell；也可以直接开新终端

proxy          # 端口存在才开启；避免 Clash 没启动时把终端变成断网状态
unproxy        # 关闭本 shell 会话的大小写代理变量
proxy_status   # 查看环境变量和本地端口状态
```

安装器在 macOS 写 `~/.zshrc`,Linux 则按当前 shell 写 `~/.bashrc` 或
`~/.config/fish/config.fish`。重复安装会**更新自己的受管区块**,不会重复追加,也不会改
其它配置。默认不开环境变量:模式 A 仍由 TUN + 进程规则工作,模式 B 则直接交给旁路由。
只有确认必须让所有新 shell 硬连本机 Clash 时才使用:

```bash
PROXY_DEFAULT_ON=1 ./install.sh proxy
```

> **慎用 `PROXY_DEFAULT_ON=1`。** `.zshrc` 改回默认关闭后,已经运行的 ChatGPT/Codex、IDE
> 或 Agent 仍保留旧环境；必须重启这些长驻进程,否则关 Clash 时它们仍会因 7897 消失而断联。

默认生成的变量是:

```text
HTTP_PROXY / http_proxy   = http://127.0.0.1:<MIXED_PORT>
HTTPS_PROXY / https_proxy = http://127.0.0.1:<MIXED_PORT>
ALL_PROXY / all_proxy     = socks5h://127.0.0.1:<MIXED_PORT>
NO_PROXY / no_proxy       = localhost,127.0.0.1,::1,.local,192.168.0.0/16,100.64.0.0/10,.tailscale.com,fd7a:115c:a1e0::/48
```

### Windows(PowerShell)

在 `$PROFILE` 里加(`notepad $PROFILE`):

```powershell
$env:HTTP_PROXY  = "http://127.0.0.1:<MIXED_PORT>"
$env:HTTPS_PROXY = "http://127.0.0.1:<MIXED_PORT>"
$env:ALL_PROXY   = "socks5h://127.0.0.1:<MIXED_PORT>"
$env:NO_PROXY    = "localhost,127.0.0.1,::1,.local"

function proxy   { $env:HTTP_PROXY="http://127.0.0.1:<MIXED_PORT>"; $env:HTTPS_PROXY=$env:HTTP_PROXY; $env:ALL_PROXY="socks5h://127.0.0.1:<MIXED_PORT>"; $env:NO_PROXY="localhost,127.0.0.1,::1,.local"; "代理已开启" }
function unproxy { Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY,Env:ALL_PROXY,Env:NO_PROXY -ErrorAction SilentlyContinue; "代理已关闭" }
```

## 模式 B:旁路由主路径

当设备默认网关已经指向旁路由时,本机 Clash 不再承担透明接管:

1. 本机「系统代理」关、TUN 关。
2. Shell 保持 `unproxy`；重启所有曾继承 `127.0.0.1:<MIXED_PORT>` 的 GUI/Agent。
3. 用清空代理变量后的直连测试验收旁路由,不要拿旧进程作证:

```bash
route -n get default | grep -E 'gateway|interface'
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
    curl --noproxy '*' -I https://api.github.com
```

需要临时强制某个会话经本机 Clash、或对比两条代理路径时才执行 `proxy`；完成后 `unproxy`。

## 验证

### 模式 A

打开客户端「**连接**」页,操作一下目标工具,看那条连接:

- **进程(Process)列** —— 确认进程名,跟你写的规则对得上;对不上就照实际名字补一条。
- **规则 / 链路列** —— 应命中你的 `PROCESS-NAME` 规则、走了代理组节点。
- 顺手开浏览器访问国内站点,应走 `DIRECT`。

命令行快速自检:

```bash
proxy_status
curl -s https://api.ipify.org; echo   # 出口 IP 应是代理节点的
```

### 模式 B

- `scutil --proxy`（macOS）应显示 HTTP/HTTPS/SOCKS 均关闭。
- 默认路由的 gateway 应是旁路由地址。
- 清空八个大小写 `*PROXY` 后仍能解析并连接目标服务。
- 用 `ps eww -p <PID>` 只筛代理变量,确认长驻 Agent 没残留 `127.0.0.1:7897`。

## 排错

- **代理通但网页打不开 / 解析失败** —— 多半是开 TUN 后的 DNS 问题,检查客户端的
  DNS / fake-ip 配置(一般默认配置即可)。
- **某进程没走代理** —— 它发包的真实进程名不在规则里,去「连接」页看名字补上。
- **本地服务被代理影响** —— 确认 `no_proxy` 含 `localhost,127.0.0.1`。
- **Clash Verge 的 Merge 里看不到规则** —— 这是预期行为:进程规则在「全局扩展脚本」,
  Merge 为空即可。重新激活后检查最终配置的 `rules:` 首部,不要检查顶层 `prepend-rules`。
- **关 Clash 后 Agent 断联** —— 旧进程仍继承 `*PROXY=127.0.0.1:<MIXED_PORT>`；确认新
  shell 已干净后重启 ChatGPT/Codex/IDE。修改 rc 文件不会追溯更新已运行进程。

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

iOS 拿不到 App 身份,所以只能改成**把目标服务的域名指向代理**。这是服务级分流,
并不等同于 App 级分流:其它 App 访问相同域名也会走代理,未列出的新域名则可能漏掉。

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

1. **节点地区** —— 出口必须位于 OpenAI 当前支持的地区；名单会变化,以
   [OpenAI 官方列表](https://help.openai.com/en/articles/5347006)为准。别让 `Auto`
   漂到不支持的地区,否则即使规则命中也可能报 `unsupported_country`。
2. **第三方登录不是代理开关问题** —— 使用 Google/Microsoft/Apple 注册的账号应继续用
   原方式登录,不能靠「忘记密码」改成邮箱密码。遇到登录问题按
   [OpenAI 官方排错说明](https://help.openai.com/en/articles/7426629)处理。
