#!/bin/bash
# 一键升级版本号（pubspec.yaml 为唯一源）
# 用法: bash scripts/project/bump_version.sh <X.Y.Z>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <new_version>"
  echo "Example: $0 0.6.0"
  exit 1
fi

NEW_VERSION="$1"

if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: version must be in X.Y.Z format"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_DATE=$(date +%Y-%m-%d)

# ── 1. pubspec.yaml ──────────────────────────────────────────────────────────
sed -i "s/^version: .*/version: $NEW_VERSION/" "$ROOT/flutter_app/pubspec.yaml"
echo "[bump_version] flutter_app/pubspec.yaml -> $NEW_VERSION"

# ── 2. coordinator.dart ──────────────────────────────────────────────────────
sed -i "s/currentVersion = '[^']*'/currentVersion = '$NEW_VERSION'/" \
  "$ROOT/flutter_app/lib/state/coordinator.dart"
echo "[bump_version] coordinator.dart -> $NEW_VERSION"

# ── 3. installer.nsi（NSIS 安装包版本，与 pubspec 同源）────────────────────
NSIS="$ROOT/packaging/nsis/installer.nsi"
sed -i "s/!define PRODUCT_VERSION \".*\"/!define PRODUCT_VERSION \"$NEW_VERSION\"/" "$NSIS"
# VIProductVersion 需四段（X.Y.Z.0），Windows 属性页/UAC 弹窗显示
sed -i "s/VIProductVersion \".*\"/VIProductVersion \"$NEW_VERSION.0\"/" "$NSIS"
echo "[bump_version] packaging/nsis/installer.nsi -> $NEW_VERSION"

# ── 4. CHANGELOG.md ──────────────────────────────────────────────────────────
CHANGELOG="$ROOT/CHANGELOG.md"
# 将首个 ## [Unreleased] 替换为 ## [Unreleased]\n\n## [X.Y.Z] - date
awk -v ver="$NEW_VERSION" -v date="$RELEASE_DATE" '
/^## \[Unreleased\]/ {
  print "## [Unreleased]"
  print ""
  print "## [" ver "] - " date
  found = 1
  next
}
{ print }
' "$CHANGELOG" > "${CHANGELOG}.tmp" && mv "${CHANGELOG}.tmp" "$CHANGELOG"

# 追加版本链接引用
echo "[$NEW_VERSION]: https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v$NEW_VERSION" >> "$CHANGELOG"
echo "[bump_version] CHANGELOG.md -> release header + link reference"

# ── 5. announcement.md（从 CHANGELOG 同步“版本改动”，并更新 id）────────────
bash "$ROOT/scripts/project/sync_announcement.sh" "$NEW_VERSION"

echo ""
echo "Version bumped to $NEW_VERSION."
echo "Next: review CHANGELOG.md and flutter_app/assets/data/announcement.md, then follow docs/maintainer.md."