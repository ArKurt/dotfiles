# FlClash 内部机制核验笔记

> **快照:FlClash 0.8.94(AUR `flclash-bin`)· 2026-07-28 核验 · 对照上游源码 `chen08209/FlClash@main`**
>
> 本文记录的是**实现细节**——sqlite 表结构、枚举取值、恢复语义、脚本调用约定。
> 这些**不是公开 API,上游改版即可能失效**。看到与实际不符时,以源码为准并回来更新本文。
> 长青的原理与操作说明在 [reference.md](reference.md) 和 [README.md](README.md),那两份不受版本影响。

---

## 一句话结论

FlClash ≥ 0.8.85 支持覆写脚本,能力对齐 Clash Verge Rev 的全局扩展脚本;
配合 WebDAV 可把「订阅 + 脚本 + 规则」整套同步到手机。但**恢复时的选项选错会覆盖手机的
平台设置**,且**桌面与手机需要各自的 profile**——原因见下。

---

## 架构:FlClash 与 FlClashX 不是一回事

`flclash-bin` 与 `flclashx-bin` 在 Arch 上**互相冲突,不能共存**(需先卸载其一)。
两者数据目录也不同,且 **schema 不兼容,配置不能直接对拷**:

| | FlClash 0.8.94 | FlClashX 0.4.2(分叉) |
|---|---|---|
| 数据目录 | `~/.local/share/com.follow.clash` | `~/.local/share/com.follow.clashx` |
| 订阅存储 | **`database.sqlite`**(Drift) | `shared_preferences.json` 里的 `profiles` 数组 |
| `currentProfileId` | **`int?`** | 字符串 |
| 配置键名 | `appSettingProps` / `davProps` / `proxiesStyleProps` | `appSetting` / `dav` / `proxiesStyle` |

> `pacman -R` 只删程序文件,**不动** `~/.local/share/*` 用户数据,所以换装时订阅不会丢。

### 数据落地位置

```
~/.local/share/com.follow.clash/
├── database.sqlite     profiles / scripts / rules / proxy_groups / profile_rule_mapping
├── shared_preferences.json   flutter.config —— 应用与内核设置
├── profiles/<profileId>.yaml 订阅正文
└── scripts/<scriptId>.js     覆写脚本正文
```

`profiles.script_id` → `scripts.id`;`scripts` 表只存 id/label/时间,**正文在 `scripts/<id>.js` 文件里**。

---

## 覆写脚本

引擎是 **QuickJS**(`flutter_js` + `libquickjs_c_bridge_plugin.so`),ES2020 特性可用
(`Set`、箭头函数、展开运算符实测均正常)。

### ⚠️ 只传一个参数

```dart
// lib/common/javascript.dart
runtime.evaluateAsync('''
  $scriptContent
  main($configJs)      // ← 只有 config，没有 profileName
''');
```

Clash Verge Rev 传 `main(config, profileName)`,**FlClash 只传 `config`**。
写 `function main(config, profileName)` 不会报错,但 `profileName` 恒为 `undefined`——
**不能靠它分支**。

### ⚠️ 脚本内无法判断平台

运行时不注入任何平台标识,传入的 `config` 是订阅正文(两端同步后完全一致)。
所以**做不到「一个脚本自动区分手机/桌面」**。要让两端行为不同,只能靠下面的双 profile 方案。

---

## WebDAV 同步

**不是自动同步**,是手动的「上传 / 下载」两个动作,两端各点一次,共用一个文件名
(路径 `/FlClash/<fileName>`)。

备份包 `backup.zip` 内容(`lib/common/task.dart::_backupTask`):

```
database.sqlite   ← profiles / scripts / rules / proxy_groups
config.json       ← 全部应用与内核设置
profiles/*.yaml   ← 订阅正文
scripts/*.js      ← 覆写脚本正文  ✅ 脚本会跟着同步
```

### ⚠️⚠️ 恢复时必须选「仅恢复配置文件」

恢复有**两个互相独立**的开关,选错会把手机的平台设置冲掉:

**① `RestoreOption`(恢复时当场选)**

| 取值 | 行为 |
|---|---|
| `onlyProfiles` **仅恢复配置文件** ✅ | 只写数据库(订阅/脚本/规则/代理组),**完全不碰应用设置** |
| `all` ⚠️ | 额外覆盖 `patchClashConfig`、`vpnProps`、`windowProps`、`themeProps`、`networkProps`、`davProps`、`hotKeyActions`、`currentProfileId`、`appSettingProps` 等**全部设置** |

跨平台同步(Linux → Android)**必须选 `onlyProfiles`**,否则手机的 **VPN 设置会被桌面的设置覆盖**,
连桌面的窗口尺寸都会写进手机配置。

**② `RestoreStrategy`(常驻设置,默认 `compatible`)**

| 取值 | 对 `profiles` 表 |
|---|---|
| `compatible`(默认)✅ | upsert 合并,保留本机已有 profile |
| `override` | 清空后整表替换 |

注意:无论选哪个,**`scripts` / `rules` / `proxy_groups` 三张表都是整表替换**
(`setAllWithBatch`),只有 `profiles` 受此开关影响。

---

## 跨设备差异化:双 profile 方案

**需求**:桌面 Claude 走美区,手机 Claude 走新加坡,但两端同步同一个备份。

**为什么不能用一个脚本**:见上文——脚本拿不到平台信息,也拿不到 profileName。

**方案**:两个 profile 指向同一订阅 URL,各挂一个脚本。

```
profile 桌面  → script 桌面版（Claude → 🇺🇸）
profile 手机  → script 手机版（Claude → 🇸🇬）
```

**为什么成立**:`onlyProfiles` 恢复时会在写完数据库后**直接 return**,
不会触碰 `currentProfileId`(`lib/providers/action.dart::restore`)。
所以两台设备同步后都拿到全部 profile 和全部脚本,但**各自记住自己选中的那个**,互不干扰。

手机端只需第一次选中手机 profile,之后每次同步都保持不变。

---

## 按需运行(On Demand)

**位置**:配置 → 高级 → 按需运行

**机制**:维护「排除 SSIDs」列表。连上列表内的 WiFi 时自动 `stopListener()` 挂起,
离开后自动 `startListener()` 恢复。官方文案:「连接到被排除SSID的WIFI时,将会自动切换应用运行状态」。

挂起期间**连 app 自身的请求也走直连**(`lib/common/http.dart`:`if (!isStart || suspend) return 'DIRECT'`),
是整体挂起而非部分绕过。

**两个前置权限**,缺一不工作:
1. **定位权限** —— Android/macOS 读 WiFi SSID 必须要
2. **忽略电池优化** —— 官方文案:「为保证后台运行,请关闭本应用的电池优化」

**典型用法**:把家里 WiFi 的 SSID 加进去。家里默认网关是旁路由透明代理(模式 B)时,
手机一回家自动挂起交给旁路由,出门自动恢复自己代理——正好自动化了「不要叠加两层接管」。

---

## 内核:FlClashCore 不是独立 mihomo

| | 身份 |
|---|---|
| `verge-mihomo`(Clash Verge Rev) | 标准 Mihomo Meta,正常 CLI,可命令行独立喂配置 |
| `FlClashCore`(FlClash) | **不是**独立 mihomo。参数被当作 unix socket 路径(喂 `-v` 会 panic `dial unix -v`),只能由 FlClash GUI 经 socket 驱动 |

两者**不通用**。同理,`clash-verge-service.service` 是 **Verge 专属**的特权 helper
(`/usr/lib/flclash/` 下没有对应文件),FlClash 走自己的 `authorizeCore()` 提权,
禁用该服务不影响 FlClash。

> ⚠️ 该 systemd 服务 `enabled` + `Restart=always` 时会**开机直接拉起 `verge-mihomo`**,
> 即使 Verge GUI 里 `enable_auto_launch: false`、且 GUI 从未启动。
> 想彻底不自启需 `systemctl disable clash-verge-service`(代价:Verge 的 TUN 需要时再手动起服务)。

---

## 验证方法:问内核,别信 yaml

开外部控制器(设置里打开,固定 `127.0.0.1:9090`),直接问内核实际生效的规则:

```bash
curl -s --noproxy '*' http://127.0.0.1:9090/rules      # 实际生效的规则(含脚本注入的)
curl -s --noproxy '*' http://127.0.0.1:9090/proxies    # 代理组与当前选择
curl -s --noproxy '*' http://127.0.0.1:9090/configs    # 内核实际配置
```

注意 `external-controller` 在 FlClash 里是**枚举**,只接受 `''`(关)或 `'127.0.0.1:9090'`(开),
不能填任意地址。

**查选择链**尤其重要——规则命中了,落地节点仍可能是错的:

```
OpenAI → SSRDOG → Auto → 🇭🇰 Hong Kong     ← 规则没问题，但落到了香港
```

---

## 踩坑记录

手工改配置时踩过的,都是「照 FlClashX / mihomo 的经验硬套」导致的:

| 坑 | 现象 | 正解 |
|---|---|---|
| `currentProfileId` 填字符串 | **app 静默卡死**,GUI 起不来、内核不启动、日志一行没有 | 必须是 `int` |
| `find-process-mode` 填 `strict` | 静默回退 | FlClash 枚举只有 `{always, off}`,**没有 strict** |
| 以为 flclash / flclashx 可共存 | 安装报冲突 | 必须先卸载其一 |
| 以为能用 `clash://install-config?url=` 深链导入 | 无反应 | 该 scheme **只在 Windows 注册**(`lib/common/window.dart`),Linux 无效 |

经验:FlClash 的配置**用 GUI 改最稳**。手工改 sqlite / shared_preferences 前,
先去源码确认字段类型与枚举取值(`lib/models/`、`lib/enum/enum.dart`),并**先备份数据目录**。
