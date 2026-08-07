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
DATE=$(date +%Y%m%d)
echo "${DATE}-${GIT_HASH}" > "$OUTPUT"
echo "[gen_db_version] $OUTPUT = ${DATE}-${GIT_HASH}"
