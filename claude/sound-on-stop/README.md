# sound-on-stop

Claude Code 每回合结束时「叮」一声 —— 跑长任务时不用盯着屏幕,响了就回来看。

通过 Claude Code 的 **Stop 钩子**实现:回合结束触发,异步播放一个提示音。

## 安装

```bash
./install.sh
```

幂等:只在 `~/.claude/settings.json` 的 `hooks.Stop` 里**还没有**这条命令时才追加,
重复跑不会叠出多个音。其它键(statusLine、permissions、别的钩子)一律不动。

## 依赖

- `jq`(必需,用于安全合并)
- `paplay` + freedesktop 音效(Arch 上由 PipeWire / PulseAudio 提供)。
  命令带 `|| true`,所以缺播放器也只是没声音,绝不会让回合报错。

## 自定义

默认音:`/usr/share/sounds/freedesktop/stereo/complete.oga`。
换音或换播放器,改脚本顶部的 `SOUND_CMD` 即可,例如 macOS:

```sh
SOUND_CMD='afplay /System/Library/Sounds/Glass.aiff'
```
