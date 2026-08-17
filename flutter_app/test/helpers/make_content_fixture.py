#!/usr/bin/env python3
"""生成纯内容库测试 fixture。

输入：当前 asset classical.db 路径、输出路径。
逻辑：复制 asset → 删除 7 张旧用户表（profiles / user / reading_history /
text_tracking / learning_increments / quiz_attempts / review_items）→
PRAGMA user_version = 1。
"""
import sqlite3
import sys
import shutil

USER_TABLES = [
    "profiles",
    "user",
    "reading_history",
    "text_tracking",
    "learning_increments",
    "quiz_attempts",
    "review_items",
]


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: make_content_fixture.py <src.db> <dst.db>", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    shutil.copyfile(src, dst)
    conn = sqlite3.connect(dst)
    try:
        for table in USER_TABLES:
            conn.execute(f'DROP TABLE IF EXISTS "{table}"')
        # sqlite_sequence 是 SQLite 内部表，不能 DROP；删除用户表后残留行不影响
        # 内容库纯净校验（黑名单不含该内部表）。
        conn.execute("PRAGMA user_version = 1")
        conn.commit()
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
