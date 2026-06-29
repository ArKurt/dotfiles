# statusline-context

Claude Code 状态栏:上下文进度条 + 80% 提示音,外加可选的**预算/用量行**与**思考等级**。两行上下对仗,冷暖配色区分。

示例(默认两行):

```
ctx ████████░░░░░░░░░░░░ 42% 84k/200k ⎇ main Opus 4.8 💡high
5h  ███████░░░░░░░░░░░░░ 38% ↺2h14m  │  $0.42 +120/-30
```

读取 Claude Code 喂给 statusLine 的 stdin JSON(`context_window.*` / `cost.*` / `rate_limits.*` / `effort.level`)渲染。**预算/用量数据全部来自 stdin——零额外依赖、不联网、不扫 transcript。**

**行 1 · 上下文核心**(暖色:绿 `<60%` / 黄 `60–79%` / 红 `≥80%`)

- **20 格进度条**,实心填充按区间变色、空心变暗
- **token 计数** `已用k/窗口k`(如 `84k/200k`)
- **越界标记** `⚠200k+`(仅在窗口本身 ≈200k 时显示;1M 模型下自动抑制)
- **分支 + 模型名**
- **思考等级** `💡high`(取 stdin `effort.level`;缺失时回落 `~/.claude/settings.json` 的 `effortLevel`)
- 跨越 80% 时**一次性**播放提示音(同一 session 不重复)

**行 2 · 预算 / 用量**(与行 1 对仗;均可单独开关)

- **5 小时额度用量条** `5h ███░ 38%`——和 ctx 同款 20 格条,但走**冷色(淡紫,256-color 141)**以作区分;后接 `↺2h14m` 重置倒计时
- `│` 分隔后是**会话统计**:成本 `$0.42`、改动行数 `+120/-30`(绿增 / 红删)
- 可选:会话时长 `⏱1h23m`、周用量 `7d 12%`(默认均关)

## 开关 🎛️（环境变量,`=0` 关闭）

| 变量 | 默认 | 作用 |
|------|------|------|
| `CLAUDE_SL_COST` | 开 | 会话成本 + 增/删行数 |
| `CLAUDE_SL_5H` | 开 | 5 小时用量条 + 重置倒计时 |
| `CLAUDE_SL_DURATION` | 关 | 会话时长 `⏱` |
| `CLAUDE_SL_WEEKLY` | 关 | 7 天(周)用量% |
| `CLAUDE_SL_THINKING` | 开 | 当前思考等级 |
| `CLAUDE_SL_THINK_ICON` | 💡 | 思考等级前的图标(可换 `⚡` / `🧠` / …) |
| `CLAUDE_SL_USABLE` | 关 | 上下文% 按 autocompact **可用窗口**算(比裸 % 更诚实) |
| `CLAUDE_CTX_AUTOCOMPACT_PCT` | 8 | 可用模式的预留百分比(官方阈值未公开,近似可调) |
| `CLAUDE_SL_MULTILINE` | 开 | 两行布局;`=0` 合并回单行 |
| `CLAUDE_CTX_WINDOW` | — | 覆盖上下文窗口大小(如代理模型 API 少报时) |

> 改默认值:在 Claude Code 能继承到的 shell profile 里 `export CLAUDE_SL_WEEKLY=1`,或直接改脚本顶部那几行默认。

## 安装

```bash
./install.sh
```

幂等:把脚本拷到 `~/.claude/statusline-context.sh`,并用 jq 把 `statusLine` **合并**进
`~/.claude/settings.json`——不会动你已有的 hooks / permissions 等键。

## 依赖

- `jq`(必需):`sudo pacman -S jq` (Linux) 或 `winget install jq` (Windows)
- `date`(倒计时/时长换算用,coreutils 自带,无需另装)
- `paplay` + freedesktop 音效(可选,仅提示音):Arch 上由 `libpulse` / PipeWire 提供。
  Windows 上自动使用 PowerShell `[console]::beep()` 兜底。缺失只是没声音,进度条照常工作。

## 自定义

- **按需开关功能**:用上面那张表的环境变量,比手改脚本干净。
- **换 5h 条颜色**:改脚本里 `C_COOL` 那行的 256-color 号(`141` 淡紫 → `99` 更深 / `183` 更淡)。
- **换思考图标**:`CLAUDE_SL_THINK_ICON=⚡`(临时)或改脚本默认。
- **关掉提示音**:删掉脚本里 `paplay ...` 那一行(或整个 80% alarm 块)。
- **换音效路径**(非 Arch / macOS):把 `paplay /usr/share/...oga` 换成
  你系统的播放命令,如 macOS 的 `afplay /System/Library/Sounds/Sosumi.aiff`。
- **进度条格数**:改脚本里的 `cells=20`(两条条同步)。
