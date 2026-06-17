# dotfiles

个人工具的云端中转站 —— 小而有用的配置 / 脚本,在多台机器间一处维护、随取随用。

每个工具是一个自带 `install.sh` 的目录,安装器都**幂等**(可重复跑)、**不破坏**已有配置。

## 用法

新机器上:

```bash
git clone git@github.com:ArKurt/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # 列出所有可用工具
./install.sh <tool>     # 安装某个
./install.sh all        # 全装
```

## 工具清单

| 工具 | 说明 |
|------|------|
| [`claude/statusline-context`](claude/statusline-context/) | Claude Code 状态栏:实时上下文进度条 + 80% 提示音 |

## 加新工具

1. 建目录(如 `claude/my-tool/`),放进脚本和一个可执行的 `install.sh`。
2. 安装器约定:幂等、用 `jq` 合并而非覆盖配置文件、缺依赖时清晰报错。
3. 在上表登记一行。

顶层 `install.sh` 会自动发现任何 `*/install.sh`,无需改 dispatcher。

## 约定

- 目标平台:Arch Linux(其他平台多数也能跑;音效等平台相关项在各工具 README 注明)。
- 安装器只新增 / 合并,绝不盲目覆盖用户已有的 hooks、permissions 等。
