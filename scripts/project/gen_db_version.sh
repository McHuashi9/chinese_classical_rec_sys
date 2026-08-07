#!/bin/bash
# 自动生成 db_version.txt
# 用法: bash scripts/project/gen_db_version.sh
# 由维护者在数据变更后调用（先 commit 再执行再 amend）
set -euo pipefail

OUTPUT="flutter_app/assets/data/db_version.txt"
if ! git diff --quiet; then
    echo "WARNING: uncommitted changes detected — hash may not match committed state" >&2
fi
GIT_HASH=$(git rev-parse --short HEAD)
# 格式 YYYYMMDDHHMM-hash：12 位定长时间前缀，方向判断无需猜同日 hash
DATE=$(date +%Y%m%d%H%M)
# 发布机时钟回拨保护：生成的时间戳不得早于库中已有的版本时间
CURRENT_VERSION=$(git show HEAD:flutter_app/assets/data/db_version.txt 2>/dev/null || true)
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
