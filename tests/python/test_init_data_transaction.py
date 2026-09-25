#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""init_data.py 建库事务 / 原子替换端到端测试。

覆盖项：
1. 成功建库：integrity_check=ok、foreign_key_check 0 行、篇数/题数/user_version
   正确，并与 build/data/classical.db 逐行对拍 id→title、id→q_key、text_id 三向；
2. 负向：注入「文章集截断 + 写入中途抛错」后，目标库 sha256 与运行前逐字节相同；
3. 负向：失败后库内不存在「新文本 + 旧题库」组合，且不残留 <db>.tmp；
4. 负向：目标库原本不存在时，失败不产生任何库文件；
5. check_content_db.py 新增的 foreign_key_check 闸门：悬空外键库必须 FAIL，
   干净库必须打印 OK 5/6 且整体 PASS；
6. CLI 入口：--questions-json 正向 + 未显式给出时默认查找行为向后兼容。

用法（必须用仓库 venv；系统 python3 无 numpy）：
    venv/bin/python3 tests/python/test_init_data_transaction.py
全部库文件都在临时目录中生成，不触碰 build/data/、flutter_app/assets/data/ 与
classical_data/；也可在装了 pytest 的环境下直接 `pytest tests/python/`。
"""

import contextlib
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_SCRIPTS = ROOT / "scripts" / "project"
INIT_DATA_PY = PROJECT_SCRIPTS / "init_data.py"
CHECK_DB_PY = PROJECT_SCRIPTS / "check_content_db.py"
QJSON = ROOT / "build/data/questions.json"
ID_MAP_JSON = ROOT / "build/data/question_id_map.json"
REFERENCE_DB = ROOT / "build/data/classical.db"

sys.path.insert(0, str(PROJECT_SCRIPTS))
import init_data  # noqa: E402  （依赖仓库 venv 的 numpy）

# 注入用：把文章集截断到该篇数（模拟增删文章导致的 text_id 失配）
INJECT_TEXT_LIMIT = 250


@contextlib.contextmanager
def _repo_cwd():
    """init_data 用相对路径读 articles//features.json，测试期间切到仓库根。"""
    old = os.getcwd()
    os.chdir(ROOT)
    try:
        yield
    finally:
        os.chdir(old)


@contextlib.contextmanager
def _ro(db_path):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        yield conn
    finally:
        conn.close()


class _JsonLoadBoom:
    """init_data.json 替身：dumps 正常，第 fail_on_call 次 load 抛错以注入写入中途故障。

    init_database 内的 json.load 调用序：1) load_features()（try 之前）
    2) questions.json（文本已 INSERT、questions 已 DELETE，位于 try 之内）。
    """

    def __init__(self, real_json, fail_on_call=2):
        self._real = real_json
        self._fail_on_call = fail_on_call
        self._calls = 0

    def load(self, *args, **kwargs):
        self._calls += 1
        if self._calls >= self._fail_on_call:
            raise RuntimeError("注入故障：题库读取失败（写入中途）")
        return self._real.load(*args, **kwargs)

    def dumps(self, *args, **kwargs):
        return self._real.dumps(*args, **kwargs)


@contextlib.contextmanager
def _inject_write_failure(text_limit=INJECT_TEXT_LIMIT):
    """替换 init_data.load_texts（截断文章集）与 init_data.json（load 抛错）。"""
    orig_load_texts = init_data.load_texts
    orig_json = init_data.json

    def truncating_load_texts():
        texts = orig_load_texts()
        keys = list(texts.keys())[:text_limit]
        assert len(keys) < len(texts), "注入前提：文章集必须变小"
        return {k: texts[k] for k in keys}

    init_data.load_texts = truncating_load_texts
    init_data.json = _JsonLoadBoom(orig_json)
    try:
        yield
    finally:
        init_data.load_texts = orig_load_texts
        init_data.json = orig_json


def _load_id_map():
    if ID_MAP_JSON.is_file():
        return json.loads(ID_MAP_JSON.read_text(encoding="utf-8"))
    return None


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _blob_short_hash(path: Path) -> str:
    """与 check_content_db.git_blob_short_hash 等价（git hash-object 前 7 位）。"""
    data = path.read_bytes()
    return hashlib.sha1(b"blob %d\x00" % len(data) + data).hexdigest()[:7]


def _counts(db_path) -> tuple:
    with _ro(db_path) as conn:
        return (
            conn.execute("SELECT COUNT(*) FROM classical_text").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM questions").fetchone()[0],
            conn.execute("PRAGMA user_version").fetchone()[0],
        )


def _snapshot(db_path):
    """(id→title, id→q_key, id→text_id) 三个有序快照。"""
    with _ro(db_path) as conn:
        texts = conn.execute("SELECT id, title FROM classical_text ORDER BY id").fetchall()
        qkeys = conn.execute("SELECT id, q_key FROM questions ORDER BY id").fetchall()
        text_ids = conn.execute("SELECT id, text_id FROM questions ORDER BY id").fetchall()
    return texts, qkeys, text_ids


def _assert_clean(db_path, label: str) -> None:
    with _ro(db_path) as conn:
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        fk_rows = conn.execute("PRAGMA foreign_key_check").fetchall()
        version = conn.execute("PRAGMA user_version").fetchone()[0]
    assert integrity == "ok", f"{label}: integrity_check={integrity}"
    assert not fk_rows, f"{label}: 悬空外键 {len(fk_rows)} 行，样例 {fk_rows[:3]}"
    assert version == 1, f"{label}: user_version={version}"


def _assert_matches_reference(db_path, label: str) -> None:
    """与入库库 build/data/classical.db 逐行对拍三向映射。"""
    if not REFERENCE_DB.is_file():
        print(f"  跳过与参考库对拍（缺少 {REFERENCE_DB}）")
        return
    assert _counts(db_path) == _counts(REFERENCE_DB), (
        f"{label}: 计数/版本与参考库不一致 {_counts(db_path)} vs {_counts(REFERENCE_DB)}")
    mine = _snapshot(db_path)
    ref = _snapshot(REFERENCE_DB)
    for name, rows_mine, rows_ref in zip(
            ("id→title", "id→q_key", "id→text_id"), mine, ref):
        assert len(rows_mine) == len(rows_ref), (
            f"{label}: {name} 行数 {len(rows_mine)} != 参考 {len(rows_ref)}")
        mismatches = [(a, b) for a, b in zip(rows_mine, rows_ref) if a != b]
        assert not mismatches, f"{label}: {name} 失配 {len(mismatches)} 行，样例 {mismatches[:3]}"


def _build_reference_copy(tmp_path: Path, name: str = "base.db") -> Path:
    """用 init_data 正常建一个库（作为后续负向用例的运行前状态）。"""
    db = tmp_path / name
    with _repo_cwd():
        ok = init_data.init_database(str(db), _load_id_map(), str(QJSON))
    assert ok is True, "基线库构建失败"
    _assert_clean(db, "基线库")
    return db


def _run_check_content_db(db_path: Path, ver_path: Path):
    return subprocess.run(
        [sys.executable, str(CHECK_DB_PY), "--db", str(db_path),
         "--questions-json", str(QJSON), "--db-version", str(ver_path)],
        cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8")


def test_success_build_and_match_reference(tmp_path):
    """成功建库正确，且与入库库三向映射 0 失配。"""
    db = tmp_path / "success.db"
    with _repo_cwd():
        ok = init_data.init_database(str(db), _load_id_map(), str(QJSON))
    assert ok is True, "建库返回 False"
    assert db.is_file(), "目标库不存在"
    assert not Path(str(db) + ".tmp").exists(), "成功路径残留 <db>.tmp"
    _assert_clean(db, "成功建库")
    n_text, n_q, _ = _counts(db)
    assert n_text > 0 and n_q > 0, f"空库: {n_text} 篇 / {n_q} 题"
    _assert_matches_reference(db, "成功建库")


def test_failure_leaves_target_byte_identical(tmp_path):
    """注入失败后目标库 sha256 逐字节不变，且无「新文本 + 旧题库」组合。"""
    base = _build_reference_copy(tmp_path)
    target = tmp_path / "target.db"
    target.write_bytes(base.read_bytes())

    before_sha = _sha256(target)
    before_snapshot = _snapshot(target)
    before_counts = _counts(target)

    with _repo_cwd(), _inject_write_failure():
        ok = init_data.init_database(str(target), _load_id_map(), str(QJSON))

    assert ok is False, "注入故障后 init_database 应返回 False"
    assert _sha256(target) == before_sha, "失败后目标库不再是逐字节相同"
    assert _counts(target) == before_counts, "失败后计数发生变化"
    assert _snapshot(target) == before_snapshot, "失败后内容发生变化"
    _assert_clean(target, "失败后的目标库")

    # 语义断言：既没有截断成 250 篇，也没有悬空 text_id（即无坏库组合）
    with _ro(target) as conn:
        dangling = conn.execute(
            "SELECT COUNT(*) FROM questions WHERE text_id NOT IN "
            "(SELECT id FROM classical_text)").fetchone()[0]
    assert dangling == 0, f"失败后出现 {dangling} 行悬空 text_id"
    assert _counts(target)[0] != INJECT_TEXT_LIMIT, "失败后留下了注入的新文本"
    assert not Path(str(target) + ".tmp").exists(), "失败路径残留 <db>.tmp"


def test_failure_on_absent_target_creates_nothing(tmp_path):
    """目标库原本不存在时，失败不产生任何库文件（含 .tmp）。"""
    target = tmp_path / "absent.db"
    assert not target.exists()
    with _repo_cwd(), _inject_write_failure():
        ok = init_data.init_database(str(target), _load_id_map(), str(QJSON))
    assert ok is False, "注入故障后 init_database 应返回 False"
    assert not target.exists(), "失败后不应创建目标库"
    assert not Path(str(target) + ".tmp").exists(), "失败后不应残留 <db>.tmp"


def test_cli_questions_json_and_default_lookup(tmp_path):
    """CLI：--questions-json 锚定题库；未给出时默认 build/data/questions.json 兼容。"""
    id_map_arg = ["--id-map", str(ID_MAP_JSON)] if ID_MAP_JSON.is_file() else []
    ref_q = _counts(REFERENCE_DB)[1] if REFERENCE_DB.is_file() else None

    # 1) 显式 --questions-json
    db_explicit = tmp_path / "cli_explicit.db"
    proc = subprocess.run(
        [sys.executable, str(INIT_DATA_PY), "--db", str(db_explicit),
         "--questions-json", str(QJSON), *id_map_arg],
        cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8")
    assert proc.returncode == 0, f"CLI 显式题库失败:\n{proc.stdout}\n{proc.stderr}"
    assert "数据初始化成功！" in proc.stdout
    _assert_clean(db_explicit, "CLI 显式题库")

    # 2) 未给出 --questions-json：自定义 --db 仍从默认 build/data 取题库（向后兼容）
    db_default = tmp_path / "sub" / "cli_default.db"
    proc = subprocess.run(
        [sys.executable, str(INIT_DATA_PY), "--db", str(db_default), *id_map_arg],
        cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8")
    assert proc.returncode == 0, f"CLI 默认题库失败:\n{proc.stdout}\n{proc.stderr}"
    _assert_clean(db_default, "CLI 默认题库")
    if ref_q is not None:
        assert _counts(db_default)[1] == ref_q, "默认题库查找行为发生变化"
        assert f"题库导入: {ref_q} 题" in proc.stdout, proc.stdout

    # 3) 显式指向不存在的题库：必须失败，且不产生目标库（不再静默产出无题库库）
    db_missing = tmp_path / "cli_missing.db"
    proc = subprocess.run(
        [sys.executable, str(INIT_DATA_PY), "--db", str(db_missing),
         "--questions-json", str(tmp_path / "no_such_questions.json"), *id_map_arg],
        cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8")
    assert proc.returncode == 1, f"显式题库缺失应失败:\n{proc.stdout}\n{proc.stderr}"
    assert "题库文件不存在" in proc.stdout, proc.stdout
    assert not db_missing.exists(), "题库缺失时不应产生目标库"
    assert not Path(str(db_missing) + ".tmp").exists(), "题库缺失时不应残留 <db>.tmp"


def test_check_content_db_fk_gate(tmp_path):
    """check_content_db：干净库 6/6 全绿；悬空外键库必须在 fk 闸门 FAIL。"""
    base = _build_reference_copy(tmp_path)

    # 干净库 + 正确 blob hash → 全绿
    ver_ok = tmp_path / "db_version_ok.txt"
    ver_ok.write_text(f"202609252100-{_blob_short_hash(base)}\n", encoding="utf-8")
    proc = _run_check_content_db(base, ver_ok)
    assert proc.returncode == 0, f"干净库应通过:\n{proc.stdout}\n{proc.stderr}"
    assert "OK 5/6 外键完整性" in proc.stdout, proc.stdout
    assert "PASS: 内容库发布校验通过" in proc.stdout, proc.stdout

    # 制造悬空外键：删掉一篇文本，其题目 text_id 悬空（题数不变，前面闸门仍通过）
    corrupt = tmp_path / "corrupt.db"
    corrupt.write_bytes(base.read_bytes())
    conn = sqlite3.connect(str(corrupt))
    conn.execute("PRAGMA foreign_keys = OFF")
    conn.execute("DELETE FROM classical_text WHERE id = "
                 "(SELECT MIN(id) FROM classical_text)")
    conn.commit()
    conn.close()
    with _ro(corrupt) as ro:
        assert ro.execute("PRAGMA foreign_key_check").fetchall(), "坏库样本未产生悬空外键"

    ver_bad = tmp_path / "db_version_bad.txt"
    ver_bad.write_text(f"202609252100-{_blob_short_hash(corrupt)}\n", encoding="utf-8")
    proc = _run_check_content_db(corrupt, ver_bad)
    assert proc.returncode == 1, f"悬空外键库必须 FAIL:\n{proc.stdout}\n{proc.stderr}"
    assert "悬空外键" in proc.stderr, proc.stderr
    assert "OK 4/6" in proc.stdout, "fk 闸门应位于题数闸门之后"


def main() -> int:
    if not QJSON.is_file():
        print(f"FAIL: 缺少题库文件 {QJSON}", file=sys.stderr)
        return 2
    tests = [
        test_success_build_and_match_reference,
        test_failure_leaves_target_byte_identical,
        test_failure_on_absent_target_creates_nothing,
        test_cli_questions_json_and_default_lookup,
        test_check_content_db_fk_gate,
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="init_data_tx_") as td:
        tmp_path = Path(td)
        for test in tests:
            try:
                test(tmp_path)
            except AssertionError as e:
                failures.append(test.__name__)
                print(f"FAIL {test.__name__}: {e}", file=sys.stderr)
            else:
                print(f"PASS {test.__name__}")
    if failures:
        print(f"FAILED: {', '.join(failures)}", file=sys.stderr)
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
