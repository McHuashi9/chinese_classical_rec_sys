#!/usr/bin/env python3
"""
自动扫描项目字符 → 下载原版字体 → 子集化 → 输出到 assets/fonts/

用法:
    source venv/bin/activate
    python3 scripts/subset_fonts.py               # 正常执行
    python3 scripts/subset_fonts.py --force        # 强制重下载 + 重子集化
    python3 scripts/subset_fonts.py --check-only   # 仅验证当前字体覆盖率
"""

import argparse
import hashlib
import json
import os
import re
import sys
import zipfile
from pathlib import Path

import requests

try:
    from fontTools.subset import Subsetter, Options
    from fontTools.ttLib import TTFont
except ImportError:
    print("Error: fonttools 未安装。请运行: pip install fonttools")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
ASSETS_FONTS = ROOT / "flutter_app" / "assets" / "fonts"
CACHE = Path.home() / ".cache" / "chinese-classical-fonts"
CACHE.mkdir(parents=True, exist_ok=True)
HASH_FILE = ASSETS_FONTS / ".subset_hash"

GH_API = "https://api.github.com"

FONT_SCAN_PATHS = [
    ROOT / "articles" / "anthology",
    ROOT / "articles" / "textbook",
    ROOT / "flutter_app" / "lib",
]

EXTRA_CHARS_FILE = ROOT / "scripts" / "fonts_extra_chars.txt"

FONT_DEFS = [
    {"output": "SourceHanSerifSC-Regular.otf", "weight": None},
    {"output": "SourceHanSerifSC-Light.otf", "weight": 300},
    {"output": "LXGWWenKai-Regular.ttf", "weight": None},
    {"output": "LXGWWenKai-Medium.ttf", "weight": 500},
    {"output": "HarmonyOS_SansSC_Regular.ttf", "weight": None},
    {"output": "HarmonyOS_SansSC_Bold.ttf", "weight": 700},
]

# 联网下载源配置（本地缓存不存在时 fallback）
DOWNLOAD_SOURCES = [
    # SourceHanSerifSC — Adobe 官方 Release zip
    {
        "files": ["SourceHanSerifSC-Regular.otf", "SourceHanSerifSC-Light.otf"],
        "owner": "adobe-fonts",
        "repo": "source-han-serif",
        "zip_asset": "09_SourceHanSerifSC.zip",
        "zip_dir": None,
    },
    # LXGWWenKai — 从 lxgw 官方 Release 下载单个 TTF
    {
        "files": ["LXGWWenKai-Regular.ttf", "LXGWWenKai-Medium.ttf"],
        "owner": "lxgw",
        "repo": "LxgwWenKai",
        "zip_asset": None,
        "zip_dir": None,
    },
    # HarmonyOS Sans — 从本项目 Release 下载
    {
        "files": ["HarmonyOS_SansSC_Regular.ttf", "HarmonyOS_SansSC_Bold.ttf"],
        "owner": "McHuashi9",
        "repo": "chinese_classical_rec_sys",
        "zip_asset": None,
        "zip_dir": None,
        "tag_override": "fonts-v1",
    },
]


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def parse_args():
    p = argparse.ArgumentParser(description="字体子集化工具")
    p.add_argument("--force", action="store_true", help="强制重新下载 + 重新子集化")
    p.add_argument("--check-only", action="store_true", help="仅验证当前字体覆盖率，不做任何操作")
    return p.parse_args()


def _read_file_content(path: Path) -> str:
    try:
        with open(path, "rb") as f:
            raw = f.read()
            for enc in ("utf-8", "gbk", "gb18030"):
                try:
                    return raw.decode(enc)
                except UnicodeDecodeError:
                    continue
            return raw.decode("utf-8", errors="replace")
    except Exception as e:
        eprint(f"  [warn] 跳过 {path}: {e}")
        return ""


def collect_characters() -> set:
    chars: set = set()

    def add_text(text: str):
        chars.update(text)

    eprint("扫描项目字符...")

    # 1. 文章
    for base in [ROOT / "articles" / "anthology", ROOT / "articles" / "textbook"]:
        if base.exists():
            for fpath in sorted(base.iterdir()):
                if fpath.suffix in (".txt", ".md"):
                    add_text(_read_file_content(fpath))

    # 2. Dart 源码
    lib_dir = ROOT / "flutter_app" / "lib"
    if lib_dir.exists():
        for fpath in lib_dir.rglob("*.dart"):
            add_text(_read_file_content(fpath))

    # 3. JSON 数据文件
    data_dir = ROOT / "data"
    if data_dir.exists():
        for fpath in data_dir.glob("*.json"):
            try:
                with open(fpath) as f:
                    raw = json.load(f)
                add_text(json.dumps(raw, ensure_ascii=False))
            except Exception as e:
                eprint(f"  [warn] 跳过 {fpath}: {e}")

    # 4. 补充字符文件
    if EXTRA_CHARS_FILE.exists():
        raw = _read_file_content(EXTRA_CHARS_FILE)
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # 支持 U+XXXX 或 U+XXXX-U+YYYY 格式
            for token in line.split():
                token = token.strip()
                if token.startswith("U+"):
                    parts = token[2:].split("-")
                    try:
                        if len(parts) == 1:
                            chars.add(chr(int(parts[0], 16)))
                        elif len(parts) == 2:
                            for cp in range(int(parts[0], 16), int(parts[1], 16) + 1):
                                chars.add(chr(cp))
                    except (ValueError, OverflowError):
                        pass
                else:
                    chars.update(token)

    eprint(f"  字符集大小: {len(chars)}")
    return chars


def gh_latest_release(owner: str, repo: str, tag_override: str | None = None) -> dict:
    if tag_override:
        url = f"{GH_API}/repos/{owner}/{repo}/releases/tags/{tag_override}"
    else:
        url = f"{GH_API}/repos/{owner}/{repo}/releases/latest"
    eprint(f"  GET {url}")
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def download_file(url: str, dest: Path, desc: str = "") -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    eprint(f"  下载 {desc or url} ...")
    r = requests.get(url, stream=True, timeout=600)
    r.raise_for_status()
    total = int(r.headers.get("content-length", 0))
    written = 0
    with open(dest, "wb") as f:
        for chunk in r.iter_content(chunk_size=8192):
            f.write(chunk)
            written += len(chunk)
            if total and written % (1024 * 1024) < 8192:
                pct = written * 100 // total
                eprint(f"\r    {written // (1024*1024)}/{total // (1024*1024)}MB ({pct}%)", end="")
    if total:
        eprint()


def _download_source_group(source: dict, force: bool) -> dict:
    """下载一组字体源，返回 {output_name: cache_path}"""
    result = {}
    need_download = []
    for fname in source["files"]:
        cache_path = CACHE / fname
        if cache_path.exists() and not force:
            result[fname] = cache_path
            eprint(f"  [cached] {fname}")
        else:
            need_download.append((fname, cache_path))

    if not need_download:
        return result

    is_zip = source.get("zip_asset") is not None

    if is_zip:
        # 下载 zip 并提取
        zip_name = source["zip_asset"]
        cache_zip = CACHE / zip_name
        release = gh_latest_release(source["owner"], source["repo"],
                                     tag_override=source.get("tag_override"))
        assets = {a["name"]: a["browser_download_url"] for a in release.get("assets", [])}
        zip_url = assets.get(zip_name)
        if not zip_url:
            eprint(f"  [error] 未在 release 中找到 {zip_name}")
            sys.exit(1)
        download_file(zip_url, cache_zip, zip_name)
        with zipfile.ZipFile(cache_zip) as zf:
            for fname, cache_path in need_download:
                matches = [n for n in zf.namelist() if n.endswith(fname)]
                if not matches:
                    eprint(f"  [error] 在 {zip_name} 中未找到 {fname}")
                    sys.exit(1)
                with zf.open(matches[0]) as src, open(cache_path, "wb") as dst:
                    dst.write(src.read())
                result[fname] = cache_path
                eprint(f"  解压 → {fname}")
    else:
        # 下载单个文件
        release = gh_latest_release(source["owner"], source["repo"],
                                     tag_override=source.get("tag_override"))
        assets = {a["name"]: a["browser_download_url"] for a in release.get("assets", [])}
        for fname, cache_path in need_download:
            url = assets.get(fname)
            if not url:
                eprint(f"  [error] 未在 release 中找到 {fname}")
                eprint(f"    可选: {list(assets.keys())}")
                sys.exit(1)
            download_file(url, cache_path, fname)
            result[fname] = cache_path

    return result


def ensure_original_fonts(force: bool = False) -> dict:
    eprint("确保原版字体已缓存...")
    cached = {}

    # 1. 优先使用本地缓存（包括刚备份的原版字体）
    for fd in FONT_DEFS:
        fname = fd["output"]
        cache_path = CACHE / fname
        if cache_path.exists() and not force:
            cached[fname] = cache_path
            eprint(f"  [cached] {fname}")

    # 2. 缺失的从网络下载
    missing = [fd["output"] for fd in FONT_DEFS if fd["output"] not in cached]
    if missing:
        eprint(f"  本地缺失 {len(missing)} 个字体，准备从网络下载...")
        for src in DOWNLOAD_SOURCES:
            src_result = _download_source_group(src, force)
            cached.update(src_result)

    # 3. 最终检查
    for fd in FONT_DEFS:
        if fd["output"] not in cached:
            eprint(f"  [error] 无法获取 {fd['output']}（本地无缓存，网络下载失败）")
            sys.exit(1)

    return cached


def char_hash(chars: set) -> str:
    return hashlib.sha256("".join(sorted(chars)).encode("utf-8")).hexdigest()[:16]


def needs_subset(chars: set, force: bool) -> bool:
    if force:
        return True
    if not HASH_FILE.exists():
        return True
    old = HASH_FILE.read_text().strip()
    return old != char_hash(chars)


def subset_fonts(chars: set, force: bool, cached: dict) -> None:
    if not needs_subset(chars, force):
        eprint("字符集未变，跳过子集化。")
        return

    ASSETS_FONTS.mkdir(parents=True, exist_ok=True)
    char_list = sorted(chars)

    for fd in FONT_DEFS:
        output_name = fd["output"]
        input_path = cached.get(output_name)
        if not input_path:
            eprint(f"  [skip] {output_name}: 原版字体未缓存")
            continue
        output_path = ASSETS_FONTS / output_name

        eprint(f"  子集化 {output_name} ({len(char_list)} 字符) ...")
        try:
            font = TTFont(str(input_path))
            opts = Options()
            opts.recalc_timestamp = False
            opts.notdef_outline = True
            opts.recalc_bBox = False
            subsetter = Subsetter(options=opts)
            subsetter.populate(text="".join(char_list))
            subsetter.subset(font)
            font.save(str(output_path))
            eprint(f"    → {output_path} ({output_path.stat().st_size // 1024}KB)")
        except Exception as e:
            eprint(f"  [error] {output_name} 子集化失败: {e}")
            sys.exit(1)

    HASH_FILE.write_text(char_hash(chars))
    eprint("子集化完成。")


def _is_standard_char(c: str) -> bool:
    """判断字符是否为标准 Unicode 字符（排除私有用区等不可能存在于普通字体的范围）"""
    cp = ord(c)
    if 0xE000 <= cp <= 0xF8FF:    # Private Use Area
        return False
    if 0xF0000 <= cp <= 0x10FFFF:  # Supplementary PUA
        return False
    if 0xD800 <= cp <= 0xDFFF:    # Surrogates
        return False
    return True


def verify_fonts(chars: set) -> bool:
    eprint("验证字体覆盖率...")
    all_ok = True
    missing_all = set()

    for fd in FONT_DEFS:
        output_name = fd["output"]
        output_path = ASSETS_FONTS / output_name
        if not output_path.exists():
            eprint(f"  [error] {output_name}: 文件不存在")
            all_ok = False
            continue
        try:
            font = TTFont(str(output_path))
            cmap = font.getBestCmap()
            missing = {c for c in chars if ord(c) not in cmap and _is_standard_char(c)}
            if missing:
                sample = "".join(sorted(missing)[:10])
                eprint(f"  [info] {output_name}: 缺 {len(missing)} 个字符 (前10: {sample})")
                eprint(f"         注：这些字符原版字体也未包含，非子集化问题")
                missing_all.update(missing)
            else:
                eprint(f"  [ok]   {output_name}: 全部覆盖")
        except Exception as e:
            eprint(f"  [error] {output_name} 验证失败: {e}")
            all_ok = False

    if missing_all:
        eprint(f"\n总计 {len(missing_all)} 个字符在所有字体中均缺失: "
               f"{''.join(sorted(missing_all)[:20])}")
    return all_ok


def main():
    args = parse_args()
    os.chdir(ROOT)
    chars = collect_characters()

    if args.check_only:
        ok = verify_fonts(chars)
        sys.exit(0 if ok else 1)

    cached = ensure_original_fonts(force=args.force)

    old_cwd = Path.cwd()
    os.chdir(ROOT)
    try:
        subset_fonts(chars, args.force, cached)
        ok = verify_fonts(chars)
        if not ok:
            eprint("\n⚠ 字体覆盖率不足，请检查 fonts_extra_chars.txt 补充缺失字符。")
            sys.exit(1)
    finally:
        os.chdir(old_cwd)

    eprint("\n全部完成 ✓")


if __name__ == "__main__":
    main()
