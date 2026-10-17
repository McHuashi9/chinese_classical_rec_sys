#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""公告同步脚本回归测试。

重点保护：CHANGELOG → announcement.md 同步时，正文“作者的话”不能被覆盖，
且 dry-run / 失败路径都不能修改正式文件。

用法：
    python3 tests/python/test_sync_announcement.py
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "project" / "sync_announcement.sh"

AUTHOR_HEAD = """---
id: v1.5.0-1
---

感谢您使用文言文推荐系统。

这是第一段作者的话。

这是第二段作者的话。
"""

CHANGELOG = """# Changelog

## [Unreleased]

## [1.6.0] - 2026-10-18

### Added

- 新功能甲

### Fixed

- 修复乙

## [1.5.0] - 2026-09-30

### Fixed

- 旧改动
"""

ANNOUNCEMENT = AUTHOR_HEAD + """
## 版本改动

- 旧改动
"""


def _fixture(tmp: Path) -> tuple[Path, Path]:
    """在临时目录搭一个最小仓库，复制脚本并写入测试数据。"""
    script = tmp / "scripts" / "project" / "sync_announcement.sh"
    script.parent.mkdir(parents=True)
    shutil.copy2(SCRIPT, script)

    announcement = tmp / "flutter_app" / "assets" / "data" / "announcement.md"
    announcement.parent.mkdir(parents=True)
    announcement.write_text(ANNOUNCEMENT, encoding="utf-8")
    (tmp / "CHANGELOG.md").write_text(CHANGELOG, encoding="utf-8")
    return script, announcement


def _run(script: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def test_sync_preserves_author_text(tmp: Path) -> None:
    script, announcement = _fixture(tmp)
    proc = _run(script, "1.6.0")
    assert proc.returncode == 0, f"{proc.stdout}\n{proc.stderr}"

    text = announcement.read_text(encoding="utf-8")
    assert "id: v1.6.0-1" in text
    assert AUTHOR_HEAD.split("---\n", 2)[2].strip() in text
    assert "- 旧改动" not in text
    assert "- 新功能甲\n- 修复乙" in text
    assert not Path(str(announcement) + ".tmp").exists()


def test_dry_run_reports_diff_without_writing(tmp: Path) -> None:
    script, announcement = _fixture(tmp)
    before = announcement.read_bytes()
    proc = _run(script, "1.6.0", "--dry-run")
    assert proc.returncode == 0, f"{proc.stdout}\n{proc.stderr}"
    assert "announcement.md (before)" in proc.stdout
    assert "+- 新功能甲" in proc.stdout
    assert "announcement.md not written" in proc.stdout
    assert announcement.read_bytes() == before
    assert not Path(str(announcement) + ".tmp").exists()


def test_missing_changelog_section_leaves_file_unchanged(tmp: Path) -> None:
    script, announcement = _fixture(tmp)
    before = announcement.read_bytes()
    proc = _run(script, "9.9.9")
    assert proc.returncode == 1
    assert "CHANGELOG section [9.9.9] not found" in proc.stderr
    assert announcement.read_bytes() == before
    assert not Path(str(announcement) + ".tmp").exists()


def test_missing_marker_appends_changes_after_author_text(tmp: Path) -> None:
    script, announcement = _fixture(tmp)
    announcement.write_text(AUTHOR_HEAD, encoding="utf-8")
    proc = _run(script, "1.6.0")
    assert proc.returncode == 0, f"{proc.stdout}\n{proc.stderr}"

    text = announcement.read_text(encoding="utf-8")
    assert "这是第二段作者的话。" in text
    author_pos = text.index("这是第二段作者的话。")
    marker_pos = text.index("## 版本改动")
    assert author_pos < marker_pos
    assert "- 新功能甲\n- 修复乙" in text


def main() -> int:
    tests = [
        test_sync_preserves_author_text,
        test_dry_run_reports_diff_without_writing,
        test_missing_changelog_section_leaves_file_unchanged,
        test_missing_marker_appends_changes_after_author_text,
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="sync_announcement_") as td:
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
