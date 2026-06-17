# sound-on-push 🎺

`git push` 成功时播一段凯旋小号曲。基于 Claude Code 的 **PostToolUse / Bash 钩子**——
每个跑过的 Bash 命令钩子都看一眼,只有「是 push」且「没报错」才出声。

## 装它

```bash
./install.sh sound-on-push
```

装完开个新 session(或 `/resume`)就生效。自带音源,跨机器一致。

## 什么时候响

钩子在运行时读自己的 stdin JSON 来判断:

| 情况 | 响? |
|------|------|
| 命令含 `git push`,且输出无报错(含 `Everything up-to-date`) | ✅ 🎺 |
| push 失败(`rejected` / `fatal:` / `failed to push` / `permission denied` / `authentication failed` / `could not read`) | ❌ 不庆祝失败 |
| 不是 push 命令 | ❌ |

`async: true`,4 秒曲子不挡活儿。

## 注意

- 对**任何** `git push` 都会响,不分是谁触发的。
- 播放器回退:`mpv → ffplay → mpg123`(mp3 解不了的 `paplay` 故意跳过);
  Windows 没有这些时退化成 PowerShell `[console]::beep()`。
- 想临时关 / 查看:session 里敲 `/hooks`。

## 自带文件

- `victory-fanfare.mp3` → 装到 `~/.claude/sounds/push-done.mp3`
