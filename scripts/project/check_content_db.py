#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""R15 发布闸门：内容库 ↔ 版本一致性校验。

校验项（对应 local_docs/plan-supplement/v1.0.0-phase6-release.md 细化补充）：
1. 表集合恰为内容表（classical_text / questions）+ SQLite 内部表（sqlite_*），
   不得包含任何旧用户表（kUserTableNames，须与 bridge/user_tables.h 同步）；
2. PRAGMA user_version == 1（db_version=1）；
3. 6 个强制初始化 q_key 全部存在（须与 bridge.cpp 两处列表同步）；
4. questions.q_key 非空且唯一，题数与 build/data/questions.json 一致；
5. db_version.txt 格式 YYYYMMDDHHMM-hash（兼容 YYYYMMDD-hash），
   其中 hash 为内容库的 Git blob hash 短哈希（git hash-object classical.db 前 7 位），
   不受 publish_data.sh 的 commit --amend 影响。

用法:
    python3 scripts/project/check_content_db.py [--db ...] [--questions-json ...] [--db-version ...]
"""

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# 旧用户表黑名单：与 bridge/user_tables.h 的 kUserTableNames 保持同步。
# 新增用户表时必须在 bridge/user_tables.h、tests/test_helpers.h 与本清单三处同步。
USER_TABLES = [
    "profiles",
    "user",
    "reading_history",
    "text_tracking",
    "learning_increments",
    "quiz_attempts",
    "review_items",
]

# 6 个强制初始化 q_key：与 bridge.cpp 的 kInitQKeys / initQKeyList() 两处保持同步。
INIT_Q_KEYS = [
    "d648b695e1579dbe",
    "28a1103b477177ee",
    "6dcbeb434a04bb29",
    "5f465c9792081778",
    "f6e064465d0da521",
    "638f4ed6d813d2f8",
]

# db_version.txt 格式：YYYYMMDD-hash（旧）或 YYYYMMDDHHMM-hash（新）。
DB_VERSION_RE = re.compile(r"^(\d{8}|\d{12})[-_]([0-9a-fA-F]{7,})$")


def git_blob_short_hash(path: Path) -> str:
    """计算与 `git hash-object <file>` 等价的短哈希（前 7 位）。"""
    data = path.read_bytes()
    full = hashlib.sha1(b"blob %d\x00" % len(data) + data).hexdigest()
    return full[:7]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description="校验内容库与版本文件的一致性（R15）")
    ap.add_argument("--db", type=Path, default=ROOT / "build/data/classical.db",
                    help="内容库路径（默认 build/data/classical.db）")
    ap.add_argument("--questions-json", type=Path, default=ROOT / "build/data/questions.json",
                    help="题库 JSON 路径（默认 build/data/questions.json）")
    ap.add_argument("--db-version", type=Path, default=ROOT / "flutter_app/assets/data/db_version.txt",
                    help="db_version.txt 路径（默认 flutter_app/assets/data/db_version.txt）")
    args = ap.parse_args()

    db_path = args.db
    qjson_path = args.questions_json
    ver_path = args.db_version

    if not db_path.is_file():
        fail(f"找不到内容库: {db_path}")
    if not qjson_path.is_file():
        fail(f"找不到 questions.json: {qjson_path}")
    if not ver_path.is_file():
        fail(f"找不到 db_version.txt: {ver_path}")

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    cur = conn.cursor()

    # 1. 表集合
    tables = {row[0] for row in cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    for bad in USER_TABLES:
        if bad in tables:
            fail(f"内容库含旧用户表 {bad}，不是纯内容库")
    for required in ("classical_text", "questions"):
        if required not in tables:
            fail(f"内容库缺少内容表 {required}")
    for name in tables:
        if name.startswith("sqlite_"):
            continue
        if name not in ("classical_text", "questions"):
            fail(f"内容库出现非预期表 {name}（仅允许 classical_text/questions/sqlite_* 内部表）")
    print(f"OK 1/5 表集合纯净（{len(tables)} 张表，无旧用户表）")

    # 2. user_version
    user_version = cur.execute("PRAGMA user_version").fetchone()[0]
    if user_version != 1:
        conn.close()
        fail(f"PRAGMA user_version 必须为 1，当前 {user_version}")
    print("OK 2/5 db_version(user_version)=1")

    # 3. 初始化 q_key
    present = {row[0] for row in cur.execute(
        "SELECT q_key FROM questions WHERE q_key IS NOT NULL AND q_key != ''")}
    missing = [k for k in INIT_Q_KEYS if k not in present]
    if missing:
        conn.close()
        fail(f"内容库缺少初始化 q_key: {missing}")
    print(f"OK 3/5 初始化 q_key 齐全（{len(INIT_Q_KEYS)} 个）")

    # 4. q_key 唯一 + 题数
    empty = cur.execute(
        "SELECT COUNT(*) FROM questions WHERE q_key IS NULL OR q_key = ''"
    ).fetchone()[0]
    if empty:
        conn.close()
        fail(f"questions.q_key 存在 {empty} 条空值")
    dups = cur.execute(
        "SELECT q_key, COUNT(*) FROM questions GROUP BY q_key HAVING COUNT(*) > 1"
    ).fetchall()
    if dups:
        conn.close()
        fail(f"questions.q_key 存在重复: {dups[:5]}")
    db_count = cur.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    with open(qjson_path, encoding="utf-8") as f:
        rows = json.load(f)
    if db_count != len(rows):
        conn.close()
        fail(f"内容库题数 {db_count} != questions.json 题数 {len(rows)}")
    print(f"OK 4/5 q_key 唯一且题数一致（{db_count} 题）")

    # 5. db_version.txt ↔ 内容库 blob hash
    ver_text = ver_path.read_text(encoding="utf-8").strip()
    m = DB_VERSION_RE.fullmatch(ver_text)
    if not m:
        conn.close()
        fail(f"db_version.txt 格式非法: {ver_text!r}")
    suffix = m.group(2)
    blob_short = git_blob_short_hash(db_path)
    if suffix[:7].lower() != blob_short.lower():
        conn.close()
        fail(f"db_version.txt hash {suffix} != 内容库 blob hash {blob_short}")
    print(f"OK 5/5 db_version.txt 与内容库 blob hash 一致（{ver_text}）")

    conn.close()
    print(f"PASS: 内容库发布校验通过 -> {db_path}")


if __name__ == "__main__":
    main()
