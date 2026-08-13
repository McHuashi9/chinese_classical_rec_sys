#!/usr/bin/env python3
"""导出旧库 questions 的 q_key→id 映射（发布/重建前的 id 对齐用）

用法:
    python3 scripts/project/export_question_id_map.py [db路径] [-o 输出.json]
- 老库已有 q_key 列 → 直接 SELECT q_key, id
- 老库无 q_key 列（v0.9.4 及以前）→ 用与 generate_questions.py 相同的指纹函数现算：
  answer 文本 = json(options)[answer_index]，title/author 经 classical_text 联表
输出供 init_data.py --id-map 使用：旧题认领旧 id，新题尾部追加，
老用户 quiz_attempts/review_items 的 question_id 引用不漂移。
"""
import argparse
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_questions import compute_q_key  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="导出 questions 表 q_key→id 映射")
    ap.add_argument("db", nargs="?", default="build/data/classical.db", help="旧库路径")
    ap.add_argument("-o", "--out", default="build/data/question_id_map.json", help="输出 JSON 路径")
    args = ap.parse_args()

    if not Path(args.db).exists():
        print(f"错误: 找不到旧库 {args.db}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(args.db)
    cur = conn.cursor()
    cols = [r[1] for r in cur.execute("PRAGMA table_info(questions)").fetchall()]
    if "q_key" in cols:
        rows = cur.execute("SELECT q_key, id FROM questions WHERE q_key != ''").fetchall()
        id_map = {k: i for k, i in rows}
        print(f"旧库已有 q_key 列：直接导出 {len(id_map)} 条")
    else:
        rows = cur.execute("""
            SELECT q.id, t.title, t.author, q.q_type, q.stem, q.options, q.answer_index
            FROM questions q JOIN classical_text t ON q.text_id = t.id
        """).fetchall()
        id_map = {}
        for qid, title, author, q_type, stem, options, ans_idx in rows:
            answer = json.loads(options)[ans_idx]
            id_map[compute_q_key(title, author or "", q_type, stem, answer)] = qid
        print(f"旧库无 q_key 列：按指纹现算导出 {len(id_map)} 条")
    conn.close()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(id_map, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"导出 {len(id_map)} 条 q_key→id 映射 → {out}")


if __name__ == "__main__":
    main()
