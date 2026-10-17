#!/usr/bin/env python3
"""从 bridge/error_codes.def 生成 Dart BridgeError 常量。

用法:
    python3 scripts/project/generate_bridge_error_codes.py
    python3 scripts/project/generate_bridge_error_codes.py --check
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEF_PATH = ROOT / "bridge" / "error_codes.def"
OUT_PATH = ROOT / "flutter_app" / "lib" / "bridge" / "bridge_error_codes.g.dart"

_LINE = re.compile(
    r'^\s*BRIDGE_ERROR\(\s*([A-Z][A-Z0-9_]*)\s*,\s*(-?\d+)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)\s*$'
)


def dart_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dart_field(name: str) -> str:
    parts = name.lower().split('_')
    return parts[0] + ''.join(part.capitalize() for part in parts[1:])


def parse_def() -> list[tuple[str, int, str]]:
    entries: list[tuple[str, int, str]] = []
    for line in DEF_PATH.read_text(encoding="utf-8").splitlines():
        m = _LINE.match(line)
        if m:
            entries.append((m.group(1), int(m.group(2)), m.group(3)))
    if not entries:
        raise SystemExit(f"未在 {DEF_PATH} 找到 BRIDGE_ERROR(...) 条目")
    return entries


def render(entries: list[tuple[str, int, str]]) -> str:
    field_names = "".join(
        f"  static const int {dart_field(name)} = {value};\n" for name, value, _ in entries
    )
    names = ",\n".join(
        f"    {value}: 'BRIDGE_{name}'" for name, value, _ in entries
    )
    messages = ",\n".join(
        f"    {value}: {dart_string(desc)}" for name, value, desc in entries
    )
    return f'''// GENERATED CODE - DO NOT EDIT.
// 唯一源: bridge/error_codes.def
// 重新生成: python3 scripts/project/generate_bridge_error_codes.py

/// C ABI 错误码（数值与名称均从 [bridge/error_codes.def] 生成）。
abstract final class BridgeError {{
{field_names}
  /// code -> 稳定符号名，用于日志/异常文本。
  static const Map<int, String> names = {{
{names},
  }};

  /// code -> 中文说明。
  static const Map<int, String> messages = {{
{messages},
  }};

  static String nameOf(int code) => names[code] ?? 'BRIDGE_ERR_UNKNOWN($code)';
  static String messageOf(int code) => messages[code] ?? '未知错误';
}}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只校验生成文件是否最新")
    args = parser.parse_args()

    expected = render(parse_def())
    if args.check:
        actual = OUT_PATH.read_text(encoding="utf-8") if OUT_PATH.exists() else ""
        if actual != expected:
            print(
                f"{OUT_PATH.relative_to(ROOT)} 已过期，请运行 "
                "python3 scripts/project/generate_bridge_error_codes.py",
                file=sys.stderr,
            )
            return 1
        print(f"{OUT_PATH.relative_to(ROOT)} 与 bridge/error_codes.def 一致")
        return 0

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(expected, encoding="utf-8")
    print(f"已生成 {OUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
