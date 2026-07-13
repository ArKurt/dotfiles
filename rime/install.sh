#!/usr/bin/env bash
# Installer: 雾凇拼音(rime-ice) + 万象语法模型(wanxiang grammar)的 RIME 配置。
#
# 干什么:
#   1. 把 default.custom.yaml / rime_ice.custom.yaml 部署到 fcitx5 的 RIME 用户目录
#   2. 校验万象语法模型(由 AUR 包 rime-wanxiang-gram-zh-hans 提供,随 yay/paru -Syu 更新)
#   3. 用 rime_deployer 重新部署,并重载 fcitx5
#
# 幂等 + 只加不砸:配置相同则跳过;不同则先备份 .bak 再写;模型走 AUR、不由本脚本下。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GRAM_NAME="wanxiang-lts-zh-hans.gram"
GRAM_URL="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/${GRAM_NAME}"
GRAM_MIN_BYTES=$((300 * 1024 * 1024))   # 完整约 401MB;低于此判定为下载不全

is_windows() { case "${OS:-}${OSTYPE:-}" in *[Ww]indows*|*msys*|*cygwin*) return 0;; *) return 1;; esac; }

if is_windows; then
  echo "ℹ Windows 用的是小狼毫(Weasel),不是 fcitx5,部署机制不同。"
  echo "  请手动操作(详见 README.md):"
  echo "    1. 把 default.custom.yaml / rime_ice.custom.yaml 放进 %APPDATA%\\Rime\\"
  echo "    2. 下载 $GRAM_NAME 放进同一目录: $GRAM_URL"
  echo "    3. 右键托盘 → 重新部署"
  exit 0
fi

RIME_DIR="$HOME/.local/share/fcitx5/rime"
SHARED_DIR="/usr/share/rime-data"

# ── 依赖检查 ──────────────────────────────────────────────
miss=0
command -v curl          >/dev/null 2>&1 || { echo "✗ 缺 curl:        sudo pacman -S curl" >&2; miss=1; }
command -v rime_deployer  >/dev/null 2>&1 || { echo "✗ 缺 rime_deployer(librime):  sudo pacman -S librime" >&2; miss=1; }
[ -d "$SHARED_DIR" ] || { echo "✗ 没找到 $SHARED_DIR —— 先装雾凇方案到共享目录,或装 fcitx5-rime + rime-ice" >&2; miss=1; }
[ -f "$SHARED_DIR/rime_ice.schema.yaml" ] || { echo "✗ $SHARED_DIR 里没有 rime_ice.schema.yaml —— 雾凇方案源未安装" >&2; miss=1; }
[ "$miss" -eq 0 ] || exit 1

mkdir -p "$RIME_DIR"

# ── 部署配置文件(幂等 + 备份不覆盖)──────────────────────
deploy_file() {
  local name="$1" src="$HERE/$1" dst="$RIME_DIR/$1"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "✓ $name 已是最新,跳过"
  elif [ -f "$dst" ]; then
    cp "$dst" "$dst.bak"
    cp "$src" "$dst"
    echo "✓ $name 已更新(原文件备份为 $name.bak)"
  else
    cp "$src" "$dst"
    echo "✓ $name 已部署"
  fi
}
deploy_file default.custom.yaml
deploy_file rime_ice.custom.yaml

# ── 万象语法模型:走 AUR(官方常规渠道·随 yay/paru -Syu 自动更新)──
# 模型由 AUR 包 rime-wanxiang-gram-zh-hans 提供,装到 /usr/share/rime-data/。
# 不再由本脚本手动下载 —— 手动下的永远不会更新,会一直冻结在初次那版
#(踩过的坑:argamo 模型冻结数周而 arnino 常新)。
SHARED_GRAM="$SHARED_DIR/$GRAM_NAME"
STALE_GRAM="$RIME_DIR/$GRAM_NAME"
# 清掉历史上手动下到用户目录的旧模型(存在则会遮蔽 AUR 共享版,导致永不更新)
if [ -f "$STALE_GRAM" ]; then
  echo "⚠ 用户目录有手动下载的旧模型,会遮蔽 AUR 共享版 —— 删除:"
  rm -v "$STALE_GRAM"
fi
if [ -f "$SHARED_GRAM" ] && [ "$(stat -c%s "$SHARED_GRAM")" -ge "$GRAM_MIN_BYTES" ]; then
  echo "✓ 万象模型已由 AUR 提供($(( $(stat -c%s "$SHARED_GRAM")/1024/1024 ))MB @ $SHARED_DIR·随系统更新)"
else
  echo "✗ 未找到万象模型 —— 请装 AUR 包(官方常规渠道,随 yay/paru -Syu 更新):" >&2
  echo "    yay -S rime-wanxiang-gram-zh-hans" >&2
  echo "  装完重跑本脚本。" >&2
  exit 1
fi

# ── 重新部署 + 重载 ───────────────────────────────────────
# 注意:fcitx5-remote -r 只重载、不触发完整部署,必须用 rime_deployer 强制 build。
echo "⚙ 重新部署 RIME..."
rime_deployer --build "$RIME_DIR" "$SHARED_DIR" >/dev/null 2>&1 \
  && echo "✓ 部署完成" \
  || echo "⚠ 部署返回非零(多半是 schema_list 里有缺失方案,不影响雾凇/万象)"

if command -v fcitx5-remote >/dev/null 2>&1 && pgrep -x fcitx5 >/dev/null 2>&1; then
  fcitx5-remote -r && echo "✓ fcitx5 已重载"
else
  echo "ℹ fcitx5 未运行 —— 启动后即生效"
fi

echo
echo "完成!切到雾凇拼音,打一句长拼音(如 faguangmogubujinjinhuifaguang)验证整句联想是否变准。"
echo "重跑本脚本是安全的(相同配置跳过、模型由 AUR 管·随 yay/paru -Syu 更新)。"
