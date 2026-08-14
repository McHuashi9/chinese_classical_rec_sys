#!/usr/bin/env python3
"""Dart 覆盖率汇总（读 flutter test --coverage 生成的 lcov.info，只出报告不设门槛）
CI 中存在 $GITHUB_STEP_SUMMARY 时，把覆盖率数字同时写进 step summary
（workflow run 页面该步骤的 Summary 折叠区直接可见）；本地跑不受影响"""
import os
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'coverage/lcov.info'

files = {}
cur = None
for line in open(path):
    line = line.strip()
    if line.startswith('SF:'):
        cur = line[3:]
        files[cur] = [0, 0]
    elif line.startswith('LF:'):
        files[cur][0] = int(line[3:])
    elif line.startswith('LH:'):
        files[cur][1] = int(line[3:])

tot = sum(f[0] for f in files.values())
cov = sum(f[1] for f in files.values())


def emit(lines):
    for s in lines:
        print(s)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')


if tot == 0:
    emit(["Dart 行覆盖率: 无数据（lcov 为空，先跑 flutter test --coverage）"])
    sys.exit(1)
pct = cov / tot * 100
lines = [f"Dart 行覆盖率: {cov}/{tot} ({pct:.1f}%)"]
lines += [f"  {name:55s} {c / max(t, 1) * 100:5.1f}%  ({c}/{t})"
          for name, (t, c) in sorted(files.items(), key=lambda r: -r[1][1] / max(r[1][0], 1))]
emit(lines)