#!/usr/bin/env bash
# =============================================================
# 打包离线资源（在【有模型的联网 Linux 机器】上运行）
# 与 pack-offline-assets.ps1 等价，产物为 offline-assets.tar.gz
#
# 用法：在项目根目录执行
#   bash scripts/pack-offline-assets.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
echo "项目根目录: $ROOT"

# 需要打包的路径（相对项目根，保持 backend/ 前缀）。
# nltk_data 只取代码实际用到的资源(zip)，避免把 ~780MB 全量打进去。
items=(
  "backend/app/service/core/rag/res/deepdoc"
  "backend/app/service/core/rag/res/huqie.txt.trie"
  "backend/app/service/core/rag/res/huqie.txt"
  "backend/nltk_data/corpora/wordnet.zip"
  "backend/nltk_data/corpora/omw-1.4.zip"
  "backend/nltk_data/corpora/stopwords.zip"
  "backend/nltk_data/corpora/words.zip"
  "backend/nltk_data/tokenizers/punkt.zip"
  "backend/nltk_data/tokenizers/punkt_tab.zip"
  "backend/nltk_data/taggers/averaged_perceptron_tagger.zip"
  "backend/nltk_data/taggers/averaged_perceptron_tagger_eng.zip"
  "backend/nltk_data/taggers/universal_tagset.zip"
)


# 校验齐全
missing=0
for it in "${items[@]}"; do
  if [ ! -e "$ROOT/$it" ]; then
    echo "  ✗ 缺失: $it"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "❌ 资源缺失，请先在联网机器上跑一次文档解析以自动下载模型" >&2
  exit 1
fi

OUT="$ROOT/offline-assets.tar.gz"
rm -f "$OUT"
echo "正在压缩到 $OUT ..."
tar -czf "$OUT" "${items[@]}"

SIZE=$(du -h "$OUT" | cut -f1)
echo ""
echo "✅ 打包完成: offline-assets.tar.gz ($SIZE)"
echo "下一步：拷到离线服务器项目根目录，执行 bash scripts/restore-offline-assets.sh"
