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

# ── 3. CHANGELOG.md ──────────────────────────────────────────────────────────
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

echo ""
echo "Done! Next steps (for AI agent):"
echo "  1. 整理 CHANGELOG.md 的 release 描述（把开发细节转化为用户可感知的效果），然后请用户确认"
echo "  2. 用户确认后，执行:"
echo "     git add flutter_app/pubspec.yaml \\"
echo "           flutter_app/lib/state/coordinator.dart \\"
echo "           CHANGELOG.md \\"
echo "           scripts/project/bump_version.sh"
echo "     git commit -m \"release: v${NEW_VERSION}\" && git push origin dev"
echo "  3. 询问用户是否继续发版到 main，确认后执行:"
echo "     git switch main && git merge --squash dev"
echo "  4. 解决冲突后，询问用户确认，然后执行:"
echo "     git commit -m \"release: v${NEW_VERSION}\" && git tag v${NEW_VERSION} && git push origin main v${NEW_VERSION}"
echo "  5. 询问用户确认，然后执行:"
echo "     git switch dev && git reset --hard main && git push --force origin dev"
echo "  ---"
echo "  tag 推送成功后 force push dev（会重写历史），务必确认 tag 已推送。"
echo "gh cli可用，可以后续 sleep 五分钟后关注 CI 是否成功"