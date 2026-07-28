# selective-proxy 参考手册

`README.md` 讲怎么用;这里讲**为什么这么用**,以及各平台细节、完整规则模板和排错。

占位符沿用 README 的约定:`<PROXY_GROUP>` 主代理组、`<US_GROUP>` 美区组、`<MIXED_PORT>` 混合端口。

---

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

### 为什么两种模式不能叠加

**不要同时开本机系统代理、TUN、常驻 `*PROXY` 和旁路由透明代理。** 多层接管会让
真实路径难以判断,还会让长驻进程硬依赖 `127.0.0.1:<MIXED_PORT>`；一旦关掉本机 Clash,
这些旧进程立即断联,不会自动回退旁路由。

---

## 适配哪些客户端(通用性 · 2026-07-18 核验)

本套 `proxy`/`unproxy` **只认 `127.0.0.1:<MIXED_PORT>`,不认客户端**——凡 **Mihomo / Clash.Meta 内核**的都通用。已核验同属一核、可互换:

| 客户端 | 内核 | 备注 |
|---|---|---|
| **Clash Verge Rev** | Mihomo | 桌面·Tauri;本机实测 `proxy` 通(mixed-port 7897) |
| **FlClash**(chen08209) | Mihomo | Flutter·五端;核由 GUI 经 unix socket 驱动(不能命令行独立喂配置),详见 [flclash-notes.md](flclash-notes.md) |
| **FlClashX**(pluralplay·FlClash 分叉) | Mihomo | 同上 + 机场服务/仪表盘增强;⚠️ 可选 HWID 上报面板 |

**唯一前提 = 端口对齐**:把在用客户端的 **mixed-port 设成本仓库的 `<MIXED_PORT>`(默认 7897)**;或反过来 `CLASH_PORT=<客户端端口> ./install.sh proxy` 让脚本跟随。对齐后同一套 `proxy`/`unproxy` 在任意客户端下一致工作。

> 模式 B(旁路由/nikki 透明代理)**与客户端无关**——流量在网关层被接管,本机跑哪个 Clash、甚至不跑,都不影响。

---

## 模式 A:完整规则模板

别直接改订阅(更新会被覆盖),用客户端的覆写功能把规则插到订阅规则之前。
以 **Clash Verge Rev 2.x** 为例,进入「订阅 → 全局扩展脚本」加入:

```javascript
function main(config, profileName) {
  // 组名必须与订阅里的组名【逐字一致】,注意常带国旗 emoji + 空格,如 "🇺🇸 United States"
  const PROXY = "<PROXY_GROUP>"; // 主代理组
  const US    = "<US_GROUP>";    // 需美区落地的组(codex/claude 等);不需要就删掉相关行

  // 组名容错:引用了不存在的组,mihomo 会校验整份配置失败并回滚。
  // 读出真实存在的组,缺失时自动回退 —— 换订阅、跨机器也不崩。
  const groups = new Set((config["proxy-groups"] || []).map((g) => g.name));
  const pick = (n, fb) => (groups.has(n) ? n : fb);
  const P = pick(PROXY, "GLOBAL");
  const U = pick(US, P);

  const rules = [
    // — 局域网直连(最高优先级;LocalSend 等,详见下文「让局域网工具直连」)—
    "PROCESS-NAME,localsend,DIRECT",
    "DST-PORT,53317,DIRECT",
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
    "IP-CIDR,224.0.0.0/4,DIRECT,no-resolve",
    // — 国内服务显式直连,必须排在下面的进程规则之前(见排错「国内工具更新被误代理」)—
    "DOMAIN-SUFFIX,kimi.com,DIRECT",
    // — 编码 Agent / 终端 CLI 强制走代理 —
    // Cursor/VSCode 等 Electron 应用进程名都叫 electron,按进程会一刀切;改按域名关键字覆盖 Cursor 全家(cursor.sh/cursorapi.com/cursor-cdn.com)
    "DOMAIN-KEYWORD,cursor," + U,
    "PROCESS-NAME,codex," + U,
    "PROCESS-NAME,Codex (Service)," + U, // macOS Codex 桌面端
    "PROCESS-NAME,claude," + U,
    "PROCESS-NAME,git," + P,
    "PROCESS-NAME,curl," + P,
    "PROCESS-NAME,wget," + P,
    "PROCESS-NAME,npm," + P,
    // 可选宽匹配;会波及所有 Node/Python 程序,确认需要再打开:
    // "PROCESS-NAME,node," + P,
    // "PROCESS-NAME,python3," + P,
  ];

  // 让局域网组播绕过 TUN(LocalSend 等自动发现;详见下文「让局域网工具直连」)
  config.tun = config.tun || {};
  const ex = config.tun["route-exclude-address"] || [];
  for (const c of ["224.0.0.0/4", "255.255.255.255/32"]) if (!ex.includes(c)) ex.push(c);
  config.tun["route-exclude-address"] = ex;

  config.rules = [...rules, ...(config.rules || [])];
  return config;
}
```

### ⚠️ 规则必须放「全局扩展脚本」,不能放「扩展覆写配置(Merge)」

Clash Verge Rev(实测 2.5.x)会把 Merge 里的 `prepend-rules` 原样输出成最终配置的
**顶层 `prepend-rules:` 键**;而它不是 Mihomo 核心字段,内核直接忽略 → 你的进程规则
**全部静默失效**。更阴险的是失效后这些流量会被 `MATCH,<兜底组>` 接住、"看起来正常",
只有 `codex→美区组` 这种「指定去向」的意图悄悄废掉。

**别信生成的 yaml 文本,要问内核** —— 用外部控制 API 看真正生效的规则:

```bash
curl -s --unix-socket <mihomo.sock> -H "Authorization: Bearer <secret>" http://localhost/rules
```

脚本里改 `config.rules` 是直接操作最终数组,一定进 `rules:`。保存后重新激活订阅即可。

### PROCESS-NAME 匹配的是谁

**匹配的是真正发起连接的那个进程,不是终端窗口。**
你在终端跑 `curl` 发包的是 `curl`,跑 `npm install` 发包的是 `node`。
所以"让终端里的一切走代理"得把常用 CLI 名字都列上;漏了哪个,去「连接」页看它
显示的真实进程名,补一条即可。

- **Windows** 上进程名通常带 `.exe`:写成 `Cursor.exe` / `node.exe` / `codex.exe`
  / `git.exe` / `curl.exe` / `pwsh.exe` 等。
- **macOS** 的 GUI App 可能由 Helper 进程真正联网。不要猜名字,直接在客户端「连接」页
  看 Process/进程列；必要时用 `PROCESS-PATH` 精确匹配 App 内的 Helper,避免把所有
  `node` 进程都送进代理。
- **Android** 匹配的是**包名**(如 `com.openai.chatgpt`),不是可执行文件名。

---

## Shell 环境变量细节

安装器同时设置大小写两套变量,并使用 `socks5h` 让 SOCKS 连接的域名也交给代理解析。
默认生成的变量是:

```text
HTTP_PROXY / http_proxy   = http://127.0.0.1:<MIXED_PORT>
HTTPS_PROXY / https_proxy = http://127.0.0.1:<MIXED_PORT>
ALL_PROXY / all_proxy     = socks5h://127.0.0.1:<MIXED_PORT>
NO_PROXY / no_proxy       = localhost,127.0.0.1,::1,.local,192.168.0.0/16,100.64.0.0/10,.tailscale.com,fd7a:115c:a1e0::/48
```

安装器在 macOS 写 `~/.zshrc`,Linux 则按当前 shell 写 `~/.bashrc` 或
`~/.config/fish/config.fish`。重复安装会**更新自己的受管区块**,不会重复追加,也不会改
其它配置。

> **慎用 `PROXY_DEFAULT_ON=1`。** `.zshrc` 改回默认关闭后,已经运行的 ChatGPT/Codex、IDE
> 或 Agent 仍保留旧环境；必须重启这些长驻进程,否则关 Clash 时它们仍会因 `<MIXED_PORT>`
> 消失而断联。

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

---

## 验证细节

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

```bash
route -n get default | grep -E 'gateway|interface'
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
    curl --noproxy '*' -I https://api.github.com
```

- `scutil --proxy`(macOS)应显示 HTTP/HTTPS/SOCKS 均关闭。
- 默认路由的 gateway 应是旁路由地址。
- 清空八个大小写 `*PROXY` 后仍能解析并连接目标服务。
- 用 `ps eww -p <PID>` 只筛代理变量,确认长驻 Agent 没残留 `127.0.0.1:<MIXED_PORT>`。

---

## 排错

- **代理通但网页打不开 / 解析失败** —— 多半是开 TUN 后的 DNS 问题,检查客户端的
  DNS / fake-ip 配置(一般默认配置即可)。
- **某进程没走代理** —— 它发包的真实进程名不在规则里,去「连接」页看名字补上。
- **本地服务被代理影响** —— 确认 `no_proxy` 含 `localhost,127.0.0.1`。
- **Clash Verge 的 Merge 里看不到规则** —— 这是预期行为:进程规则在「全局扩展脚本」,
  Merge 为空即可。重新激活后检查最终配置的 `rules:` 首部,不要检查顶层 `prepend-rules`。
- **关 Clash 后 Agent 断联** —— 旧进程仍继承 `*PROXY=127.0.0.1:<MIXED_PORT>`；确认新
  shell 已干净后重启 ChatGPT/Codex/IDE。修改 rc 文件不会追溯更新已运行进程。
- **TUN 下测"另起的临时 mihomo 实例"会被自劫持** —— 本机全局 TUN 会接管临时实例的出站,
  测自建节点时出口 IP 变成**机场节点**而非节点真实出口(易误判成节点飘到别的地区)。干净
  测法:① 在节点服务器**本地自连**测出口;或 ② 用生产 Verge 自己的 mihomo(fwmark 排除
  自身、不自劫持)+ API `GET /proxies/{name}/delay` 测握手延迟。附:mihomo `PUT /configs`
  只收 home 或 Verge 数据目录(SAFE_PATHS)内的配置路径,`/tmp` 会被拒(400),临时配置放数据目录。
- **国内工具更新失败 / 大文件 TLS 掐断** —— `PROCESS-NAME,curl/npm/node→代理` 会把
  **国内服务**流量也误丢给海外节点(轻则慢,重则大文件报 `TLS unexpected eof`)。例:
  `kimi update` 从 `code`/`cdn.kimi.com` 下载几十 MB 二进制,被推到香港节点后 TLS 被掐。
  解法:给国内域名显式直连、且排在进程规则**之前** —— `DOMAIN-SUFFIX,kimi.com,DIRECT`。
  同理适用于其它国产 CLI 的自更新。

---

## 让局域网工具直连(LocalSend / AirDrop 类,仅模式 A)

模式 A 开 TUN 后,局域网互传工具会**一半坏一半好**,先分清:

| 环节 | 走向 | 说明 |
|---|---|---|
| **传输**(单播到 `192.168.x.x`) | 物理网卡直连 ✅ | 局域网有精确路由,不进 TUN,一般不用管 |
| **发现**(组播 `224.0.0.167`) | 被 TUN 吞 ❌ | `auto-route` 把组播拉进 TUN 的 gvisor,出不到局域网,**双方发现不到彼此** |

先实测确认是不是这个问题(关键看组播走哪个网卡):

```bash
ip route get 224.0.0.167     # 走 dev Meta/tun = 被 TUN 吞;走物理网卡(如 ens33)才正常
ip route get 192.168.1.50    # 局域网对端应走物理网卡直连
```

**修复** —— 上面的完整规则模板**已经内置**这两块(`tun.route-exclude-address` 排除组播
+ 4 条局域网直连置顶);从那份模板起步就无需再动,原理是:

- **让组播绕过 TUN** —— 给 `tun.route-exclude-address` 加 `224.0.0.0/4` + 广播(`strict-route`
  须为 `false`),组播回落物理网卡;
- **直连置顶** —— `PROCESS-NAME,localsend` / `DST-PORT,53317` / LAN 网段 / 组播 → `DIRECT`,
  绝不进代理组。

保存后**重新激活订阅**,再 `ip route get 224.0.0.167` 应从 TUN 网卡变回物理网卡。

> **保底退路:** 若 `route-exclude-address` 在 gvisor 栈下没能救回组播,直接在 LocalSend 里
> **手动收藏对端 IP**(`192.168.x.x`)。单播传输本就走物理网卡直连,手填 IP 完全绕过发现,必通。
>
> 局域网还传不了,就查两端防火墙有没有放行 `53317` 的 **TCP + UDP**,以及路由器有没有开
> 「AP 隔离 / 客户端隔离」。

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
2. 加规则,两条路:
   - **覆写脚本(推荐)** —— FlClash ≥ 0.8.85 支持,写法与 Clash Verge Rev 的全局扩展脚本
     基本一致,可与桌面共用一套思路。细节与跨设备同步方案见 [flclash-notes.md](flclash-notes.md)。
   - **订阅 → 覆写**(向导式表单,非手写 YAML):
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

**按需运行(按 WiFi SSID 自动挂起)** —— 配置 → 高级 → 按需运行。把家里的 WiFi SSID 加进
「排除 SSIDs」,回家连上该 WiFi 时 FlClash 自动挂起、交给旁路由,出门自动恢复;正好自动化了
「不要叠加两层接管」。需要**定位权限**(读 SSID)和**忽略电池优化**。机制细节见
[flclash-notes.md](flclash-notes.md)。

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
   ⚠️ 注意代理组的**选择链**:`OpenAI → 主组 → Auto → 🇭🇰 香港` 这种链路,规则命中了
   也会落到香港。逐级点开确认最终落地节点。
2. **第三方登录不是代理开关问题** —— 使用 Google/Microsoft/Apple 注册的账号应继续用
   原方式登录,不能靠「忘记密码」改成邮箱密码。遇到登录问题按
   [OpenAI 官方排错说明](https://help.openai.com/en/articles/7426629)处理。
