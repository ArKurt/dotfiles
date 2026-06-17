# notify-sound

Claude **停下来等你**的时候播放一段提示音 —— 等你做选择、等输入、要权限时,
不用一直盯着屏幕,听到「表,来救我!」就知道该回来了 😄

通过 Claude Code 的 **Notification 钩子**实现(Claude 需要你注意时触发)。
音频文件 `help-me.mp3` **随 repo 一起打包**,所以换机器也自带音源、可复现。

## 安装

```bash
./install.sh
```

它会:

1. 把 `help-me.mp3` 拷到 `~/.claude/notify-help-me.mp3`;
2. 把 Notification 钩子设为播放它,**并顶掉**任何已有的提示音钩子
   (比如旧的 `window-attention.oga`)——所以装上即「替换」。

幂等:重复跑不会叠音。除提示音类的 Notification 钩子外,其它键一律不动。

## 依赖

- `jq`(必需)
- 一个能放 mp3 的播放器,按 `mpv → ffplay → mpg123` 顺序尝试,装了任一即可。
  (`paplay` 不能解 mp3,故这里不用它。)命令带 `|| true`,缺播放器也不会让回合报错。

## 换成自己的音

把本目录的 `help-me.mp3` 换成你的文件(保持同名),重跑 `./install.sh` 即可。
非 Linux 平台改 `install.sh` 里的 `SOUND_CMD`(如 macOS 用 `afplay`)。
