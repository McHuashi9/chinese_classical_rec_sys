#!/usr/bin/env python3
"""导出旧库 questions 的 q_key→id 映射（发布/重建前的 id 对齐用）

用法:
    python3 scripts/project/export_question_id_map.py [db路径] [-o 输出.json]
- 始终按 generate_questions.py 当前指纹函数现算（不用库内 q_key 列）：
  answer 文本 = json(options)[answer_index]，title/author 经 classical_text 联表
- 不用库内列的原因：库内列可能是更早算法版本的指纹（如题干引号样式变更前），
  与当前算法不一致会导致 id 认领失配、复习数据漂移；现算保证两边同算法。
- 重建前须先让旧库 = 内容已更新的当前库（或与目标内容指纹一致），
  否则内容指纹改变（如改题干）的题会认领失败 → 尾部追加新 id
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
    rows = cur.execute("""
        SELECT q.id, t.title, t.author, q.q_type, q.stem, q.options, q.answer_index
        FROM questions q JOIN classical_text t ON q.text_id = t.id
    """).fetchall()
    id_map = {}
    for qid, title, author, q_type, stem, options, ans_idx in rows:
        answer = json.loads(options)[ans_idx]
        id_map[compute_q_key(title, author or "", q_type, stem, answer)] = qid
    print(f"按当前指纹现算导出 {len(id_map)} 条（库内 q_key 列值不采用）")
    conn.close()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(id_map, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"导出 {len(id_map)} 条 q_key→id 映射 → {out}")


if __name__ == "__main__":
    main()
