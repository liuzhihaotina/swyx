#!/usr/bin/env bash
# =============================================================
# 在【离线服务器】上解开离线资源包（Linux）
#
# 前提：已 git clone 本仓库；已把 offline-assets.zip（或 .tar.gz）
#       拷到项目根目录。
#
# 作用：把 DeepDOC 模型 / huqie 词典 / nltk_data 还原到正确位置，
#       让离线机器无需联网即可解析文档。
#
# 用法：在项目根目录执行
#   bash scripts/restore-offline-assets.sh
# =============================================================
set -euo pipefail

# 定位项目根目录（脚本所在目录的上一级）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
echo "项目根目录: $ROOT"

# 找到资源包（优先 zip，其次 tar.gz）
PKG=""
if [ -f "offline-assets.zip" ]; then
  PKG="offline-assets.zip"
elif [ -f "offline-assets.tar.gz" ]; then
  PKG="offline-assets.tar.gz"
else
  echo "❌ 未找到 offline-assets.zip 或 offline-assets.tar.gz，请先拷到项目根目录" >&2
  exit 1
fi
echo "使用资源包: $PKG"

# 解压到项目根目录（包内路径以 backend/ 开头，会原样覆盖到正确位置）
case "$PKG" in
  *.zip)
    command -v unzip >/dev/null 2>&1 || { echo "❌ 缺少 unzip，请先安装：sudo apt-get install -y unzip" >&2; exit 1; }
    unzip -o "$PKG" -d "$ROOT" >/dev/null
    ;;
  *.tar.gz)
    tar -xzf "$PKG" -C "$ROOT"
    ;;
esac

# 校验关键文件是否就位
DEEPDOC="backend/app/service/core/rag/res/deepdoc"
need=(
  "$DEEPDOC/det.onnx"
  "$DEEPDOC/rec.onnx"
  "$DEEPDOC/layout.onnx"
  "$DEEPDOC/tsr.onnx"
  "$DEEPDOC/updown_concat_xgb.model"
  "backend/app/service/core/rag/res/huqie.txt.trie"
  "backend/nltk_data"
)
missing=0
for f in "${need[@]}"; do
  if [ ! -e "$ROOT/$f" ]; then
    echo "  ✗ 缺失: $f"
    missing=1
  else
    echo "  ✓ $f"
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "❌ 部分资源缺失，请检查资源包是否完整" >&2
  exit 1
fi

echo ""
echo "✅ 离线资源已就位，可离线解析文档。"
echo "提示：容器已通过 volume 挂载 nltk_data；模型在镜像构建的代码目录内，"
echo "      如果后端已在运行，重启一次后端容器即可生效：docker compose restart swxy_api"
