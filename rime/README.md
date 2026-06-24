# rime —— 雾凇拼音 + 万象语法模型 🀄

我的 RIME 输入法配置:**雾凇拼音(rime-ice)** 打底,挂上 **万象语法模型(wanxiang grammar)**,
让「一口气打整句、中间不分词」也能首选就对。

## 装这个

```bash
./install.sh        # 在 dotfiles 根目录:./install.sh rime
```

脚本会:

1. 把 `default.custom.yaml` / `rime_ice.custom.yaml` 部署到 `~/.local/share/fcitx5/rime/`
   (已存在且不同 → 先备份 `.bak` 再写,绝不静默覆盖)
2. 下载万象语法模型 `wanxiang-lts-zh-hans.gram`(**~401MB,不入 git,首次自动拉取**)
3. 用 `rime_deployer` 重新部署,并重载 fcitx5

幂等:重跑会跳过相同配置、不重下模型。

## 为什么模型不进 git ⚠️

`wanxiang-lts-zh-hans.gram` 有 **401MB**,远超 GitHub 单文件 100MB 上限,且大二进制会把仓库撑爆。
所以仓库里只放**配置**,模型由 `install.sh` 从[官方 release](https://github.com/amzxyz/RIME-LMDG/releases/tag/LTS) 现拉。

## 依赖

- `fcitx5-rime`、雾凇方案源在 `/usr/share/rime-data`(`rime_ice.schema.yaml` 等)
- `librime`(提供 `rime_deployer`)、`curl`

缺啥脚本会清楚报给你 + 给出 `pacman` 安装命令。

## 文件说明

| 文件 | 作用 |
|------|------|
| `default.custom.yaml` | 方案列表(雾凇/小狼毫简体/flypy 双拼/注音)、Caps 切换、候选 6 个/页 |
| `rime_ice.custom.yaml` | 给雾凇挂万象语法模型:`grammar/language: wanxiang-lts-zh-hans` |

## 踩过的坑 🕳️

- **`fcitx5-remote -r` 只重载、不触发完整部署**。改完配置必须用
  `rime_deployer --build <用户目录> /usr/share/rime-data`(或托盘「重新部署」)才真正重建。
- 万象模型只在**整句长输入**时发挥作用,打单字/短词看不出区别 —— 验证一定要测长句。
- `schema_list` 里若引用了 `/usr/share/rime-data` 缺失的方案(如未装源的 `wubi86`),
  部署会报 `missing input schema` 并返回非零,但**不影响**已部署的雾凇/万象。

## 更新万象模型 🔄

```bash
rm ~/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram
./install.sh        # 重新拉取最新模型并部署
```

## Windows 📎

Windows 用的是**小狼毫(Weasel)**而非 fcitx5,`install.sh` 会检测到并提示手动:

1. 把两个 `*.custom.yaml` 放进 `%APPDATA%\Rime\`
2. 下载 `wanxiang-lts-zh-hans.gram` 放进同一目录
3. 右键托盘 → 重新部署
