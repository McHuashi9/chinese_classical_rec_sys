#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
古文数据初始化脚本

从 articles/ 目录读取古文数据和特征，导入 SQLite 数据库。
- 先读取古文观止（anthology）
- 再读取语文教科书（textbook），覆盖同名同作者文选版本
- 去重：按 (title, author) 去重，同名不同作者共存
- 共 270 篇古文（202 + 68）

数据库自动创建，使用10维特征体系（与论文Table 3一致）：
- d1: f1 平均句长
- d2: f3 句子数
- d3: f5 虚词比例
- d4: f6 字平均对数频次
- d5: f8 通假字密度
- d6: f9 古汉语困惑度
- d7: f10 今汉语困惑度
- d8: f11 MATTR词汇多样性
- d9: f12 典故密度
- d10: f13 语义复杂度

排除：f2(字数)、f4(总词数)、f7(生僻字密度)
"""

import argparse
import io
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

import numpy as np

# Fix Windows console encoding for Chinese characters
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 数据库路径
DB_PATH = "build/data/classical.db"

# 数据路径（应用数据源）
TEXTBOOK_DIR = "articles/textbook"
ANTHOLOGY_DIR = "articles/anthology"
# 特征文件（文章特征，数据管线产出）
FEATURES_FILE = "scripts/project/features.json"


def extract_original_text(content: str) -> str:
    """从文件内容中提取【原文】部分的正文（保留〔n〕注释标记）"""
    match = re.search(r"【原文】\n(.+?)(?=\n【注释】|\n【译文】|$)", content, re.DOTALL)
    if not match:
        lines = content.strip().split("\n")
        if len(lines) > 2:
            return "\n".join(lines[2:]).strip()
        return content.strip()
    return match.group(1).strip()


def extract_annotations(content: str) -> str:
    """从文件内容中提取【注释】章节原文"""
    match = re.search(r"【注释】\n(.+?)(?=\n【译文】|$)", content, re.DOTALL)
    return match.group(1).strip() if match else ""


def extract_translation(content: str) -> str:
    """从文件内容中提取【译文】章节原文（译文是文件最后一段，译者名段原样保留）"""
    match = re.search(r"【译文】\n(.+?)(?=$)", content, re.DOTALL)
    return match.group(1).strip() if match else ""


def extract_background(content: str) -> str:
    """从文件内容中提取【题解】部分作为背景介绍"""
    match = re.search(r"【题解】\n(.+?)(?=\n【原文】)", content, re.DOTALL)
    if match:
        bg = match.group(1).strip()
        # 去除混入的书信敬语（如"愈再拜："、"谨再拜言相公阁下："等）
        bg = re.sub(r'\n{2,}[^\n]*(?:再拜|谨再拜言|顿首)[^\n]*$', '', bg)
        return bg.strip()
    return ''


def parse_front_matter(content: str) -> dict | None:
    """解析 YAML front matter，返回 {title, author, dynasty, source} 或 None"""
    match = re.match(r'^---\s*\n(.+?)\n---\s*\n', content, re.DOTALL)
    if not match:
        return None
    result = {}
    for line in match.group(1).strip().split('\n'):
        if ':' in line:
            key, _, value = line.partition(':')
            result[key.strip()] = value.strip()
    return result


def strip_front_matter(content: str) -> str:
    """移除文件开头的 YAML front matter，返回纯正文"""
    return re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, count=1, flags=re.DOTALL)


def parse_text_file(file_path: str) -> dict | None:
    """解析古文 txt 文件，从 front matter 提取元数据，从正文提取题解、原文和注释"""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        fm = parse_front_matter(content)
        if not fm:
            print(f"警告: {file_path} 缺少 front matter，跳过")
            return None
        
        body = strip_front_matter(content)
        original_text = extract_original_text(body)
        background = extract_background(body)
        annotations_raw = extract_annotations(body)
        translation = extract_translation(body)
        
        return {
            "title": fm.get('title', ''),
            "author": fm.get('author', ''),
            "dynasty": fm.get('dynasty', ''),
            "content": original_text,
            "background": background,
            "source": fm.get('source', ''),
            "annotations_raw": annotations_raw,
            "translation": translation,
        }
    except Exception as e:
        print(f"解析文件失败 {file_path}: {e}")
        return None


def load_texts() -> dict:
    """加载所有古文数据，优先语文书版本
    
    使用 (title, author) 作为去重 key，避免同名不同作者文章（如六国论苏洵/苏辙）
    互相覆盖。保留 filename_stem 用于 features.json 失配时的 fallback。
    """
    texts = {}
    anthology_bg = {}
    
    # 先加载古文观止
    anthology_dir = Path(ANTHOLOGY_DIR)
    if anthology_dir.exists():
        for txt_file in anthology_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file))
            if parsed:
                title = parsed["title"]
                author = parsed.get("author", "")
                key = (title, author)
                parsed["_filename_stem"] = txt_file.stem
                texts[key] = parsed
                anthology_bg[title] = parsed.get("background", "")
    
    # 再加载语文书（覆盖同名同作者文选版本）
    textbook_dir = Path(TEXTBOOK_DIR)
    if textbook_dir.exists():
        for txt_file in textbook_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file))
            if parsed:
                title = parsed["title"]
                author = parsed.get("author", "")
                key = (title, author)
                parsed["_filename_stem"] = txt_file.stem
                # 教科书版 background 太短（仅出处标注）时用古文观止版补充
                tb_bg = parsed.get("background", "")
                if len(tb_bg) < 50 and title in anthology_bg and len(anthology_bg[title]) > 50:
                    parsed["background"] = anthology_bg[title]
                texts[key] = parsed
    
    return texts


def load_features() -> dict:
    """加载特征数据"""
    features_path = Path(FEATURES_FILE)
    if not features_path.exists():
        print(f"特征文件不存在: {FEATURES_FILE}")
        return {}
    
    with open(features_path, "r", encoding="utf-8") as f:
        return json.load(f)


# 10维特征键名（与论文Table 3一致）
FEATURE_KEYS = [
    "f1_avg_sentence_length",   # d1
    "f3_sentence_count",        # d2
    "f5_function_word_ratio",   # d3
    "f6_avg_char_log_freq",     # d4
    "f8_tongjiazi_density",     # d5
    "f9_ppl_ancient",           # d6
    "f10_ppl_modern",           # d7
    "f11_mattr",                # d8
    "f12_allusion_density",     # d9
    "f13_semantic_complexity"   # d10
]


def percentile_normalize(features: dict, lower_pct: int = 2, upper_pct: int = 98) -> dict:
    """百分位数标准化特征到 [0,1] 范围
    
    使用 P2-P98 替代 min/max，避免极端值影响。
    与论文方法一致。
    
    Args:
        features: 原始特征字典 {title: {feature_key: value, ...}}
        lower_pct: 下百分位数（默认2）
        upper_pct: 上百分位数（默认98）
    
    Returns:
        标准化后的特征字典
    """
    if not features:
        return features
    
    # 提取所有文章的特征矩阵
    titles = list(features.keys())
    n_texts = len(titles)
    n_features = len(FEATURE_KEYS)
    
    raw_matrix = np.zeros((n_texts, n_features))
    for i, title in enumerate(titles):
        for j, key in enumerate(FEATURE_KEYS):
            raw_matrix[i, j] = features[title].get(key, 0.0)
    
    # 计算每个特征的百分位数
    lowers = np.percentile(raw_matrix, lower_pct, axis=0)
    uppers = np.percentile(raw_matrix, upper_pct, axis=0)
    
    # 标准化
    normalized_matrix = np.zeros_like(raw_matrix)
    for j in range(n_features):
        if uppers[j] - lowers[j] > 1e-9:
            normalized_matrix[:, j] = np.clip(
                (raw_matrix[:, j] - lowers[j]) / (uppers[j] - lowers[j]), 0.0, 1.0
            )
        else:
            normalized_matrix[:, j] = 0.5  # 常量特征设为中间值
    
    # 方向性反转：↓难特征的语义反转（"值越大越难"）
    normalized_matrix[:, 3] = 1 - normalized_matrix[:, 3]  # f6 (字平均对数频次, ↓难)
    normalized_matrix[:, 5] = 1 - normalized_matrix[:, 5]  # f9 (古汉语困惑度, ↓难)
    
    # 构建标准化后的特征字典
    normalized_features = {}
    for i, title in enumerate(titles):
        normalized_features[title] = {}
        for j, key in enumerate(FEATURE_KEYS):
            normalized_features[title][key] = float(normalized_matrix[i, j])
    
    return normalized_features


def create_tables(conn: sqlite3.Connection) -> bool:
    """创建数据库表（如果不存在）"""
    cursor = conn.cursor()
    
    # 兼容旧表：若缺少 annotations_raw / translation 则新增列
    try:
        cursor.execute("ALTER TABLE classical_text ADD COLUMN annotations_raw TEXT DEFAULT ''")
    except sqlite3.OperationalError:
        pass  # 列已存在
    try:
        cursor.execute("ALTER TABLE classical_text ADD COLUMN translation TEXT DEFAULT ''")
    except sqlite3.OperationalError:
        pass  # 列已存在

    # 创建 classical_text 表（10维特征 + 注释 + 译文）
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS classical_text (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            author TEXT,
            dynasty TEXT,
            background TEXT DEFAULT '',
            source TEXT DEFAULT '',
            content TEXT NOT NULL,
            char_count INTEGER DEFAULT 0,
            annotations_raw TEXT DEFAULT '',
            translation TEXT DEFAULT '',
            f1_avg_sentence_length REAL DEFAULT 0.0,
            f3_sentence_count REAL DEFAULT 0.0,
            f5_function_word_ratio REAL DEFAULT 0.0,
            f6_avg_char_log_freq REAL DEFAULT 0.0,
            f8_tongjiazi_density REAL DEFAULT 0.0,
            f9_ppl_ancient REAL DEFAULT 0.0,
            f10_ppl_modern REAL DEFAULT 0.0,
            f11_mattr REAL DEFAULT 0.0,
            f12_allusion_density REAL DEFAULT 0.0,
            f13_semantic_complexity REAL DEFAULT 0.0
        );
    """)

    # 创建 questions 表（内容库：题目 + 答案 + 解析，随数据包同步）
    # answer_index = 正确答案在 options JSON 数组中的下标（0-based）；
    # dims = CSV（如 "3,4,9"，0-based 维度），C++/Dart 直接 split 解析；
    # context = 划线词所在原句（mark_start/mark_len = 划线区间，无则 -1/0）；
    # q_key = 内容指纹稳定键（generate_questions.py 生成；不含 options），
    #   数据包重建时按 q_key 认领旧 id，保证老用户 quiz_attempts/review_items 引用不漂移
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text_id INTEGER NOT NULL,
            q_type TEXT NOT NULL,
            stem TEXT NOT NULL,
            options TEXT NOT NULL,
            answer_index INTEGER NOT NULL,
            explanation TEXT DEFAULT '',
            difficulty REAL DEFAULT 0.0,
            dims TEXT DEFAULT '',
            seq INTEGER DEFAULT 0,
            context TEXT DEFAULT '',
            mark_start INTEGER DEFAULT -1,
            mark_len INTEGER DEFAULT 0,
            q_key TEXT DEFAULT '',
            FOREIGN KEY (text_id) REFERENCES classical_text(id)
        );
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_questions_text
        ON questions(text_id);
    """)
    # 部分唯一索引：空键不受唯一约束（老数据/无键行兼容）
    cursor.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_q_key
        ON questions(q_key) WHERE q_key != '';
    """)
    
    return True


def init_database(db_path: str, id_map: dict | None = None,
                  questions_json: str = "") -> bool:
    """初始化数据库并导入数据

    id_map: {q_key: 旧 id} 映射（export_question_id_map.py 导出）。
    提供时按 q_key 认领旧 id，新题尾部追加——老用户 quiz_attempts/review_items
    引用的 question_id 不漂移；None 时全新自增（首次建库）。

    questions_json: 题库 JSON 路径。显式给出时锚定该文件（保证与 --db 同批次）；
    留空时沿用默认 build/data/questions.json（与 --db 路径无关，向后兼容）。

    整个建库（schema → 清空 → 写入 → user_version → 纯净断言）在单个事务内完成，
    且先写到 <db>.tmp、提交成功后再原子替换目标库：任何失败都回到运行前状态。
    """
    start_time = time.time()
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
    
    texts = load_texts()
    features = load_features()
    features = percentile_normalize(features)
    
    # 特征匹配：先试 front matter title，失配则 fallback 到 filename.stem
    # （如 郑伯克段于鄢 文件名含括号，features.json 的 key 也含括号）
    texts_with_features = {}
    missing = []
    for (title, author), text_data in texts.items():
        fname = text_data.get("_filename_stem", title)
        if title in features:
            texts_with_features[(title, author)] = (text_data, features[title])
        elif fname in features:
            texts_with_features[(title, author)] = (text_data, features[fname])
        else:
            texts_with_features[(title, author)] = (text_data, None)
            missing.append(f"{title}（{author}）")
    
    if missing:
        print(f"特征缺失（将用 0.5 填充，背景加【特征待定】）: {len(missing)} 篇")
        for m in missing:
            print(f"  - {m}")
    
    # 题库路径：显式 --questions-json 锚定该文件；否则沿用默认（避免静默取错批次）
    if questions_json:
        questions_file = questions_json
    else:
        questions_file = os.path.join(os.path.dirname(DB_PATH), "questions.json")
        db_dir_abs = os.path.dirname(os.path.abspath(db_path))
        q_dir_abs = os.path.dirname(os.path.abspath(questions_file))
        if db_dir_abs != q_dir_abs:
            print(f"提示: 题库默认取自 {questions_file}（与 --db 不同目录）；"
                  f"如库与题库不属同一批次，请用 --questions-json 显式指定")

    # 先建到临时文件，全部成功后再原子替换，失败时目标库逐字节不变
    tmp_path = db_path + ".tmp"
    conn = None
    try:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        conn = sqlite3.connect(tmp_path)
        conn.isolation_level = None                # 关掉 Python 隐式 BEGIN，全程手工控制事务
        conn.execute("PRAGMA foreign_keys = ON")   # 必须在 BEGIN 之前（事务内为 no-op）
        conn.execute("BEGIN IMMEDIATE")            # 立刻取 RESERVED 锁，避免中途升级失败
        create_tables(conn)
        cursor = conn.cursor()
        # 外键方向：先删子表 questions，再删父表 classical_text（插入顺序仍为父→子）
        cursor.execute("DELETE FROM questions")
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='questions'")
        cursor.execute("DELETE FROM classical_text")
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='classical_text'")
        
        for (title, author), (text_data, feat) in texts_with_features.items():
            # char_count 基于去标记后的计数
            content_clean = re.sub(r"〔\d+〕", "", text_data["content"])
            char_count = len(re.sub(r'\s+', '', content_clean))
            background = text_data.get("background", "")
            annotations_raw = text_data.get("annotations_raw", "")
            
            if feat is None:
                # 新文章无特征，使用中值 0.5 填充，背景标注特征待定
                feat = {k: 0.5 for k in FEATURE_KEYS}
                background = "【特征待定】" + background
            
            cursor.execute(
                """
                INSERT INTO classical_text 
                (title, author, dynasty, background, source, content, char_count,
                 annotations_raw, translation,
                 f1_avg_sentence_length, f3_sentence_count,
                 f5_function_word_ratio, f6_avg_char_log_freq,
                 f8_tongjiazi_density, f9_ppl_ancient,
                 f10_ppl_modern, f11_mattr, 
                 f12_allusion_density, f13_semantic_complexity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    text_data["title"],
                    text_data["author"],
                    text_data.get("dynasty", ""),
                    background,
                    text_data.get("source", ""),
                    text_data["content"],
                    char_count,
                    annotations_raw,
                    text_data.get("translation", ""),
                    feat.get("f1_avg_sentence_length", 0.0),
                    feat.get("f3_sentence_count", 0),
                    feat.get("f5_function_word_ratio", 0.0),
                    feat.get("f6_avg_char_log_freq", 0.0),
                    feat.get("f8_tongjiazi_density", 0.0),
                    feat.get("f9_ppl_ancient", 0.0),
                    feat.get("f10_ppl_modern", 0.0),
                    feat.get("f11_mattr", 0.0),
                    feat.get("f12_allusion_density", 0.0),
                    feat.get("f13_semantic_complexity", 0.0),
                ),
            )
        
        elapsed = time.time() - start_time
        cursor.execute("SELECT COUNT(*) FROM classical_text")
        count = cursor.fetchone()[0]

        # 导入题库（generate_questions.py --json 生成；路径由 --questions-json 或默认给出）
        q_imported = 0
        if os.path.exists(questions_file):
            title_to_id = {r[0]: r[1] for r in
                           cursor.execute("SELECT title, id FROM classical_text").fetchall()}
            with open(questions_file, encoding="utf-8") as f:
                rows = json.load(f)
            # id 对齐：--id-map（{q_key: 旧 id}）命中则沿用旧 id，新题从 max+1 尾部追加
            # （保证老用户 quiz_attempts/review_items 的 question_id 引用不漂移）
            used_ids = set()
            next_id = (max(id_map.values()) + 1) if id_map else None
            for r in rows:
                tid = None
                # 优先 (title, author) 匹配（如 郑伯克段于鄢 有《左传》/《穀梁传》两篇同名）
                hits = cursor.execute(
                    "SELECT id FROM classical_text WHERE title=? AND author=?",
                    (r["title"], r.get("author", ""))).fetchall()
                if len(hits) == 1:
                    tid = hits[0][0]
                else:
                    tid = title_to_id.get(r["title"])
                if tid is None:
                    continue
                q_key = r.get("q_key", "")
                qid = None
                if q_key and id_map and q_key in id_map:
                    qid = id_map[q_key]
                    if qid in used_ids:  # 防御：映射重复/新行 q_key 冲突
                        qid = None
                if qid is None and next_id is not None:
                    qid = next_id
                if qid is not None:
                    used_ids.add(qid)
                # 显式 id 模式下让自增序列跟随最大 id
                if qid is not None and (next_id is not None):
                    next_id = max(next_id, qid + 1)
                # 单条 14 列 INSERT：qid=None 时写 NULL，由 SQLite 自增（与显式 id 分支合并）
                cursor.execute(
                    """
                    INSERT INTO questions
                    (id, text_id, q_type, stem, options, answer_index, explanation, difficulty, dims, seq,
                     context, mark_start, mark_len, q_key)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (qid, tid, r["q_type"], r["stem"], json.dumps(r["options"], ensure_ascii=False),
                     r["answer_index"], r["explanation"], r["difficulty"],
                     r["dims"], r["seq"], r.get("context", ""),
                     r.get("mark_start", -1), r.get("mark_len", 0), q_key),
                )
                q_imported += 1
            if next_id is not None:
                # 自增序列对齐：未来 AUTOINCREMENT 从当前最大 id+1 继续
                cursor.execute("DELETE FROM sqlite_sequence WHERE name='questions'")
                cursor.execute("INSERT INTO sqlite_sequence(name, seq) VALUES ('questions', ?)",
                               (max(used_ids, default=0),))
            print(f"题库导入: {q_imported} 题（来源 {questions_file}"
                  f"{'，id-map 对齐 ' + str(len(used_ids)) + ' 题' if next_id is not None else ''}）")
        else:
            if questions_json:
                # 显式指定的题库缺失＝配置错误：直接失败回滚，避免静默产出无题库库
                raise FileNotFoundError(f"题库文件不存在: {questions_file}")
            print(f"题库文件不存在（跳过）: {questions_file}")

        # user_version 在数据写入之后、commit 之前（实测可回滚），与内容同生共死
        conn.execute("PRAGMA user_version = 1")

        # 内容库纯净断言：只允许内容表 + SQLite 内部表，且 user_version=1
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {r[0] for r in cursor.fetchall()}
        forbidden_user_tables = {
            "profiles", "user", "reading_history", "text_tracking",
            "learning_increments", "quiz_attempts", "review_items",
        }
        bad = tables & forbidden_user_tables
        if bad:
            raise RuntimeError(f"内容库包含用户表，重建失败: {sorted(bad)}")
        required = {"classical_text", "questions"}
        missing = required - tables
        if missing:
            raise RuntimeError(f"内容库缺少必要内容表: {sorted(missing)}")
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        if version != 1:
            raise RuntimeError(f"内容库 user_version 应为 1，实际为 {version}")
        print(f"内容库断言通过：表={sorted(tables - {'sqlite_sequence'})}，user_version={version}")

        conn.commit()                   # 唯一 commit：断言全部通过后才落盘
        conn.close()
        conn = None
        os.replace(tmp_path, db_path)   # 原子替换：失败时目标库逐字节不变

        print(f"导入完成: {count} 篇, 耗时 {elapsed:.2f}s")
        print(f"数据库: {db_path}")
        return True
        
    except Exception as e:
        # 捕获面须覆盖断言 RuntimeError / OSError / JSONDecodeError / KeyError，全部回滚
        if conn is not None:
            try:
                conn.rollback()
            except sqlite3.Error:
                pass
        print(f"数据库错误: {e}")
        return False
    finally:
        if conn is not None:
            conn.close()
        # 成功路径的临时文件已被 os.replace 移走；失败路径在此清理，保证目标库不变
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def main():
    ap = argparse.ArgumentParser(description="初始化 classical.db（内容库）")
    ap.add_argument("--db", default=DB_PATH, help=f"数据库路径（默认 {DB_PATH}）")
    ap.add_argument("--id-map", default="",
                    help="旧库 q_key→id 映射 JSON（export_question_id_map.py 导出），"
                         "用于题库 id 对齐（老用户复习数据不漂移）")
    ap.add_argument("--questions-json", default="",
                    help="题库 JSON 路径（默认 build/data/questions.json，与 --db 路径无关）；"
                         "自定义 --db 时显式给出，避免库与题库来自两个批次")
    args = ap.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    os.chdir(project_root)

    id_map = None
    if args.id_map:
        id_map = json.loads(Path(args.id_map).read_text(encoding="utf-8"))

    print(f"工作目录: {os.getcwd()}")
    print(f"数据库: {args.db}")

    success = init_database(args.db, id_map, args.questions_json)

    if success:
        print("数据初始化成功！")
    else:
        print("数据初始化失败！")
        sys.exit(1)


if __name__ == "__main__":
    main()