#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""数据管线卫生测试：共享归一化、建库失败语义、题库生成闸门。

覆盖项：
1. 共享 percentile_normalize 的固定 fixture：P2/P98 裁剪、常量特征 0.5、
   f6/f9 反转、空输入原样返回；
2. init_data.py 与 generate_questions.py 导入同一份 FEATURE_KEYS /
   percentile_normalize（对象同一）；
3. 坏文件导致 init_database 返回 False，目标库逐字节不变、无 <db>.tmp；
4. 重复 q_key 时 generate_questions 以非零码退出，且不写任何题库产物。

用法（必须用仓库 venv；系统 python3 无 numpy）：
    venv/bin/python3 tests/python/test_pipeline_hygiene.py
"""

import contextlib
import hashlib
import io
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_SCRIPTS = ROOT / "scripts" / "project"
sys.path.insert(0, str(PROJECT_SCRIPTS))

import feature_normalization  # noqa: E402  （依赖仓库 venv 的 numpy）
import generate_questions  # noqa: E402
import init_data  # noqa: E402

VALUES = [0.0, 1.0, 2.0, 3.0, 4.0]
# 线性序列 [0,1,2,3,4] 的 P2=0.08、P98=3.92 → 分母 3.84
P2, P98 = 0.08, 3.92


def _expected_norm(value: float) -> float:
    return min(1.0, max(0.0, (value - P2) / (P98 - P2)))


def _assert_close(got: float, want: float, label: str) -> None:
    assert abs(got - want) < 1e-12, f"{label}: {got!r} != {want!r}"


def _fixture() -> dict:
    """5 篇、10 维：f5/f8/f13 常量，f6/f9 同时验证反向。"""
    return {
        f"篇{i}": {
            "f1_avg_sentence_length": VALUES[i],
            "f3_sentence_count": VALUES[::-1][i],
            "f5_function_word_ratio": 2.0,
            "f6_avg_char_log_freq": VALUES[i],
            "f8_tongjiazi_density": 1.5,
            "f9_ppl_ancient": VALUES[::-1][i],
            "f10_ppl_modern": VALUES[i],
            "f11_mattr": VALUES[::-1][i],
            "f12_allusion_density": VALUES[i],
            "f13_semantic_complexity": 0.0,
        }
        for i in range(len(VALUES))
    }


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@contextlib.contextmanager
def _patched(module, **attrs):
    original = {name: getattr(module, name) for name in attrs}
    for name, value in attrs.items():
        setattr(module, name, value)
    try:
        yield
    finally:
        for name, value in original.items():
            setattr(module, name, value)


@contextlib.contextmanager
def _captured():
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        yield out, err


def test_shared_normalization_fixture(tmp_path: Path) -> None:
    """固定 fixture 锁住 P2/P98 裁剪、常量 0.5、f6/f9 反转。"""
    result = feature_normalization.percentile_normalize(_fixture())
    assert list(result) == [f"篇{i}" for i in range(len(VALUES))]
    for i in range(len(VALUES)):
        title = f"篇{i}"
        _assert_close(result[title]["f1_avg_sentence_length"],
                      _expected_norm(VALUES[i]), f"{title} f1")
        _assert_close(result[title]["f3_sentence_count"],
                      _expected_norm(VALUES[::-1][i]), f"{title} f3")
        _assert_close(result[title]["f5_function_word_ratio"], 0.5, f"{title} f5 常量")
        _assert_close(result[title]["f8_tongjiazi_density"], 0.5, f"{title} f8 常量")
        _assert_close(result[title]["f13_semantic_complexity"], 0.5, f"{title} f13 常量")
        _assert_close(result[title]["f6_avg_char_log_freq"],
                      1 - _expected_norm(VALUES[i]), f"{title} f6 反转")
        _assert_close(result[title]["f9_ppl_ancient"],
                      1 - _expected_norm(VALUES[::-1][i]), f"{title} f9 反转")

    empty = {}
    assert feature_normalization.percentile_normalize(empty) == {}


def test_scripts_share_normalization(tmp_path: Path) -> None:
    """两个脚本导入同一对象，而不是各留一份副本。"""
    assert len(feature_normalization.FEATURE_KEYS) == 10
    assert feature_normalization.FEATURE_KEYS[3] == "f6_avg_char_log_freq"
    assert feature_normalization.FEATURE_KEYS[5] == "f9_ppl_ancient"
    for module in (init_data, generate_questions):
        assert module.FEATURE_KEYS is feature_normalization.FEATURE_KEYS, module.__name__
        assert module.percentile_normalize is feature_normalization.percentile_normalize, (
            module.__name__)


def test_missing_front_matter_is_skip_not_error(tmp_path: Path) -> None:
    path = tmp_path / "无元数据.txt"
    path.write_text("没有 front matter 的正文", encoding="utf-8")
    with _captured() as (out, _err):
        assert init_data.parse_text_file(str(path)) is None
    assert str(path) in out.getvalue(), "缺少 front matter 时应打印文件名"


def test_bad_article_fails_before_touching_target(tmp_path: Path) -> None:
    """坏文件让建库在临时库之前失败，目标库逐字节不变。"""
    articles = tmp_path / "anthology"
    articles.mkdir()
    (articles / "坏文.txt").write_bytes(b"\xff\xfe\x00 not utf-8")
    textbook = tmp_path / "textbook"
    textbook.mkdir()
    features_json = tmp_path / "features.json"
    features_json.write_text("{}", encoding="utf-8")

    target = tmp_path / "classical.db"
    target.write_bytes(b"sentinel-target-bytes")
    before = _sha256(target)

    with _patched(init_data, ANTHOLOGY_DIR=str(articles), TEXTBOOK_DIR=str(textbook),
                  FEATURES_FILE=str(features_json)):
        with _captured() as (out, _err):
            ok = init_data.init_database(str(target), None, str(tmp_path / "questions.json"))

    assert ok is False, "坏文件应让 init_database 返回 False"
    assert _sha256(target) == before, "失败后目标库不再是逐字节相同"
    assert not Path(str(target) + ".tmp").exists(), "失败路径残留 <db>.tmp"
    assert "坏文.txt" in out.getvalue(), "失败信息应含文件名"
    assert "utf-8" in out.getvalue(), "失败信息应含原因"


def _write_article_fixture(tmp_path: Path) -> Path:
    articles = tmp_path / "articles"
    articles.mkdir()
    (articles / "测试篇.txt").write_text(
        """---
title: 测试篇
author: 测试
dynasty: 测试
source: textbook
---

【原文】
学而时习之，不亦说乎？有朋自远方来，不亦乐乎？人不知而不愠，不亦君子乎？

【注释】
〔1〕说：喜悦
〔2〕习：温习
〔3〕朋：朋友
〔4〕乐：快乐
〔5〕愠：恼怒

【译文】
学习后按时温习，不也喜悦吗？有志同道合的人从远方来，不也快乐吗？
""",
        encoding="utf-8")
    return articles


def _run_generator(tmp_path: Path, articles: Path, **patched) -> tuple:
    features_json = tmp_path / "features.json"
    features_json.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    db_json = tmp_path / "questions.json"
    old_argv = sys.argv
    sys.argv = ["generate_questions.py", "--json"]
    try:
        with _patched(generate_questions, ARTICLES_DIR=articles,
                      FEATURES_FILE=features_json, OUT_DIR=out_dir,
                      DB_JSON=db_json, **patched):
            with _captured() as (out, err):
                rc = generate_questions.main()
    finally:
        sys.argv = old_argv
    return rc, out.getvalue(), err.getvalue(), out_dir, db_json


def test_duplicate_q_key_rejected_before_artifacts(tmp_path: Path) -> None:
    """全局 q_key 冲突：打印键与题干、非零退出，不写 questions/all_questions。"""
    articles = _write_article_fixture(tmp_path)
    rc, _out, err, out_dir, db_json = _run_generator(
        tmp_path, articles, compute_q_key=lambda *args: "fixed_q_key")

    assert rc != 0, "q_key 重复必须以非零码退出"
    assert "错误: q_key 重复 fixed_q_key" in err, err
    assert "下列句中划线词" in err, "冲突信息应含题干"
    assert not (out_dir / "all_questions.json").exists(), "不应写出 all_questions.json"
    assert not (out_dir / "stats.json").exists(), "不应写出 stats.json"
    assert not db_json.exists(), "不应写出 questions.json"


def test_zero_questions_rejected(tmp_path: Path) -> None:
    """总题数为 0 以非零码退出，且不写题库产物。"""
    articles = tmp_path / "empty_articles"
    articles.mkdir()
    rc, _out, err, out_dir, db_json = _run_generator(tmp_path, articles)

    assert rc != 0, "0 题必须以非零码退出"
    assert "未生成任何题目" in err, err
    assert not (out_dir / "all_questions.json").exists()
    assert not db_json.exists()


def main() -> int:
    tests = [
        test_shared_normalization_fixture,
        test_scripts_share_normalization,
        test_missing_front_matter_is_skip_not_error,
        test_bad_article_fails_before_touching_target,
        test_duplicate_q_key_rejected_before_artifacts,
        test_zero_questions_rejected,
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="pipeline_hygiene_") as td:
        base = Path(td)
        for test in tests:
            case_dir = base / test.__name__
            case_dir.mkdir()
            try:
                test(case_dir)
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
