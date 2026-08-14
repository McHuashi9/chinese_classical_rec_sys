#!/usr/bin/env bash
# C++ 覆盖率报告（只出报告，不设门槛）
# 用法：./scripts/test_coverage_cpp.sh [out_dir]   # 默认 build-cov/
# 依赖：pip install gcovr（venv 内已装）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build-cov}"

cmake -B "$OUT" -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="--coverage -O0" -DCMAKE_EXE_LINKER_FLAGS="--coverage" >/dev/null
cmake --build "$OUT" --target run_tests -j"$(nproc)" >/dev/null

# 测试资产（test_classical.db）随 run_tests 拷贝，覆盖率运行需真跑一遍
"$OUT/tests/run_tests" >/dev/null 2>&1

mkdir -p "$OUT/coverage"
gcovr -r "$ROOT" \
  --exclude 'third_party/' \
  --exclude 'tests/' \
  --exclude 'bridge/' \
  --exclude 'build.*/' \
  --json -o "$OUT/coverage/coverage.json" >/dev/null

# JSON 汇总 + HTML 报告
# CI 中存在 $GITHUB_STEP_SUMMARY 时，把覆盖率数字同时写进 step summary
# （workflow run 页面该步骤的 Summary 折叠区直接可见，不用翻日志）；本地跑不受影响
python3 - "$OUT/coverage/coverage.json" <<'EOF'
import json, os, sys
data = json.load(open(sys.argv[1]))
rows = []
for f in data['files']:
    lines = f['lines']
    total = len(lines)
    covered = sum(1 for l in lines if l['count'] > 0)
    rows.append((f['file'], covered, total))
sum_total = sum(r[2] for r in rows)
sum_cov = sum(r[1] for r in rows)
pct = sum_cov / sum_total * 100 if sum_total else 0.0
print(f"C++ 行覆盖率: {sum_cov}/{sum_total} ({pct:.1f}%)")
for name, cov, tot in sorted(rows, key=lambda r: -r[1]/max(r[2], 1)):
    p = cov/max(tot, 1)*100
    print(f"  {name:60s} {p:5.1f}%  ({cov}/{tot})")
summary = os.environ.get('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a', encoding='utf-8') as f:
        f.write("## C++ 行覆盖率\n\n```text\n")
        f.write(f"C++ 行覆盖率: {sum_cov}/{sum_total} ({pct:.1f}%)\n")
        for name, cov, tot in sorted(rows, key=lambda r: -r[1]/max(r[2], 1)):
            f.write(f"  {name:60s} {cov/max(tot, 1)*100:5.1f}%  ({cov}/{tot})\n")
        f.write("```\n")
EOF
if ! gcovr -r "$ROOT" \
  --exclude 'third_party/' \
  --exclude 'tests/' \
  --exclude 'bridge/' \
  --exclude 'build.*/' \
  --html --html-details -o "$OUT/coverage/index.html" >/dev/null 2>&1; then
  echo "警告: HTML 报告生成失败（JSON 汇总仍有效），不阻断"
else
  echo "HTML 报告: $OUT/coverage/index.html"
fi
