#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
古文数据初始化脚本

从 processed_classical/ 目录读取古文数据和特征，导入 SQLite 数据库。
- 优先读取语文书带注释版（textbook_annotated）
- 再读取古文观止（anthology）
- 去重：同名文章保留语文书版本
- 共 264 篇古文（63 + 213 - 12 重复）

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

# 数据路径
TEXTBOOK_DIR = "processed_classical/textbook_annotated"
ANTHOLOGY_DIR = "processed_classical/anthology"
FEATURES_FILE = "processed_classical/features.json"


def extract_original_text(content: str) -> str:
    """从文件内容中提取【原文】部分的正文（去除注释标记）"""
    # 查找【原文】部分
    match = re.search(r"【原文】\n(.+?)(?=\n【注释】|\n【译文】|$)", content, re.DOTALL)
    if not match:
        # 如果没有【原文】标记，尝试直接使用全文（去掉标题和作者）
        lines = content.strip().split("\n")
        # 跳过标题和作者行
        if len(lines) > 2:
            return "\n".join(lines[2:]).strip()
        return content.strip()
    
    original = match.group(1).strip()
    # 去除注释标记〔n〕
    original = re.sub(r"〔\d+〕", "", original)
    return original.strip()


def extract_background(content: str) -> str:
    """从文件内容中提取【题解】部分作为背景介绍"""
    match = re.search(r"【题解】\n(.+?)(?=\n【原文】)", content, re.DOTALL)
    if match:
        bg = match.group(1).strip()
        # 去除混入的书信敬语（如"愈再拜："、"谨再拜言相公阁下："等）
        bg = re.sub(r'\n{2,}[^\n]*(?:再拜|谨再拜言|顿首)[^\n]*$', '', bg)
        return bg.strip()
    return ''


def parse_text_file(file_path: str, source: str = "") -> dict | None:
    """解析古文 txt 文件，提取标题、作者、正文、背景介绍"""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        lines = content.strip().split("\n")
        if len(lines) < 2:
            return None
        
        title = lines[0].strip()
        author = lines[1].strip()
        original_text = extract_original_text(content)
        background = extract_background(content)
        
        return {
            "title": title,
            "author": author,
            "content": original_text,
            "background": background,
            "source": source,
        }
    except Exception as e:
        print(f"解析文件失败 {file_path}: {e}")
        return None


def load_texts() -> dict:
    """加载所有古文数据，优先语文书版本
    
    使用文件名（去掉 .txt 后缀）作为标题，确保与 features.json 的键名一致，
    避免同名文章互相覆盖。
    """
    texts = {}
    anthology_bg = {}
    
    # 先加载古文观止（213篇）
    anthology_dir = Path(ANTHOLOGY_DIR)
    if anthology_dir.exists():
        for txt_file in anthology_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file), source="《古文观止》")
            if parsed:
                title = txt_file.stem
                parsed["title"] = title
                texts[title] = parsed
                anthology_bg[title] = parsed.get("background", "")
    
    # 再加载语文书带注释版（63篇，覆盖重复文章）
    textbook_dir = Path(TEXTBOOK_DIR)
    if textbook_dir.exists():
        for txt_file in textbook_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file), source="语文教科书")
            if parsed:
                title = txt_file.stem
                parsed["title"] = title
                # 教科书版 background 太短（仅出处标注）时用古文观止版补充
                tb_bg = parsed.get("background", "")
                if len(tb_bg) < 50 and title in anthology_bg and len(anthology_bg[title]) > 50:
                    parsed["background"] = anthology_bg[title]
                texts[title] = parsed
    
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
            last_read_time INTEGER DEFAULT 0
        );
    """)
    
    # 创建 classical_text 表（10维特征）
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
    
    missing_features = [t for t in texts if t not in features]
    if missing_features:
        print(f"警告: {len(missing_features)} 篇文章缺少特征数据: {missing_features[:3]}...")
    
    try:
        conn = sqlite3.connect(db_path)
        create_tables(conn)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM classical_text")
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='classical_text'")
        
        valid_texts = {k: v for k, v in texts.items() if k in features}
        for title, text_data in valid_texts.items():
            feat = features[title]
            char_count = len(re.sub(r'\s+', '', text_data["content"]))
            
            cursor.execute(
                """
                INSERT INTO classical_text 
                (title, author, dynasty, background, source, content, char_count,
                 f1_avg_sentence_length, f3_sentence_count,
                 f5_function_word_ratio, f6_avg_char_log_freq,
                 f8_tongjiazi_density, f9_ppl_ancient,
                 f10_ppl_modern, f11_mattr, 
                 f12_allusion_density, f13_semantic_complexity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    text_data["title"],
                    text_data["author"],
                    "",
                    text_data.get("background", ""),
                    text_data.get("source", ""),
                    text_data["content"],
                    char_count,
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
        conn.close()
        
        print(f"导入完成: {count} 篇, 耗时 {elapsed:.2f}s")
        print(f"数据库: {db_path}")
        return True
        
    except sqlite3.Error as e:
        print(f"数据库错误: {e}")
        return False


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
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