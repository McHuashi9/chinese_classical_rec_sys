#!/bin/bash
# 从 CHANGELOG.md 的指定版本段同步公告“版本改动”，并更新 announcement.md 的 id。
# 用法: bash scripts/project/sync_announcement.sh <X.Y.Z>
# 说明: bump_version.sh 会自动调用；若整理 CHANGELOG 后需要重新同步，也可单独执行。
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.2.1"
  exit 1
fi

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
ANNOUNCEMENT="$ROOT/flutter_app/assets/data/announcement.md"

if [ ! -f "$ANNOUNCEMENT" ]; then
  echo "[sync_announcement] flutter_app/assets/data/announcement.md not found, skip"
  exit 0
fi

python3 - "$VERSION" "$CHANGELOG" "$ANNOUNCEMENT" <<'PY'
import re
import sys

version, changelog_path, announcement_path = sys.argv[1:4]

with open(changelog_path, encoding='utf-8') as f:
    changelog = f.read()

section_pattern = re.compile(
    rf'^## \[{re.escape(version)}\] - .*?(?=^## \[|\Z)',
    re.M | re.S,
)
match = section_pattern.search(changelog)
if not match:
    print('[sync_announcement] warning: CHANGELOG section not found, skip changes sync')
    sys.exit(0)

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

with open(announcement_path, encoding='utf-8') as f:
    announcement = f.read()

# 更新 front matter 中的 id，确保“仅更新后弹出”能识别新版本
announcement = re.sub(
    r'^id:.*$',
    f'id: v{version}-1',
    announcement,
    count=1,
    flags=re.M,
)

if bullets:
    marker = '## 版本改动'
    changes_body = '\n'.join(f'- {b}' for b in bullets) + '\n'
    if marker in announcement:
        head = announcement.split(marker, 1)[0].rstrip()
        announcement = f'{head}\n\n{marker}\n\n{changes_body}'
    else:
        announcement = announcement.rstrip() + f'\n\n{marker}\n\n{changes_body}'
else:
    print('[sync_announcement] warning: no Added/Changed/Fixed bullets found, changes not synced')

with open(announcement_path, 'w', encoding='utf-8') as f:
    f.write(announcement)
PY

echo "[sync_announcement] flutter_app/assets/data/announcement.md -> id + 版本改动"
