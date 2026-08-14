#!/usr/bin/env bash
# 题库可复现性检查：同一环境连跑两次 generate_questions.py --json，比对 questions.json
# 哈希；并校验重新生成结果与现有产物一致（防随机流漂移/掉题，前科：4770→4769 swap_rng）。
#
# 用法: bash scripts/project/check_questions_reproducible.sh [--expect-count N]
# 依赖: venv（numpy + pypinyin——换质模式；缺失时生成器退纯本字池，检查不代表生产模式）
# 退出码: 0 = 可复现；1 = 漂移/与现有产物不一致/依赖缺失
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$ROOT/scripts/project/generate_questions.py"
QJSON="$ROOT/build/data/questions.json"
EXPECT_COUNT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --expect-count)
      EXPECT_COUNT="$2"
      shift 2
      ;;
    *)
      echo "Error: 未知参数 $1" >&2
      exit 1
      ;;
  esac
done

if ! python3 -c "import numpy, pypinyin" 2>/dev/null; then
  echo "Error: 需要 numpy 与 pypinyin（换质模式），先激活 venv/ 再跑本检查" >&2
  exit 1
fi

# 现有产物哈希（CI 中 build/ 不入库、不存在则为空，只做两次比对）
PREV=""
if [ -f "$QJSON" ]; then
  PREV="$(sha256sum "$QJSON" | cut -d' ' -f1)"
fi

echo "[repro] 第一次生成..."
python3 "$GEN" --json >/dev/null
H1="$(sha256sum "$QJSON" | cut -d' ' -f1)"
if [ -n "$PREV" ] && [ "$PREV" != "$H1" ]; then
  echo "FAIL: 重新生成与现有 build/data/questions.json 不一致（生成器/语料与发布产物漂移）" >&2
  echo "  现有产物: $PREV" >&2
  echo "  重新生成: $H1" >&2
  echo "  请重新执行 generate_questions.py --json → init_data.py → gen_db_version.sh 后再发布" >&2
  exit 1
fi

echo "[repro] 第二次生成..."
python3 "$GEN" --json >/dev/null
H2="$(sha256sum "$QJSON" | cut -d' ' -f1)"
if [ "$H1" != "$H2" ]; then
  echo "FAIL: 两次生成 questions.json 不一致（随机流漂移）" >&2
  echo "  第一次: $H1" >&2
  echo "  第二次: $H2" >&2
  exit 1
fi

COUNT="$(python3 -c "import json; print(len(json.load(open('$QJSON'))))")"
if [ -n "$EXPECT_COUNT" ] && [ "$COUNT" != "$EXPECT_COUNT" ]; then
  echo "FAIL: 题数 $COUNT != 期望 $EXPECT_COUNT（掉题/增题）" >&2
  exit 1
fi
echo "OK: 两次生成一致 sha256=$H1（$COUNT 题）"
