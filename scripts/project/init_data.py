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
    
    tables = [
        ("user", "用户表（10维能力 + 基础能力）"),
        ("classical_text", "古文表（10维特征）"),
        ("reading_history", "阅读历史表"),
        ("learning_increments", "学习增量表"),
    ]
    
    # 创建 user 表（与 UserRepository.cpp 完全一致）
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            d1_ability REAL DEFAULT 0.0,
            d2_ability REAL DEFAULT 0.0,
            d3_ability REAL DEFAULT 0.0,
            d4_ability REAL DEFAULT 0.0,
            d5_ability REAL DEFAULT 0.0,
            d6_ability REAL DEFAULT 0.0,
            d7_ability REAL DEFAULT 0.0,
            d8_ability REAL DEFAULT 0.0,
            d9_ability REAL DEFAULT 0.0,
            d10_ability REAL DEFAULT 0.0,
            d1_base_ability REAL DEFAULT 0.0,
            d2_base_ability REAL DEFAULT 0.0,
            d3_base_ability REAL DEFAULT 0.0,
            d4_base_ability REAL DEFAULT 0.0,
            d5_base_ability REAL DEFAULT 0.0,
            d6_base_ability REAL DEFAULT 0.0,
            d7_base_ability REAL DEFAULT 0.0,
            d8_base_ability REAL DEFAULT 0.0,
            d9_base_ability REAL DEFAULT 0.0,
            d10_base_ability REAL DEFAULT 0.0,
            eta REAL DEFAULT 0.08,
            d1_quiz_count INTEGER DEFAULT 0,
            d2_quiz_count INTEGER DEFAULT 0,
            d3_quiz_count INTEGER DEFAULT 0,
            d4_quiz_count INTEGER DEFAULT 0,
            d5_quiz_count INTEGER DEFAULT 0,
            d6_quiz_count INTEGER DEFAULT 0,
            d7_quiz_count INTEGER DEFAULT 0,
            d8_quiz_count INTEGER DEFAULT 0,
            d9_quiz_count INTEGER DEFAULT 0,
            d10_quiz_count INTEGER DEFAULT 0,
            last_read_time INTEGER DEFAULT 0
        );
    """)
    
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
    
    # 创建 reading_history 表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS reading_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL DEFAULT 1,
            text_id INTEGER NOT NULL,
            read_time REAL NOT NULL,
            read_timestamp INTEGER NOT NULL
        );
    """)
    
    # 创建 learning_increments 表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS learning_increments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL DEFAULT 1,
            dimension INTEGER NOT NULL,
            delta REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            type TEXT DEFAULT 'read'
        );
    """)
    
    # 创建索引
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_learning_increments_user_dim
        ON learning_increments(user_id, dimension);
    """)

    # 创建 questions 表（内容库：题目 + 答案 + 解析，随数据包同步）
    # answer_index = 正确答案在 options JSON 数组中的下标（0-based）；
    # dims = CSV（如 "3,4,9"，0-based 维度），C++/Dart 直接 split 解析；
    # context = 划线词所在原句（mark_start/mark_len = 划线区间，无则 -1/0）
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
            FOREIGN KEY (text_id) REFERENCES classical_text(id)
        );
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_questions_text
        ON questions(text_id);
    """)
    
    conn.commit()
    return True


def init_database(db_path: str) -> bool:
    """初始化数据库并导入数据"""
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
    
    try:
        conn = sqlite3.connect(db_path)
        create_tables(conn)
        cursor = conn.cursor()
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
        
        conn.commit()
        elapsed = time.time() - start_time
        cursor.execute("SELECT COUNT(*) FROM classical_text")
        count = cursor.fetchone()[0]

        # 导入题库（build/data/questions.json，generate_questions.py --json 生成）
        q_imported = 0
        questions_file = os.path.join(os.path.dirname(DB_PATH), "questions.json")
        if os.path.exists(questions_file):
            cursor.execute("DELETE FROM questions")
            cursor.execute("DELETE FROM sqlite_sequence WHERE name='questions'")
            title_to_id = {r[0]: r[1] for r in
                           cursor.execute("SELECT title, id FROM classical_text").fetchall()}
            with open(questions_file, encoding="utf-8") as f:
                rows = json.load(f)
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
                cursor.execute(
                    """
                    INSERT INTO questions
                    (text_id, q_type, stem, options, answer_index, explanation, difficulty, dims, seq,
                     context, mark_start, mark_len)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (tid, r["q_type"], r["stem"], json.dumps(r["options"], ensure_ascii=False),
                     r["answer_index"], r["explanation"], r["difficulty"],
                     r["dims"], r["seq"], r.get("context", ""),
                     r.get("mark_start", -1), r.get("mark_len", 0)),
                )
                q_imported += 1
            conn.commit()
            print(f"题库导入: {q_imported} 题（来源 {questions_file}）")
        else:
            print(f"题库文件不存在（跳过）: {questions_file}")

        conn.close()
        
        print(f"导入完成: {count} 篇, 耗时 {elapsed:.2f}s")
        print(f"数据库: {db_path}")
        return True
        
    except sqlite3.Error as e:
        print(f"数据库错误: {e}")
        return False


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    os.chdir(project_root)
    
    print(f"工作目录: {os.getcwd()}")
    print(f"数据库: {DB_PATH}")
    
    success = init_database(DB_PATH)
    
    if success:
        print("数据初始化成功！")
    else:
        print("数据初始化失败！")
        sys.exit(1)


if __name__ == "__main__":
    main()