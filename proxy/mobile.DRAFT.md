# 📱 移动端选择性代理(草稿 / WIP)

> **🚧 状态:草稿,未完成。** Android 侧代理路由已验证可用;ChatGPT 登录还有一个
> 与代理无关的 Google 登录问题待确认;iOS 侧尚未实测。验证通过后再整理进
> [`README.md`](README.md) 正文。
>
> 占位符同正文:`<PROXY_GROUP>` = 你订阅里的主代理组名。

## 核心认知:手机上没有"独立 TUN 开关"是正常的

桌面 Clash 是"系统代理 / TUN"二选一;**手机端(Android VpnService、iOS Network
Extension)本身就以 VPN 形式运行——你点"启动"那一下就等于桌面的 TUN**,流量已被透明
接管。所以找不到 TUN 开关不是问题。FlClash 里那个 "TUN 模式" 开关是给游戏/命令行/更多
系统级流量用的,日常 App(含 ChatGPT)不用开。

目标同桌面:**指定 App 强制走代理,其余按规则分流**。两平台认 App 的机制不同:

| 平台 | 客户端 | 按 App 匹配 | 用什么规则 |
|---|---|---|---|
| Android | FlClash / Clash Meta | ✅ 按**包名** | `PROCESS-NAME`(同桌面) |
| iOS | Shadowrocket | ❌ iOS 不暴露 App 身份 | 只能按**域名** |

---

## 一、Android(FlClash)— ✅ 代理路由已验证

1. 出站模式选 **规则**,启动 VPN(这就是 TUN)。**TUN 模式开关不用开**。
2. 进**订阅 → 覆写**,启用覆写。FlClash 是**向导式表单**(不是手写 YAML):
   - 规则名称 → `PROCESS-NAME`(**别选** `PROCESS-PATH` / `PROCESS-NAME-REGEX`)
   - 匹配值 → 安卓**包名**,如 `com.openai.chatgpt`(纯包名,无引号空格)
   - 策略 → `<PROXY_GROUP>`
   - 等价于一条 `PROCESS-NAME,com.openai.chatgpt,<PROXY_GROUP>`
3. 保存后**回订阅页重新激活一次**配置。
4. 其它 App 自动按订阅规则分流。

**应用访问控制(分应用代理)三种模式,别设错:**
- 关闭 → 所有 App 都进 VPN(配合规则模式,这是**最终想要的状态**)。
- 白名单 → **只有**勾选的 App 进 VPN,其余完全不代理(适合**隔离测试单个 App**,不是最终态)。
- 黑名单 → 勾选的 App **不**进 VPN,其余都进(适合排除银行/国内 App)。

**验证结果(已确认):** FlClash「连接」页显示
`auth.openai.com → com.openai.chatgpt → 🇺🇸 United States 01 → <PROXY_GROUP>`,
进程规则命中、走了正确地区节点。**代理这部分跑通了。**

---

## 二、iOS(Shadowrocket)— ⏳ 未实测

iOS 拿不到 App 身份,不能"让某个 App 走全局",改成**把 ChatGPT 的域名指到代理**,效果一样:

1. 全局路由改成 **配置 / Config**(规则模式),**不要用 全局 / Proxy**。
2. 加域名规则,或直接导入社区维护的 OpenAI 规则集(自动更新域名):
   ```
   https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Shadowrocket/OpenAI/OpenAI.list
   ```
   手动版关键几条:
   ```
   DOMAIN-KEYWORD,openai,<PROXY_GROUP>
   DOMAIN-SUFFIX,chatgpt.com,<PROXY_GROUP>
   DOMAIN-SUFFIX,oaistatic.com,<PROXY_GROUP>
   DOMAIN-SUFFIX,oaiusercontent.com,<PROXY_GROUP>
   ```
3. 其它流量继续按订阅规则。

---

## ⚠️ 两个共同的坑

### 1. 节点地区 — OpenAI 封香港/大陆
给 ChatGPT 用的节点必须是**美 / 日 / 新 / 台 / 英**等支持地区。别用可能飘到香港的 `Auto`,
否则走了代理也报 `unsupported_country`。

### 2. ChatGPT 的 "Continue with Google" 登录失败(与代理无关)
现象:能弹出登录窗口,但报
`出错了。请确保你的设备安装了最新版本的 Google Play Store …(-9)`。
这是 **Google 登录 / Play 服务凭据(Play Integrity)** 的错,不是代理问题
(走的是 `com.google.android.gms`)。

**绕过办法:别用 Google 登录,改用邮箱 + 密码登录**(完全不碰 Play 服务)。
账号若只用 Google 注册过,先在登录页"忘记密码"给该邮箱设个密码再登。
备选:把 `com.google.android.gms` 排除出代理走直连,并更新 Play 服务——但邮箱登录更省事。

---

## TODO(完成后晋升到正文)

- [ ] 确认邮箱登录能正常进入 ChatGPT 对话(验证 Android 整套跑通)
- [ ] 把应用访问控制从"白名单"调回最终态(关闭,或黑名单只排除银行/国内 App)
- [ ] 实测 iOS / Shadowrocket 一路(Config 模式 + OpenAI 规则集)
- [ ] 三端(桌面/Android/iOS)都通过后,整理进 `README.md` 正文的"移动端"章节
