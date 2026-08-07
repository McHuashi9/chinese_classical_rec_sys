#!/bin/bash
# 发布数据更新（独立 prerelease，不干扰 app 版本更新检查）
# 用法: bash scripts/project/publish_data.sh
# 前置: 已生成 DB 与 db_version.txt（见 README「快速开始」与 gen_db_version.sh）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB_SRC="$ROOT/build/data/classical.db"
VER_SRC="$ROOT/flutter_app/assets/data/db_version.txt"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh 未安装（https://cli.github.com/）" >&2
  exit 1
fi

if [ ! -f "$DB_SRC" ]; then
  echo "Error: 找不到 $DB_SRC，请先执行 init_data.py" >&2
  exit 1
fi
if [ ! -f "$VER_SRC" ]; then
  echo "Error: 找不到 $VER_SRC，请先执行 gen_db_version.sh" >&2
  exit 1
fi

if ! git diff --quiet; then
  echo "WARNING: uncommitted changes detected — db_version 可能与提交不一致" >&2
fi

VER="$(cat "$VER_SRC")"
TAG="data-$(date +%Y%m%d-%H%M%S)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gzip -c "$DB_SRC" > "$TMP/classical.db.gz"

echo "[publish_data] 压缩 classical.db.gz: $(wc -c < "$TMP/classical.db.gz") bytes"
echo "[publish_data] tag: $TAG  db_version: $VER"

gh release create "$TAG" \
  --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
  --prerelease \
  --title "数据更新 $VER" \
  "$TMP/classical.db.gz" \
  "$VER_SRC"

echo "[publish_data] Done: https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/tag/$TAG"