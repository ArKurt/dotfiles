# selective-proxy 🧦

给编码 Agent / 终端 CLI 提供可控代理。既支持「本机 Clash 按进程分流」,也支持
「网络已经由旁路由透明代理、本机 Clash 只作临时兜底」。

> 本文把具体的 Clash 客户端名和订阅/代理组名都隐去了。用的时候按下面的占位符替换:
> - `<PROXY_GROUP>` —— 你订阅里那个能切节点的主代理组名(在客户端「代理」页看标题)。
> - `<US_GROUP>` —— 需要美区落地的组(codex/claude 等)。
> - `<MIXED_PORT>` —— 你客户端的混合端口(常见默认 `7890`,本仓库示例脚本用 `7897`)。
>
> 客户端需使用 **Mihomo / Clash Meta 内核**,并支持 TUN 模式与进程规则。
> 只认端口不认客户端——Verge Rev / FlClash / FlClashX 都通用,把 mixed-port 对齐即可。

## 先选部署模式(互斥)

| 模式 | 本机系统代理 | 本机 TUN | Shell 环境变量 | 适用场景 |
|---|---:|---:|---:|---|
| **A · 本机按进程分流** | 关 | 开 | 默认关、必要时兜底 | 设备直接接普通网关,需要本机 Clash 决定哪些进程代理 |
| **B · 旁路由主路径** | 关 | 关 | 默认关、仅故障/A-B 测试时 `proxy` | 默认网关已经是 OpenWrt/ImmortalWrt 等透明代理旁路由 |

> ⚠️ **两种模式不要叠加。** 同时开系统代理、TUN、常驻 `*PROXY` 和旁路由透明代理,会让真实
> 路径难以判断,还会让长驻进程硬依赖本机 Clash——关掉就立即断联,不会自动回退旁路由。

## 安装 shell helpers

```bash
./install.sh proxy                    # 自动识别 zsh / bash / fish,默认端口 7897
CLASH_PORT=7890 ./install.sh proxy    # 跟随你客户端的端口
source ~/.zshrc                       # 或直接开新终端

proxy          # 端口存在才开启；避免 Clash 没启动时把终端变成断网状态
unproxy        # 关闭本 shell 会话的代理变量
proxy_status   # 查看环境变量和本地端口状态
```

默认**不开**环境变量:模式 A 由 TUN + 进程规则工作,模式 B 直接交给旁路由。
环境变量只是进程规则覆盖不到时的显式兜底。

两个可选开关(平时都不需要):

```bash
PROXY_DEFAULT_ON=1 ./install.sh proxy   # 每个新 shell 自动开代理变量（慎用，见 reference）
WITH_GITPUSH=1 ./install.sh proxy       # 装 gitpush，走 socks 隧道推送（TUN 下 SSH 上行卡死时用）
```

## 客户端配置

### 模式 A

1. **关闭「系统代理」** —— TUN 接管后不需要它,留着可能重复代理。
2. **打开 TUN 模式**(虚拟网卡)—— 首次可能要安装服务 / 授权。
3. **代理模式选「规则」** —— 只有规则模式下 `PROCESS-NAME` 才生效。
4. **加进程优先规则** —— 别直接改订阅(更新会被覆盖),用客户端的**扩展脚本**功能把规则插到
   订阅规则之前。**完整脚本模板见 [reference.md](reference.md) 的「模式 A:完整规则模板」一节。**

### 模式 B

1. 本机「系统代理」关、TUN 关。
2. Shell 保持 `unproxy`；**重启**所有曾继承 `127.0.0.1:<MIXED_PORT>` 的 GUI/Agent。
3. 用清空代理变量后的直连测试验收旁路由,不要拿旧进程作证。

需要临时强制某个会话经本机 Clash、或对比两条代理路径时才执行 `proxy`；完成后 `unproxy`。

## 验证

打开客户端「**连接**」页,操作一下目标工具,确认那条连接的**进程列**和你写的规则对得上、
**规则/链路列**命中了你的 `PROCESS-NAME` 规则。国内站点应走 `DIRECT`。

```bash
proxy_status
curl -s https://api.ipify.org; echo   # 出口 IP 应是代理节点的
```

> **别信生成的 yaml 文本,要问内核。** 规则可能因为写错了覆写方式而静默失效,
> 却被兜底规则接住、"看起来正常"。用外部控制 API 看真正生效的规则——
> 见 [reference.md](reference.md) 的「规则必须放全局扩展脚本」一节。

## 延伸阅读

- **[reference.md](reference.md)** —— 参考手册:原理、完整规则模板、各平台进程名差异、
  Windows PowerShell、排错、局域网工具直连(LocalSend)、移动端(Android / iOS)配置。
- **[flclash-notes.md](flclash-notes.md)** —— FlClash 0.8.94 内部机制核验:覆写脚本约定、
  WebDAV 同步语义(**恢复选项选错会覆盖手机设置**)、跨设备差异化方案、按需运行、踩坑记录。
