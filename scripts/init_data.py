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


# ============================================================================
# 彩色输出工具
# ============================================================================
class Color:
    """ANSI 颜色代码"""
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    
    # 前景色
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    
    # 背景色
    BG_RED = "\033[41m"
    BG_GREEN = "\033[42m"
    BG_YELLOW = "\033[43m"
    BG_BLUE = "\033[44m"


def colorize(text: str, color: str) -> str:
    """给文本添加颜色"""
    return f"{color}{text}{Color.RESET}"


def print_header(title: str):
    """打印标题头"""
    width = 60
    print()
    print(colorize("═" * width, Color.CYAN))
    print(colorize(f"  {title}", Color.BOLD + Color.CYAN))
    print(colorize("═" * width, Color.CYAN))


def print_step(step: int, total: int, message: str):
    """打印步骤信息"""
    prefix = colorize(f"[{step}/{total}]", Color.BOLD + Color.BLUE)
    print(f"{prefix} {message}")


def print_success(message: str):
    """打印成功信息"""
    icon = colorize("✓", Color.GREEN)
    print(f"  {icon} {message}")


def print_warning(message: str):
    """打印警告信息"""
    icon = colorize("⚠", Color.YELLOW)
    print(f"  {icon} {message}")


def print_error(message: str):
    """打印错误信息"""
    icon = colorize("✗", Color.RED)
    print(f"  {icon} {message}")


def print_info(message: str):
    """打印普通信息"""
    dot = colorize("•", Color.DIM)
    print(f"  {dot} {message}")


def print_progress_bar(current: int, total: int, prefix: str = "", width: int = 40):
    """打印进度条"""
    if total == 0:
        return
    
    percent = current / total
    filled = int(width * percent)
    bar = "█" * filled + "░" * (width - filled)
    
    bar_colored = colorize(bar[:filled], Color.GREEN) + colorize(bar[filled:], Color.DIM)
    percent_str = colorize(f"{percent:5.1%}", Color.BOLD + Color.CYAN)
    
    # 使用 \r 回到行首覆盖
    sys.stdout.write(f"\r  {prefix} [{bar_colored}] {percent_str} ({current}/{total})")
    sys.stdout.flush()
    
    if current == total:
        print()  # 完成后换行

# 数据库路径
DB_PATH = "data/classical.db"

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


def parse_text_file(file_path: str) -> dict | None:
    """解析古文 txt 文件，提取标题、作者、正文"""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        lines = content.strip().split("\n")
        if len(lines) < 2:
            return None
        
        title = lines[0].strip()
        author = lines[1].strip()
        original_text = extract_original_text(content)
        
        return {
            "title": title,
            "author": author,
            "content": original_text
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
    
    # 先加载古文观止（213篇）
    anthology_dir = Path(ANTHOLOGY_DIR)
    if anthology_dir.exists():
        for txt_file in anthology_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file))
            if parsed:
                title = txt_file.stem  # 使用文件名（不含扩展名）作为键
                parsed["title"] = title  # 更新标题为文件名
                texts[title] = parsed
    
    # 再加载语文书带注释版（63篇，覆盖重复文章）
    textbook_dir = Path(TEXTBOOK_DIR)
    if textbook_dir.exists():
        for txt_file in textbook_dir.glob("*.txt"):
            parsed = parse_text_file(str(txt_file))
            if parsed:
                title = txt_file.stem  # 使用文件名（不含扩展名）作为键
                parsed["title"] = title  # 更新标题为文件名
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
            name TEXT NOT NULL,
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
            content TEXT NOT NULL,
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
    
    for table_name, desc in tables:
        print_success(f"{table_name} - {desc}")
    
    return True


def init_database(db_path: str) -> bool:
    """初始化数据库并导入数据"""
    start_time = time.time()
    
    # Step 1: 创建数据库目录
    print_step(1, 5, "准备数据库目录")
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
        print_success(f"创建目录: {db_dir}")
    else:
        print_info(f"目录已存在: {db_dir or '.'}")
    
    # Step 2: 加载数据
    print_step(2, 5, "加载古文数据")
    texts = load_texts()
    print_success(f"古文观止 + 语文书 = {len(texts)} 篇")
    
    features = load_features()
    print_success(f"特征记录: {len(features)} 条")
    
    # Step 3: 标准化特征
    print_step(3, 5, "标准化特征值 (P2-P98)")
    features = percentile_normalize(features)
    print_success("特征值已标准化到 [0, 1] 范围")
    
    # 检查特征匹配
    missing_features = []
    for title in texts:
        if title not in features:
            missing_features.append(title)
    
    if missing_features:
        print_warning(f"{len(missing_features)} 篇文章缺少特征数据")
        for title in missing_features[:3]:
            print_info(f"缺失: {title}")
        if len(missing_features) > 3:
            print_info(f"... 还有 {len(missing_features) - 3} 篇")
    
    # Step 4: 创建数据库表
    print_step(4, 5, "创建数据库表")
    
    try:
        conn = sqlite3.connect(db_path)
        create_tables(conn)
        
        cursor = conn.cursor()
        
        # 清空现有数据
        cursor.execute("DELETE FROM classical_text")
        cursor.execute("DELETE FROM sqlite_sequence WHERE name='classical_text'")
        print_success("已清空现有数据")
        
        # Step 5: 插入数据
        print_step(5, 5, "导入古文数据")
        
        valid_texts = {k: v for k, v in texts.items() if k in features}
        total = len(valid_texts)
        
        inserted = 0
        for title, text_data in valid_texts.items():
            feat = features[title]
            
            cursor.execute(
                """
                INSERT INTO classical_text 
                (title, author, dynasty, content,
                 f1_avg_sentence_length, f3_sentence_count,
                 f5_function_word_ratio, f6_avg_char_log_freq,
                 f8_tongjiazi_density, f9_ppl_ancient,
                 f10_ppl_modern, f11_mattr, 
                 f12_allusion_density, f13_semantic_complexity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    text_data["title"],
                    text_data["author"],
                    "",
                    text_data["content"],
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
            inserted += 1
            print_progress_bar(inserted, total, "导入进度")
        
        conn.commit()
        
        # 统计信息
        elapsed = time.time() - start_time
        cursor.execute("SELECT COUNT(*) FROM classical_text")
        count = cursor.fetchone()[0]
        
        print()
        print_header("导入完成")
        print()
        print_info(f"数据库路径: {colorize(db_path, Color.CYAN)}")
        print_info(f"古文总数:   {colorize(str(count), Color.GREEN)} 篇")
        print_info(f"耗时:       {colorize(f'{elapsed:.2f}s', Color.MAGENTA)}")
        print()
        
        print()
        
        conn.close()
        return True
        
    except sqlite3.Error as e:
        print_error(f"数据库错误: {e}")
        return False


def main():
    # 获取项目根目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    os.chdir(project_root)
    
    print_header("古文数据初始化 (10维特征)")
    print()
    print_info(f"工作目录:   {colorize(os.getcwd(), Color.CYAN)}")
    print_info(f"数据库路径: {colorize(DB_PATH, Color.CYAN)}")
    
    success = init_database(DB_PATH)
    
    print()
    if success:
        icon = colorize("✓", Color.BOLD + Color.GREEN)
        msg = colorize("数据初始化成功！", Color.GREEN)
        print(f"  {icon} {msg}")
    else:
        icon = colorize("✗", Color.BOLD + Color.RED)
        msg = colorize("数据初始化失败！", Color.RED)
        print(f"  {icon} {msg}")
        sys.exit(1)


if __name__ == "__main__":
    main()