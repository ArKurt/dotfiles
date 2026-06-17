# statusline-context

Claude Code 状态栏:实时上下文进度条 + 80% 越界提示音。

![示例] `ctx ████████░░░░░░░░░░░░ 41% 210k/1000k ⎇ main Opus 4.8`

读取 Claude Code 喂给 statusLine 的 stdin JSON(`context_window.*`),渲染:

- **20 格进度条**,按区间变色:绿 `<60%` / 黄 `60–79%` / 红 `≥80%`
- **token 计数**`已用k/窗口k`(如 `210k/1000k`)
- **越界标记** `⚠200k+`(仅在窗口本身 ≈200k 时显示;1M 模型下自动抑制)
- **分支 + 模型名**
- 跨越 80% 时**一次性**播放提示音(同一 session 不重复)

## 安装

```bash
./install.sh
```

幂等:把脚本拷到 `~/.claude/statusline-context.sh`,并用 jq 把 `statusLine` **合并**进
`~/.claude/settings.json`——不会动你已有的 hooks / permissions 等键。

## 依赖

- `jq`(必需):`sudo pacman -S jq` (Linux) 或 `winget install jq` (Windows)
- `paplay` + freedesktop 音效(可选,仅提示音):Arch 上由 `libpulse` / PipeWire 提供。
  Windows 上自动使用 PowerShell `[console]::beep()` 兜底。缺失只是没声音,进度条照常工作。

## 自定义

- **关掉提示音**:删掉脚本里 `paplay ...` 那一行(或整个 80% alarm 块)。
- **换音效路径**(非 Arch / macOS):把 `paplay /usr/share/...oga` 换成
  你系统的播放命令,如 macOS 的 `afplay /System/Library/Sounds/Sosumi.aiff`。
- **进度条格数**:改脚本里的 `cells=20`。
