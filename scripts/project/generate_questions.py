#!/usr/bin/env python3
"""出题引擎（v1）：实词解释 / 通假字还原 / 文白翻译

从 articles/ 生成选择题，供质量抽验；
--json 全量生成入库文件 build/data/questions.json（供 init_data.py 导入 questions 表）。
题目基于注释〔n〕标记 + 段落对齐译文，全部干扰项来自真实语料（同篇/同源其他文章）。

用法:
    python3 scripts/project/generate_questions.py              # 全量生成 + 统计
    python3 scripts/project/generate_questions.py --sample 20  # 随机抽 20 篇输出可读文本
    python3 scripts/project/generate_questions.py --json       # 全量生成 + 写入入库 JSON
"""
import argparse
import hashlib
import json
import random
import re
import sys
import unicodedata
from pathlib import Path

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")

ARTICLES_DIR = Path(__file__).resolve().parents[2] / "articles"
FEATURES_FILE = Path(__file__).resolve().parent / "features.json"
EXTERNAL_TJ = Path(__file__).resolve().parents[2] / "external" / "tongjiazi" / "knowledge_base"
# --sample 产物输出目录（相对仓库，与 --json 的 build/data/questions.json 同风格）
OUT_DIR = Path(__file__).resolve().parents[2] / "build" / "data" / "questions_sample"

# CRITIC 权重（与 include/core/Config.h 一致，d1..d10）
CRITIC_WEIGHTS = [0.09215, 0.09382, 0.13107, 0.09247, 0.10341,
                  0.11624, 0.08775, 0.08544, 0.10088, 0.09677]

# 特征键（与 init_data.py FEATURE_KEYS 一致，顺序敏感）
FEATURE_KEYS = ["f1_avg_sentence_length", "f3_sentence_count", "f5_function_word_ratio",
                "f6_avg_char_log_freq", "f8_tongjiazi_density", "f9_ppl_ancient",
                "f10_ppl_modern", "f11_mattr", "f12_allusion_density", "f13_semantic_complexity"]

# 题型 → 维度（论文表 tab:question_mapping）；d8/d9 无对应题型
TYPE_DIMS = {
    "shici": [3, 4, 9],      # 字词解释 → d4, d5, d10
    "tongjia": [4],          # 通假字还原 → d5
    "fanyi": [5, 6, 9],      # 文白翻译 → d6, d7, d10
}


def percentile_normalize(features: dict, lower_pct: int = 2, upper_pct: int = 98) -> dict:
    """复刻 init_data.py 的百分位标准化（P2-P98 + f6/f9 方向反转），输出 [0,1]"""
    titles = list(features.keys())
    raw = np.zeros((len(titles), len(FEATURE_KEYS)))
    for i, t in enumerate(titles):
        for j, k in enumerate(FEATURE_KEYS):
            raw[i, j] = features[t].get(k, 0.0)
    norm = np.zeros_like(raw)
    for j in range(len(FEATURE_KEYS)):
        lo, hi = np.percentile(raw, lower_pct, axis=0)[j], np.percentile(raw, upper_pct, axis=0)[j]
        if hi - lo > 1e-9:
            norm[:, j] = np.clip((raw[:, j] - lo) / (hi - lo), 0.0, 1.0)
        else:
            norm[:, j] = 0.5
    norm[:, 3] = 1 - norm[:, 3]  # f6 反转
    norm[:, 5] = 1 - norm[:, 5]  # f9 反转
    return {t: {FEATURE_KEYS[j]: float(norm[i, j]) for j in range(len(FEATURE_KEYS))}
            for i, t in enumerate(titles)}

ANNO_RE = re.compile(r"〔(\d+)〕\s*(.*?)(?=〔\d+〕|$)", re.DOTALL)
TONGJIA_RE = re.compile(r"[通同][“\"]([^”\"，。；]{1,4})[”\"]")
PARA_SPLIT_RE = re.compile(r"\n\s*\n")

# 一字多本字/异体组：取干扰项时排除"与借字成对的其他本字"（防异体同现判分争议）
ZHENG_ALIAS_GROUPS = [
    {"举", "欤", "歙"}, {"旒", "癞", "砺"}, {"嘱", "注"}, {"悌", "第"},
    {"吁", "管"}, {"尝", "曾"}, {"掘", "缺"}, {"压", "餍"}, {"缧", "蔂"},
    {"叙", "绪"}, {"腰", "邀"}, {"赈", "震"},
]


def strip_tail_zhu_yin(head: str) -> str:
    """剥离词头尾部的注音括号（X（mǐn敏）→ X）；括号前置（（huān欢）合）不剥离"""
    m = re.match(r"^([\u4e00-\u9fff]+)[（(][^）)]*[）)]$", head)
    return m.group(1) if m else head


def parse_article(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    title_m = re.search(r"^title:\s*(.+)$", raw, re.MULTILINE)
    text = re.sub(r"^---\s*\n.*?\n---\s*\n", "", raw, count=1, flags=re.DOTALL)

    def grab(section: str, stop: tuple) -> str:
        m = re.search(rf"【{section}】\n(.+?)(?=\n【(?:{'|'.join(stop)})】|$)", text, re.DOTALL)
        return m.group(1).strip() if m else ""

    return {
        # 命名铁律：文件名 == front matter title（2026-08-11 起，A 类 2 篇已 git mv 对齐）
        # 唯一例外：同名异篇用括号消歧（郑伯克段于鄢（左传/穀梁传）、六国论（苏辙）），
        #   此时 features.json 的 key 用文件名形式（郑伯克段）或共享裸 title（六国论苏洵/苏辙共用）。
        #   title_fallback 是为郑伯克段一处服务的。
        "title": title_m.group(1).strip() if title_m else path.stem,
        "author": author_m.group(1).strip() if (author_m := re.search(r"^author:\s*(.+)$", raw, re.MULTILINE)) else "",
        "title_fallback": path.stem,  # features.json 的 key 是文件名 stem（含 钴鉧潭 等差异）
        "original": grab("原文", ("注释", "译文")),
        "annotations_raw": grab("注释", ("译文",)),
        "translation": translation_no_signature(grab("译文", ())),
        "source": "textbook" if "textbook" in str(path) else "anthology",
    }


def translation_no_signature(translation: str) -> str:
    """剥离译文末尾的译者名段（如"（曾维华）""（顾易生　李笑野）"）"""
    paras = split_paras(translation)
    while paras:
        tail = paras[-1].strip()
        if (len(tail) <= 12
                and not re.search(r"[。！？；：，、]", tail)
                and re.fullmatch(r"[()（）\u4e00-\u9fff\s\u3000]+", tail)):
            paras.pop()
        else:
            break
    return "\n\n".join(paras)


def parse_annotations(raw: str) -> list:
    """解析注释条目：[{num, head, text}]

    兼容两种词头格式：
    - anthology：〔1〕衷：通"中"，此为正确之意。（冒号分隔，全角空格拆多条）
    - textbook：〔7〕[坻]水中高地。[嵁]不平的岩石。（方括号包裹，可多条）
    """
    items = []
    for m in ANNO_RE.finditer(raw):
        num, body = int(m.group(1)), m.group(2).strip()
        if "[" in body:
            for part in re.split(r"(?=\[)", body):
                mm = re.match(r"\[([^\]]+)\](.*)", part.strip())
                if mm:
                    head = mm.group(1).strip()
                    items.append({"num": num, "head": head,
                                  "text": f"{head}：{mm.group(2).strip()}"})
            continue
        for part in re.split(r"\u3000", body):  # 按单个全角空格拆多条词条（与 Dart AnnotationParser 规则一致）
            head, sep, meaning = part.partition("：")
            if not sep:  # 无词头并入前条
                if items:
                    items[-1]["text"] += " " + part
                continue
            if head.startswith("按"):  # 注释者按语（如"按：这两句…"）不是词条，丢弃
                continue
            # 释义尾部混入的按语一并截断（如"水滨。按：以上写阁外之景。"）
            meaning = re.split(r"按[：:].*$", meaning, maxsplit=1)[0].rstrip()
            items.append({"num": num, "head": head.strip(), "text": f"{head.strip()}：{meaning.strip()}"})
    return items


def is_literal_word(item: dict) -> bool:
    """实词候选：纯汉字词头 1-3 字，排除引文/括号注音/文化常识类"""
    h = item["head"]
    if not h or not re.fullmatch(r"[\u4e00-\u9fff]{1,3}", h):
        return False
    kw = ("人名", "地名", "字", "号", "谥", "年号", "官", "朝代", "即",
          "古国", "春秋", "战国", "汉", "唐", "宋", "元", "明", "清",
          "指", "此指", "这里是", "姓", "名", "氏")
    return not any(k in item["text"].split("：", 1)[-1][:12] for k in kw)


# 划线词的记号写法：heading 后紧贴词在原文中位置 → 每题存 context（原句）+
# mark_start/mark_len（划线区间，无则 -1/0，Dart 端直接下标渲染，不重复搜索）
NO_MARK = {"context": "", "mark_start": -1, "mark_len": 0}


def extract_context(art: dict, num: int, head: str) -> dict:
    """取含 〔num〕 的原句 + 划线词偏移（raw→clean 映射）

    标记在原文中位置不定：textbook 常紧贴词后，anthology 常挂在句尾
    （如"顾安所得酒乎〔10〕"中「顾」在句首）→ 取句内距标记最近的
    一次出现；纯函数不碰 random，seed 固定下题库可复现。
    """
    orig = art["original"]
    marker = f"〔{num}〕"
    if marker not in orig:
        return dict(NO_MARK)
    mpos = orig.find(marker)
    # 换行也是句界（防跨段拼接）；前后扫最近的断点
    s = max(orig.rfind(c, 0, mpos) for c in "\n。！？")
    e = min((i for i in (orig.find(c, mpos) for c in "\n。！？") if i >= 0), default=len(orig))
    sent = orig[s + 1:e]
    mpos = sent.find(marker)  # 标记在句内偏移（与 starts 同坐标系）
    starts = [m.start() for m in re.finditer(re.escape(head), sent)]
    if not starts:
        return dict(NO_MARK)
    # 距标记最近（优先出现在标记之前）
    best = min(starts, key=lambda p: (abs(p - mpos), p > mpos))
    mks = list(re.finditer(r"〔\d+〕", sent))
    # 剔除标记造成的偏移：统计 best 之前所有标记字符数
    shift = sum(m.end() - m.start() for m in mks if m.start() < best)
    clean = re.sub(r"〔\d+〕", "", sent)
    mark_start = best - shift
    # 清洗首尾空白与不成对引号（引号整句包裹时剥壳，前导字符同步调整偏移）
    new_lead = len(clean) - len(clean.lstrip())
    clean = clean[new_lead:].rstrip()
    mark_start -= new_lead
    quotes = "\u201c\u201d\u2018\u2019\""
    new_lead = len(clean) - len(clean.lstrip(quotes))
    new_tail = len(clean) - len(clean.rstrip(quotes))
    clean = clean[new_lead:len(clean) - new_tail]
    mark_start -= new_lead
    if not 0 <= mark_start <= len(clean) - len(head):
        return dict(NO_MARK)
    return {"context": clean, "mark_start": mark_start, "mark_len": len(head)}


def gen_shici(art: dict, items: list) -> list:
    """实词解释：正确释义 + 同篇其他词头释义（张冠李戴式干扰项）"""
    qs = []
    seen = set()
    # 排除释义含通假结构（[通同]"）的条目：归通假字题型出，避免题型错位
    cands = [i for i in items if is_literal_word(i) and len(i["text"]) <= 60
             and not re.search(r"[通同][“\"]", i["text"].split("：", 1)[-1])]
    if len(cands) < 4:
        return qs
    for item in cands:
        if item["head"] in seen:  # 同篇同词头只出 1 题（防重复）
            continue
        seen.add(item["head"])
        correct = item["text"].split("：", 1)[-1].strip()
        pool = []
        for other in cands:
            if other["head"] == item["head"]:
                continue
            d = other["text"].split("：", 1)[-1].strip()
            if d != correct and d not in pool and abs(len(d) - len(correct)) <= 30:
                pool.append(d)
        if len(pool) < 3:
            continue
        distractors = random.sample(pool, 3)
        qs.append({
            "type": "shici", "dims": TYPE_DIMS["shici"],
            "stem": f"下列句中划线词“{item['head']}”的解释，正确的一项是",
            "options": [correct] + distractors,
            "answer": correct,
            # 解析前拼正确答案文本：结果页答错时也能看到正确答案（判题仍只在 C++ 侧）
            "explanation": f"正确答案：{correct}。{item['text']}",
            **extract_context(art, item["num"], item["head"]),
        })
    return qs


def flat_pinyin(s: str) -> str:
    """去声调拼音（NFD 去组合符，mào→mao；多音串按整串原样保留）"""
    return "".join(c for c in unicodedata.normalize("NFD", s or "")
                   if not unicodedata.combining(c))


def compute_q_key(title: str, author: str, q_type: str, stem: str, answer: str) -> str:
    """题目稳定键：内容指纹（不含 options/difficulty/explanation/seq → 换干扰项不改键）

    数据包重建时按 q_key 认领旧 id，保证老用户 quiz_attempts/review_items
    引用的 question_id 不漂移（新题尾部追加）。
    """
    raw = f"{title}|{author}|{q_type}|{stem}|{answer}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


class TongjiaMaterial:
    """通假字干扰项素材索引（③ 形近/音近；素材/依赖缺失时优雅降级为纯①本字池）

    音近口径：干扰项 = 与本字同音（去声调）的语料字，读音以 pypinyin（含多音字）
    为权威源——源数据 tongjia_links 的拼音字段在借字/本字间不一致，不可直接采信。
    题目语义 =「同音字里选对的那个」（通假真实错因）。
    形近口径：同声旁（质量高，优先）> 同部首同结构（nodes 素材，次选）。
    """

    def __init__(self, zheng_pool: list, corpus_chars: set):
        self.zheng_pool = sorted(zheng_pool)
        self.corpus_chars = set(corpus_chars)
        self.char_readings = {}   # 字 -> {去声调读音}（pypinyin，heteronym 全读音）
        self.char_sb = {}         # 形声字 -> 声旁
        self.sb_chars = {}        # 声旁 -> {形声字}
        self.char_rs = {}         # 字 -> {(部首, 结构)}
        self.rad_struct = {}      # (部首, 结构) -> {字}
        self.sound_ok = False
        self.shape_ok = False
        self._load_readings()
        self._load_external()

    def _load_readings(self):
        try:
            from pypinyin import Style, pinyin as pinyin_fn
        except ImportError:
            print("警告: 未安装 pypinyin → ③ 音近换质关闭（形近仍可用）")
            return
        chars = self.corpus_chars | set(self.zheng_pool)
        self.char_readings = {
            ch: {flat_pinyin(x[0]) for x in pinyin_fn(ch, style=Style.NORMAL, heteronym=True)}
            for ch in sorted(chars)
        }
        self.sound_ok = True

    def _load_external(self):
        xs_f = EXTERNAL_TJ / "xingsheng_links.jsonl"
        nodes_f = EXTERNAL_TJ / "nodes.jsonl"
        if not all(f.exists() for f in (xs_f, nodes_f)):
            print("警告: external/tongjiazi 素材缺失 → ③ 形近换质关闭")
            return
        for line in xs_f.open(encoding="utf-8"):
            r = json.loads(line)
            ch, sb = r.get("形声字", ""), r.get("声旁", "")
            if ch and sb:
                self.char_sb[ch] = sb
                self.sb_chars.setdefault(sb, set()).add(ch)
        for line in nodes_f.open(encoding="utf-8"):
            r = json.loads(line)
            ch, rad, st = r.get("字", ""), r.get("部首", ""), r.get("结构", "")
            if ch and rad and st:
                self.char_rs.setdefault(ch, set()).add((rad, st))
                self.rad_struct.setdefault((rad, st), set()).add(ch)
        self.shape_ok = True

    def sound_pool(self, word: str, zhengzi: str) -> set:
        """与本字同音（去声调，pypinyin 全读音交集）的语料字"""
        if not self.sound_ok:
            return set()
        ans = self.char_readings.get(zhengzi, set())
        if not ans:
            return set()
        return {c for c in self.corpus_chars
                if self.char_readings.get(c, set()) & ans}

    def shape_pool_primary(self, word: str, zhengzi: str) -> set:
        """形近池（优）：同声旁字（借字/本字作声旁或形声字）"""
        if not self.shape_ok:
            return set()
        out = set()
        for ch in (word, zhengzi):
            sb = self.char_sb.get(ch)
            if sb:
                out |= self.sb_chars.get(sb, set())
            if ch in self.sb_chars:
                out |= {c for c in self.sb_chars[ch]}
        return out & self.corpus_chars

    def shape_pool_secondary(self, word: str, zhengzi: str) -> set:
        """形近池（次）：同部首同结构字"""
        if not self.shape_ok:
            return set()
        out = set()
        for ch in (word, zhengzi):
            for key in self.char_rs.get(ch, ()):
                out |= self.rad_struct.get(key, set())
        return out & self.corpus_chars


def gen_tongjia(art: dict, items: list, mat: TongjiaMaterial) -> list:
    """通假字还原：本字 + 干扰项三级降级

    候选判定（防张冠李戴）：
    - 单字词头：释义必须 [通同]" 直启 才采信（X：通"Y" / X（注音）：同"Y"），
      排除"词头并非借字"的条目（如"厉：带子下垂的部分。游：同'旒'"）
    - 复合词头：首字必须紧邻"通/同"引号结构（X…：X，通'Y'），
      排除"后字才是借字"的复合词头（如"顾反命：…反，同'返'"）

    干扰项三级降级（题集不变硬约束：换质失败回退原①选项，绝不掉题）：
    1. 音近×2 + 形近×1（音近 = 与本字同音去声调的语料字；形近 = 同声旁 > 同部首同结构）
    2. 音近×2 + ①本字池×1（形近不足时）
    3. ①全库本字池×3（现状；本字池必须排序保 seed 可复现）
    """
    qs = []
    cands = []
    seen = set()
    for item in items:
        bare = strip_tail_zhu_yin(item["head"])
        if not bare:
            continue
        m = TONGJIA_RE.search(item["text"])
        if not m:
            continue
        if re.fullmatch(r"[\u4e00-\u9fff]", bare):
            # 单字词头：仅释义以"通/同"直启的条目（词头 = 借字）
            meaning = item["text"].split("：", 1)[-1].strip()
            if not re.search(r"^[通同][“\"]", meaning):
                continue
            word = bare
        else:
            # 复合词头：首字必须紧邻"通/同"引号结构
            if not re.search(re.escape(bare[0]) + r"[，。；、]?[通同][“\"]",
                             item["text"]):
                continue
            word = bare[0]
        if word in seen:
            continue
        seen.add(word)
        cands.append((item, word, m.group(1)))
    if not cands:
        return qs
    # 换质采样用独立 RNG（避免扰动主随机流 → shici/fanyi 输出与旧版逐字节一致）
    swap_rng = random.Random(42)
    for item, word, zhengzi in cands:
        # 与旧行为完全一致的池与消耗：每道题恒消费 1 次主随机流 sample(pool,3)
        # （换质成功则弃用、失败/未换质则照用 → shici/fanyi 下游抽样不受扰动）
        banned_old = {zhengzi} | next((g for g in ZHENG_ALIAS_GROUPS if zhengzi in g), set())
        pool_old = [z for z in mat.zheng_pool if z not in banned_old]
        # 题集不变硬约束：本字池不足 3 不出题（与旧行为一致，换质不改变题集）
        if len(pool_old) < 3:
            continue
        old_sample = random.sample(pool_old, 3)
        options = None
        swap = "none"
        if mat.sound_ok:
            banned = banned_old | {word}
            sound = sorted(mat.sound_pool(word, zhengzi) - banned)
            if len(sound) >= 2:
                s2 = swap_rng.sample(sound, 2)
                if mat.shape_ok:
                    shape = [c for c in sorted(mat.shape_pool_primary(word, zhengzi) - banned)
                             if c not in s2]
                    if not shape:
                        shape = [c for c in sorted(mat.shape_pool_secondary(word, zhengzi) - banned)
                                 if c not in s2]
                    if shape:
                        options = [zhengzi] + s2 + [swap_rng.choice(shape)]
                        swap = "sound_shape"
                if options is None:
                    pool_sw = [z for z in pool_old if z != word]
                    if pool_sw:
                        options = [zhengzi] + s2 + swap_rng.sample(pool_sw, 1)
                        swap = "sound_pool"
        if options is None:
            options = [zhengzi] + old_sample
        q = {
            "type": "tongjia", "dims": TYPE_DIMS["tongjia"],
            "stem": f"下列句中划线字“{word}”的本字，正确的一项是",
            "options": options,
            "answer": zhengzi,
            "explanation": f"正确答案：{zhengzi}。{item['text']}",
            **extract_context(art, item["num"], word),
        }
        # 换质失败回退①（用已消费的 old_sample，不额外消耗随机流；回退后仍不过才跳过）
        if not validate(q):
            q["options"] = [zhengzi] + old_sample
            swap = "none"
        if not validate(q):
            continue
        q["_swap"] = swap
        qs.append(q)
    return qs


def split_paras(text: str) -> list:
    return [p.strip() for p in PARA_SPLIT_RE.split(text) if p.strip()]


def align_paras(orig_paras: list, trans_paras: list, heads: list) -> list:
    """段级锚点对齐：注释词头做锚，单调递增映射

    原文/译文段落数可不等（译文对照的逐段对齐由阅读器渲染时容错完成），
    这里只需找到"词头共现"的段对为翻译题提供素材。
    """
    anchors = {}  # head -> (o_idx, t_idx)
    for h in (h for h in heads if len(h) >= 2):
        o_idx = [i for i, p in enumerate(orig_paras) if h in p]
        t_idx = [i for i, p in enumerate(trans_paras) if h in p]
        if o_idx and t_idx:
            anchors[h] = (o_idx[0], t_idx[0])
    pairs, last_t = [], -1
    for o_idx in range(len(orig_paras)):
        ts = [ti for oi, ti in anchors.values() if oi == o_idx and ti > last_t]
        if ts:
            last_t = max(ts)
        if last_t >= 0:
            pairs.append((o_idx, last_t))
    return pairs


def gen_fanyi(art: dict, items: list, sent_pool: list = None) -> list:
    """文白翻译：段内句级对齐出题

    段落普遍偏长（可至 500+ 字），改取段内"含〔n〕注释标记且词头命中对应译文句"
    的句子做题干，正确译文句来自锚点对齐段的句级匹配（anthology 专名命中率高，
    textbook 译文改写多、命中率低，覆盖有限）；干扰项为译文句池中的真实语料。
    """
    qs = []
    orig_paras = split_paras(art["original"])
    trans_paras = split_paras(art["translation"])
    pairs = align_paras(orig_paras, trans_paras, [i["head"] for i in items])
    by_num = {i["num"]: i for i in items}
    all_t = [s for p in trans_paras for s in re.split(r"[。！？]", p) if s.strip()]
    pool = sent_pool if sent_pool else all_t
    # 段长比例过滤：对齐段对若译文/原文长度比例偏离整体水平过多，判定为错配对段
    # （实测合法对段 r∈[0.66,1.05]，错配样本 r=2.32；阈值 [0.5,1.7] 不伤合法对段）
    tot_o = sum(len(p) for p in orig_paras)
    tot_t = sum(len(p) for p in trans_paras)
    for o_idx, t_idx in pairs:
        if t_idx < 0 or t_idx >= len(trans_paras):
            continue
        expected = len(orig_paras[o_idx]) * tot_t / tot_o
        ratio = len(trans_paras[t_idx]) / expected if expected > 0 else 0
        if not 0.5 <= ratio <= 1.7:
            continue
        o_sents = [s for s in re.split(r"[。！？]", orig_paras[o_idx]) if s.strip()]
        t_sents = [s for s in re.split(r"[。！？]", trans_paras[t_idx]) if s.strip()]
        if not o_sents or not t_sents:
            continue
        best = None  # (命中权重, 原句, 译文句)
        for s in o_sents:
            heads_in = [by_num[int(n)]["head"] for n in re.findall(r"〔(\d+)〕", s)
                        if int(n) in by_num]
            heads_in = [h for h in heads_in if 2 <= len(h) <= 6]
            if not heads_in:
                continue
            # 词头按长度加权：共享词头长度总和 ≥4 才采信（防"赵氏"类短词头误配）
            cand = [ts for ts in t_sents if sum(len(h) for h in heads_in if h in ts) >= 4]
            if cand:
                ts = max(cand, key=lambda t: sum(len(h) for h in heads_in if h in t))
                score = sum(len(h) for h in heads_in if h in ts)
                if best is None or score > best[0]:
                    best = (score, s, ts)
        if not best:
            continue
        _, o_sent, t_sent = best
        if not 8 <= len(o_sent) <= 110 or not 12 <= len(t_sent) <= 150:
            continue
        distractors = [t2 for t2 in all_t
                       if t2 != t_sent
                       and abs(len(t2) - len(t_sent)) / max(len(t_sent), 1) < 1.2
                       and clean_markers(t2)]
        if len(distractors) < 3:  # 同篇不足，跨篇取真实译文句
            distractors = [t2 for t2 in pool
                           if t2 != t_sent and t2 not in all_t
                           and abs(len(t2) - len(t_sent)) / max(len(t_sent), 1) < 1.2
                           and clean_markers(t2)]
        if len(distractors) < 3:
            continue
        random.shuffle(distractors)
        t_sent = clean_markers(t_sent)
        t_opts = [t_sent] + [clean_markers(d) for d in distractors[:3]]
        qs.append({
            "type": "fanyi", "dims": TYPE_DIMS["fanyi"],
            "stem": f"下列对文中画线句子的翻译，正确的一项是\n{clean_markers(o_sent)}",
            "options": t_opts,
            "answer": t_sent,
            "explanation": f"正确答案：{t_sent}。\n（原句自原文段 {o_idx+1}，译文句自译文段 {t_idx+1}）",
        })
        break  # 每篇只出 1 题翻译
    return qs


def clean_markers(s: str) -> str:
    """题干/选项清洗：去除〔n〕注释标记、首尾残留引号、不成对引号"""
    s = re.sub(r"〔\d+〕", "", s)
    s = re.sub(r'^["“]+|["”]+$', "", s)
    if s.count("“") != s.count("”"):  # 引号不成对，去掉孤立引号
        s = s.replace("“", "").replace("”", "")
    s = s.replace('""', "")
    return s.strip()


def validate(q: dict) -> bool:
    """规则校验（借鉴 CCL 2025 三重校验的规则版）"""
    opts = q["options"]
    if len(opts) != 4:
        return False
    if any(not o or not o.strip() for o in opts):  # 格式：无空选项
        return False
    if len(set(opts)) != 4:          # 格式：选项无重复
        return False
    if q["answer"] not in opts:      # 格式：答案在选项中
        return False
    for d in opts:                   # 唯一性：干扰项与答案文本不重叠
        if d != q["answer"] and (d in q["answer"] or q["answer"] in d):
            return False
    if any(len(o) > 220 for o in opts):  # 选项长度限制
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=0, help="随机抽 N 篇输出可读文本")
    ap.add_argument("--json", action="store_true", help="全量生成并写入入库 JSON (build/data/questions.json)")
    args = ap.parse_args()
    random.seed(42)  # 固定 seed：全量生成可复现（同 seed 同题库，避免每次随机漂移）

    features = percentile_normalize(json.loads(FEATURES_FILE.read_text(encoding="utf-8")))
    files = sorted(ARTICLES_DIR.rglob("*.txt"))
    all_qs, stats, failures = [], {}, {}
    out = OUT_DIR
    out.mkdir(parents=True, exist_ok=True)

    # 全局译文句池（翻译题干扰项跨篇取材）
    sent_pool = []
    # 全局通假本字池（tongjia 干扰项跨篇取材）
    global_zhengzi = set()
    # 语料字集（③ 干扰项只用语料内出现过的字，滤生僻字）
    corpus_chars = set()
    for f in files:
        a = parse_article(f)
        sent_pool += [s for p in split_paras(a["translation"]) for s in re.split(r"[。！？]", p) if s.strip()]
        corpus_chars.update(re.findall(r"[\u4e00-\u9fff]",
                                       a["original"] + a["annotations_raw"] + a["translation"]))
        for item in parse_annotations(a["annotations_raw"]):
            m = TONGJIA_RE.search(item["text"])
            if m:
                global_zhengzi.add(m.group(1))
    mat = TongjiaMaterial(global_zhengzi, corpus_chars)

    if args.sample:
        # 分层抽样：保证样本含通假/翻译题篇目，其余随机补足
        has_tj, has_fy = set(), set()
        for f in files:
            a = parse_article(f)
            it = parse_annotations(a["annotations_raw"])
            if gen_tongjia(a, it, mat):
                has_tj.add(f)
            if gen_fanyi(a, it, sent_pool):
                has_fy.add(f)
        picked = set()
        if has_tj:
            picked |= set(random.sample(sorted(has_tj), min(3, len(has_tj))))
        if has_fy:
            picked |= set(random.sample(sorted(has_fy - picked), min(5, len(has_fy - picked))))
        rest = random.sample([f for f in files if f not in picked], max(0, args.sample - len(picked)))
        files = list(picked) + rest

    for f in files:
        art = parse_article(f)
        items = parse_annotations(art["annotations_raw"])
        qs = []
        qs += gen_shici(art, items)
        qs += gen_tongjia(art, items, mat)
        qs += gen_fanyi(art, items, sent_pool)
        for q in qs:
            random.shuffle(q["options"])  # 答案位置随机化（answer 为文本值，不受影响）
        qs = [q for q in qs if validate(q)]
        stats[art["title"]] = {t: sum(1 for q in qs if q["type"] == t) for t in ("shici", "tongjia", "fanyi")}
        # 篇内序号 + 标题关联 + 论文难度 D_q = Σw_j·d̂_j / Σw_j
        feat = features.get(art["title"], features.get(art["title_fallback"], {}))
        dhat = [feat.get(k, 0.5) for k in FEATURE_KEYS]
        for i, q in enumerate(qs):
            q["seq"] = i  # 篇内序号（shici → tongjia → fanyi，引文顺序）
            q["title"], q["author"], q["source"] = art["title"], art["author"], art["source"]
            ws = [CRITIC_WEIGHTS[j] for j in q["dims"]]
            q["difficulty"] = round(sum(w * dhat[j] for w, j in zip(ws, q["dims"])) / sum(ws), 3)
            q["q_key"] = compute_q_key(q["title"], q["author"], q["type"], q["stem"], q["answer"])
        all_qs.extend(qs)
        if not qs:
            failures[art["title"]] = f"注释条目 {len(items)} 条"

    (out / "all_questions.json").write_text(json.dumps(all_qs, ensure_ascii=False, indent=1), encoding="utf-8")
    (out / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1), encoding="utf-8")

    if args.json:
        db_json = Path(__file__).resolve().parents[2] / "build" / "data" / "questions.json"
        db_json.parent.mkdir(parents=True, exist_ok=True)
        # 入库字段：answer_index = 正确答案在 options（已洗牌）中的下标；
        # dims 用 CSV（如 "3,4,9"），C++/Dart 两侧 split 即可解析，避免 JSON 解析
        rows = [{
            "title": q["title"], "author": q["author"], "q_type": q["type"],
            "stem": q["stem"], "options": q["options"],
            "answer_index": q["options"].index(q["answer"]),
            "explanation": q["explanation"], "difficulty": q["difficulty"],
            "dims": ",".join(str(d) for d in q["dims"]), "seq": q["seq"],
            "context": q.get("context", ""), "mark_start": q.get("mark_start", -1),
            "mark_len": q.get("mark_len", 0),
            "q_key": q["q_key"],
        } for q in all_qs]
        db_json.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"入库 JSON → {db_json}（{len(rows)} 题）")

    by_type = {}
    for q in all_qs:
        by_type.setdefault(q["type"], []).append(q)
    print(f"总题数 {len(all_qs)} | 覆盖篇数 {sum(1 for v in stats.values() if any(v.values()))}/{len(files)}")
    for t in ("shici", "tongjia", "fanyi"):
        print(f"  {t}: {len(by_type.get(t, []))} 题")
    for t in ("shici", "tongjia"):
        sub = [q for q in all_qs if q["type"] == t]
        covered = sum(1 for q in sub if q["context"])
        print(f"  {t} 带原句(划线): {covered}/{len(sub)}")
    swap_stats = {}
    for q in all_qs:
        if q["type"] == "tongjia":
            key = q.get("_swap", "none")
            swap_stats[key] = swap_stats.get(key, 0) + 1
    print(f"  tongjia 干扰项换质: {swap_stats}")
    if failures:
        print(f"零产出篇目 {len(failures)}：{list(failures)[:10]}")

    if args.sample:
        md = ["# 出题样本抽验\n"]
        for f in files:
            art = parse_article(f)
            # 按 front matter title+author 精确匹配：文件名==title 是命名铁律，
            # 但同名异篇靠括号消歧（六国论（苏辙）等）时 stem ≠ title，不能只比 stem
            art_qs = [q for q in all_qs if q["title"] == art["title"] and q["author"] == art["author"]]
            if not art_qs:
                continue
            md.append(f"\n## {f.stem}（{art_qs[0]['source']}）\n")
            for i, q in enumerate(art_qs, 1):
                opts = "\n".join(f"    {chr(65+j)}. {o}" for j, o in enumerate(q["options"]))
                ans = q["answer"]
                ctx = ""
                if q.get("context"):
                    ctx = q["context"][:q["mark_start"]] + "**" + \
                        q["context"][q["mark_start"]:q["mark_start"] + q["mark_len"]] + \
                        "**" + q["context"][q["mark_start"] + q["mark_len"]:]
                md.append(f"{i}. [{q['type']}] 难度 {q['difficulty']}｜{q['stem']}")
                if ctx:
                    md.append(f"    原句：{ctx}")
                md.append(f"{opts}\n    **答案**：{ans}\n    **解析**：{q['explanation']}\n")
        sample_file = out / "sample_review.md"
        sample_file.write_text("\n".join(md), encoding="utf-8")
        print(f"样本 → {sample_file}")


if __name__ == "__main__":
    main()
