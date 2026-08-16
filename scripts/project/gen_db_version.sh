#!/bin/bash
# 自动生成 db_version.txt
# 用法: bash scripts/project/gen_db_version.sh
# 由维护者在数据变更后调用（先 commit 再执行再 amend）
#
# hash 语义（2026-08-16 起）：内容库的 Git blob hash（git hash-object classical.db 前 7 位），
# 不是 commit hash。commit --amend 会改变 commit hash 但不会改变 classical.db 内容，
# 因此 R15 check_content_db 可以稳定校验“版本串 ↔ 数据库内容”。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="$ROOT/flutter_app/assets/data/db_version.txt"
DB_FILE="$ROOT/flutter_app/assets/data/classical.db"
if [ ! -f "$DB_FILE" ]; then
    echo "Error: 找不到 $DB_FILE，请先 cp build/data/classical.db flutter_app/assets/data/" >&2
    exit 1
fi
if ! git diff --quiet -- "$DB_FILE"; then
    echo "WARNING: classical.db 有未提交变更 — 生成的 hash 只代表当前工作树内容" >&2
fi
GIT_HASH=$(git hash-object "$DB_FILE" | cut -c1-7)
# 格式 YYYYMMDDHHMM-hash：12 位定长时间前缀，方向判断无需猜同日 hash
DATE=$(date +%Y%m%d%H%M)
# 发布机时钟回拨保护：生成的时间戳不得早于库中已有的版本时间
CURRENT_VERSION=$(git -C "$ROOT" show HEAD:flutter_app/assets/data/db_version.txt 2>/dev/null || true)
if [ -n "$CURRENT_VERSION" ]; then
    CURRENT_DAY=${CURRENT_VERSION%%-*}
    CURRENT_DAY=${CURRENT_DAY:0:8}
    NEW_DAY=${DATE:0:8}
    if [ "$NEW_DAY" -lt "$CURRENT_DAY" ]; then
        echo "WARNING: 生成版本日期($NEW_DAY)早于库中已有版本($CURRENT_DAY)，疑似时钟回拨" >&2
    fi
fi
echo "${DATE}-${GIT_HASH}" > "$OUTPUT"
echo "[gen_db_version] $OUTPUT = ${DATE}-${GIT_HASH}"
