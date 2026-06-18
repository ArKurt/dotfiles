# dotfiles 🧰

我的私人小工具云端中转站 —— 那些「装一次就离不开」的配置和脚本,集中放一处,
哪台机器想用就 `clone` 下来一键装上。

每个工具都是一个自带 `install.sh` 的小文件夹。安装器都**幂等**(重复跑没事)、
而且**只加不砸**——hooks、permissions 等都是合并追加,绝不覆盖你已有的配置。
(唯一例外:`statusLine` 是单值键而非列表,装 statusline-context 即表示你要用它,
所以会替换原有 statusLine——但会**先把旧命令打印出来**,方便你想恢复时找回。)

## 怎么取用 🚀

到一台新机器上,就两步:

```bash
git clone git@github.com:ArKurt/dotfiles.git ~/dotfiles
cd ~/dotfiles

./install.sh                 # 看看有哪些工具
./install.sh statusline-context   # 装某一个
./install.sh all             # 全都装上
```

装完 Claude Code 相关的工具后,开个新 session(或 `/resume`)就生效啦。

## 工具清单 📦

| 工具 | 说明 | 跨平台 |
|------|------|--------|
| [`claude/statusline-context`](claude/statusline-context/) | Claude Code 状态栏:实时上下文进度条 + 80% 提示音 | Linux ✓ / Windows ✓ |
| [`claude/sound-on-stop`](claude/sound-on-stop/) | Claude Code 每回合结束时「叮」一声(Stop 钩子) | Linux ✓ / Windows ✓(beep) |
| [`claude/notify-sound`](claude/notify-sound/) | Claude 停下来等你时播放提示音(Notification 钩子,自带音源) | Linux ✓ / Windows ⚠️(beep)
| [`claude/sound-on-push`](claude/sound-on-push/) | `git push` 成功时播凯旋小号曲(PostToolUse 钩子,自带音源,失败不响) | Linux ✓ / Windows ⚠️(beep)
| [`proxy`](proxy/) | 选择性代理:只让编码 Agent / 终端走代理,其余按规则分流(Clash TUN + 进程规则 + shell 兜底);移动端同款方案见 proxy 文档 | 桌面 Linux ✓ / Windows ✓ ・ 移动端 Android ✓ / iOS ✓ |

> **关于「自带音源」:** notify-sound / sound-on-push 自带的 `.mp3` 需要系统里有
> `mpv` / `ffplay` / `mpg123` 之一才能播放(Linux 一般装一个即可)。Windows 上若没有
> 这些播放器,会退化成 PowerShell `[console]::beep()` 蜂鸣——**听得到提示,但不是自带音效**。

## 验证过哪些 ✅

搭的时候挨个试过,不是写完就推:

- `./install.sh` 能正确列出工具、按名安装
- **合并不覆盖**:拿一个预置了若干 hooks / 其它键的 `settings.json` 实测,
  装完原有键原样还在,只多出 `statusLine`(或对应工具新增的键)
- 进度条脚本渲染正常:绿(40%)/ 红(85%)、token 计数、分支、模型名都对

## 加新玩意儿 🔧

想塞个新工具进来,三步:

1. 建个目录(比如 `claude/我的工具/`),放进脚本和一个**可执行**的 `install.sh`。
2. 安装器守三条规矩:幂等、用 `jq` **合并**而不是覆盖配置、缺依赖时清清楚楚地报错。
3. 在上面那张表里登记一行。

顶层 `install.sh` 会自动发现任何 `*/install.sh`,所以**不用改 dispatcher**。

## 约定 📋

- 主战场:Arch Linux + Windows。安装器在 Linux/Windows 上自动适配(如提示音:
  Linux 用 `paplay`,Windows 用 PowerShell `[console]::beep()`)。
- 安装器只新增 / 合并,绝不盲目覆盖你已有的 hooks、permissions 等。
