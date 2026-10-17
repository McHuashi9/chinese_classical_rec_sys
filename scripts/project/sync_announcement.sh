#!/bin/bash
# 从 CHANGELOG.md 的指定版本段同步公告“版本改动”，并更新 announcement.md 的 id。
# 用法: bash scripts/project/sync_announcement.sh <X.Y.Z> [--dry-run]
# 说明: bump_version.sh 会自动调用；若整理 CHANGELOG 后需要重新同步，也可单独执行。
#       --dry-run 只输出 unified diff，不写 announcement.md。
set -euo pipefail

usage() {
  echo "Usage: $0 <version> [--dry-run]"
  echo "Example: $0 1.2.1 --dry-run"
}

VERSION=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Too many arguments" >&2
        usage >&2
        exit 2
      fi
      VERSION="$arg"
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  usage >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
ANNOUNCEMENT="$ROOT/flutter_app/assets/data/announcement.md"

if [ ! -f "$ANNOUNCEMENT" ]; then
  echo "[sync_announcement] flutter_app/assets/data/announcement.md not found, skip"
  exit 0
fi

python3 - "$VERSION" "$CHANGELOG" "$ANNOUNCEMENT" "$DRY_RUN" <<'PY'
import difflib
import os
import re
import sys

version, changelog_path, announcement_path, dry_run_arg = sys.argv[1:5]
dry_run = dry_run_arg == '1'

with open(changelog_path, encoding='utf-8') as f:
    changelog = f.read()

section_pattern = re.compile(
    rf'^## \[{re.escape(version)}\] - .*?(?=^## \[|\Z)',
    re.M | re.S,
)
match = section_pattern.search(changelog)
if not match:
    print(f'[sync_announcement] error: CHANGELOG section [{version}] not found', file=sys.stderr)
    sys.exit(1)

section = match.group(0)
subsections = re.findall(
    r'^### (?:Added|Changed|Fixed)\s*$(.*?)(?=^### |\Z)',
    section,
    re.M | re.S,
)
bullets = []
for body in subsections:
    for line in body.splitlines():
        line = line.strip()
        if line.startswith('- '):
            bullets.append(line[2:].strip())

if not bullets:
    print(f'[sync_announcement] error: no Added/Changed/Fixed bullets found for [{version}]', file=sys.stderr)
    sys.exit(1)

with open(announcement_path, encoding='utf-8') as f:
    announcement_before = f.read()
announcement = announcement_before

# 更新 front matter 中的 id，确保“仅更新后弹出”能识别新版本
announcement = re.sub(
    r'^id:.*$',
    f'id: v{version}-1',
    announcement,
    count=1,
    flags=re.M,
)

marker = '## 版本改动'
changes_body = '\n'.join(f'- {b}' for b in bullets) + '\n'
if marker in announcement:
    head = announcement.split(marker, 1)[0].rstrip()
    announcement = f'{head}\n\n{marker}\n\n{changes_body}'
else:
    announcement = announcement.rstrip() + f'\n\n{marker}\n\n{changes_body}'

# 写盘前先校验生成结果，dry-run 与正式写共用同一套检查。
id_pattern = re.compile(rf'^id:\s*v{re.escape(version)}-1\s*$', re.M)
if not id_pattern.search(announcement):
    print(f'[sync_announcement] error: generated announcement missing id v{version}-1', file=sys.stderr)
    sys.exit(1)
if marker not in announcement:
    print(f'[sync_announcement] error: generated announcement missing {marker}', file=sys.stderr)
    sys.exit(1)

actual_changes = announcement.split(marker, 1)[1].strip()
if actual_changes != changes_body.strip():
    print('[sync_announcement] error: generated announcement 版本改动 differs from CHANGELOG', file=sys.stderr)
    sys.exit(1)

if dry_run:
    diff = list(difflib.unified_diff(
        announcement_before.splitlines(keepends=True),
        announcement.splitlines(keepends=True),
        fromfile='announcement.md (before)',
        tofile='announcement.md (after)',
    ))
    sys.stdout.write(''.join(diff))
    if not diff:
        print('[sync_announcement] dry-run: no changes')
    print('[sync_announcement] dry-run: announcement.md not written')
    sys.exit(0)

# 原子写：先写临时文件再替换，失败不污染正式公告。
tmp_path = announcement_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as f:
    f.write(announcement)
os.replace(tmp_path, announcement_path)
print(f'[sync_announcement] flutter_app/assets/data/announcement.md updated for v{version}')
PY
