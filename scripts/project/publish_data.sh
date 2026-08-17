#!/bin/bash
# 发布数据更新（独立 prerelease，不干扰 app 版本更新检查）
# 用法: bash scripts/project/publish_data.sh
# 前置: 数据变更已 commit（classical.db 已生成并同步到 assets，见 README「快速开始」）
# 流程: 校验工作树 → 刷新 db_version.txt 并 amend 进 HEAD → 可复现性检查
#       → R15 内容库一致性校验 → gzip → gh release create（data-* prerelease）
#       → 触发 repro-check CI → 提醒 push
# 逃生口: SKIP_REPRO_CHECK=1 跳过可复现性检查；SKIP_AMEND=1 跳过版本号刷新与 amend
#         （SKIP_AMEND=1 时需已手动生成 db_version.txt，适合本地演练）
# R15 为发布硬闸门，不提供跳过开关。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB_SRC="$ROOT/build/data/classical.db"
VER_SRC="$ROOT/flutter_app/assets/data/db_version.txt"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh 未安装（https://cli.github.com/）" >&2
  exit 1
fi
if [ ! -f "$DB_SRC" ]; then
  echo "Error: 找不到 $DB_SRC，请先执行 init_data.py（README「快速开始」第 1 步）" >&2
  exit 1
fi

# ── 1. 工作树校验：除 db_version.txt 外必须干净 ──────────────────────────────
# 版本号将 amend 进 HEAD 提交；存在其他未提交变更时终止，防混入无关内容
DIRTY="$(git status --porcelain | grep -v 'db_version.txt' || true)"
if [ -n "$DIRTY" ]; then
  echo "Error: 存在未提交变更（db_version.txt 除外）——请先提交数据变更（git add + git commit）" >&2
  echo "$DIRTY" >&2
  exit 1
fi

# ── 2. 刷新版本号并 amend 进 HEAD（SKIP_AMEND=1 跳过）────────────────────────
if [ "${SKIP_AMEND:-}" != "1" ]; then
  if ! git symbolic-ref -q HEAD >/dev/null; then
    echo "Error: 处于 detached HEAD，无法 amend——请先 checkout 到发布分支" >&2
    exit 1
  fi
  # 还原可能的旧版本号残留，保证 gen_db_version.sh 基于干净工作树（hash 锚定数据提交）
  git checkout -- "$VER_SRC" 2>/dev/null || true
  echo "[publish_data] 刷新 db_version.txt..."
  bash "$ROOT/scripts/project/gen_db_version.sh"
  echo "[publish_data] 将改写 HEAD 提交并加入 db_version.txt:"
  git log -1 --oneline
  git add "$VER_SRC"
  git commit --amend --no-edit >/dev/null
  echo "[publish_data] HEAD 已更新: $(git log -1 --oneline)"
else
  if [ ! -f "$VER_SRC" ]; then
    echo "Error: SKIP_AMEND=1 但找不到 $VER_SRC——请先手动运行 gen_db_version.sh" >&2
    exit 1
  fi
  echo "[publish_data] SKIP_AMEND=1：沿用现有 db_version.txt（$(cat "$VER_SRC")）"
fi

# ── 3. 题库可复现性检查（SKIP_REPRO_CHECK=1 跳过）────────────────────────────
if [ "${SKIP_REPRO_CHECK:-}" != "1" ]; then
  echo "[publish_data] 题库可复现性检查（SKIP_REPRO_CHECK=1 可跳过）..."
  bash "$ROOT/scripts/project/check_questions_reproducible.sh"
fi

# ── 4. R15 内容库一致性校验（发布硬闸门）────────────────────────────────────
echo "[publish_data] R15 内容库一致性校验..."
python3 "$ROOT/scripts/project/check_content_db.py" \
  --db "$DB_SRC" \
  --questions-json "$ROOT/build/data/questions.json" \
  --db-version "$VER_SRC"

# ── 5. 打包并发布 ────────────────────────────────────────────────────────────
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

# ── 6. 触发可复现性 CI + 提醒 push（amend 改写本地提交）─────────────────────
BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [ -n "$BRANCH" ] && gh workflow run repro-check.yml --ref "$BRANCH" >/dev/null 2>&1; then
  echo "[publish_data] 已触发 repro-check CI（ref=$BRANCH，发布后留档检查）"
else
  echo "[publish_data] 提示: repro-check CI 未触发（workflow 未合入默认分支或 gh 不可用），不影响本次发布" >&2
fi

if [ -n "$BRANCH" ]; then
  LOCAL="$(git rev-parse HEAD)"
  REMOTE="$(git rev-parse "@{u}" 2>/dev/null || true)"
  if [ "$REMOTE" != "$LOCAL" ]; then
    echo "[publish_data] 注意: 本地 $BRANCH 与远端不一致（本次 amend 改写提交）——请推送："
    echo "[publish_data]   git push --force-with-lease（远端已含旧版数据提交时）或 git push"
  fi
fi
