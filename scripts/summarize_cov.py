#!/usr/bin/env python3
"""Dart 覆盖率汇总（读 flutter test --coverage 生成的 lcov.info，只出报告不设门槛）"""
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
if tot == 0:
    print("Dart 行覆盖率: 无数据（lcov 为空，先跑 flutter test --coverage）")
    sys.exit(1)
print(f"Dart 行覆盖率: {cov}/{tot} ({cov/tot*100:.1f}%)")
for name, (t, c) in sorted(files.items(), key=lambda r: -r[1][1] / max(r[1][0], 1)):
    pct = c / max(t, 1) * 100
    print(f"  {name:55s} {pct:5.1f}%  ({c}/{t})")