#!/usr/bin/env python3
"""Windows Release 目录关键 DLL 清单 + PE 依赖检查。

用法：
    python scripts/check_windows_dlls.py <flutter_app/build/windows/x64/runner/Release>

行为：
- 必选关键文件缺失即失败。
- 不允许出现 dartjni.dll（未使用的 Android JNI 传递依赖，依赖 jvm.dll）。
- 不允许出现 lib/chinese_core.dll 重复副本；chinese_core.dll 必须且只能有一份（Release 根）。
- 对 Release 根下所有 .exe/.dll 做 PE 导入表扫描：
    * 已随包分发（Release 根下同名文件）→ 通过；
    * api-ms-win-*/ext-ms-* 或 System32/SysWOW64 中存在的系统 DLL → 通过；
    * 其余 → 报“未随包分发的非系统依赖”并失败。
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

try:
    import pefile
except ImportError:  # pragma: no cover - CI 会先 pip install
    print("缺少 pefile，请先执行: python -m pip install pefile", file=sys.stderr)
    sys.exit(2)

REQUIRED = [
    "chinese_classical_rec_sys.exe",
    "flutter_windows.dll",
    "chinese_core.dll",
    "file_selector_windows_plugin.dll",
    "share_plus_plugin.dll",
    "url_launcher_windows_plugin.dll",
    # Flutter 引擎数据文件，缺失同样会导致启动失败。
    "data/icudtl.dat",
    # VC++ 运行库：虽然 CI 的 CRT 复制步骤已逐个校验，这里再作为关键清单兜底。
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "msvcp140.dll",
    "concrt140.dll",
]

FORBIDDEN = [
    # jni 仅 Android 使用；Windows 上带进包会引入 jvm.dll 依赖。
    "dartjni.dll",
]

# 直接按系统 API set 前缀放行；其余系统 DLL 在 Windows 上通过 System32/SysWOW64 存在性判断。
API_SET_PREFIXES = ("api-ms-win-", "ext-ms-")
# VC++ 运行库必须随包分发，不能因为 CI 机器上恰好装了 VS/Redist 就当成系统 DLL 放行。
# 只匹配带版本号的 msvcp/vcruntime/concrt/msvcr（如 msvcp140.dll）；不误伤
# msvcp_win.dll / vcruntime_win.dll 这类 Windows 系统 DLL。
VC_RUNTIME_RE = re.compile(r"^(msvcp|vcruntime|concrt|msvcr)\d")
# 常见 Windows 系统 DLL 兜底名单：即使 System32 扫描因权限/Server 镜像缺少个别文件，
# 也不把这些系统依赖误报为“未随包分发”。
COMMON_SYSTEM_DLLS = {
    "advapi32.dll", "apphelp.dll", "bcrypt.dll", "cfgmgr32.dll", "clbcatq.dll",
    "combase.dll", "comctl32.dll", "comdlg32.dll", "crypt32.dll", "d2d1.dll",
    "d3d11.dll", "d3d12.dll", "d3dcompiler_47.dll", "dbghelp.dll", "dcomp.dll",
    "dwmapi.dll", "dwrite.dll", "dxgi.dll", "dxva2.dll", "evr.dll",
    "gdi32.dll", "gdiplus.dll", "hid.dll", "imm32.dll", "iphlpapi.dll",
    "kernel32.dll", "mf.dll", "mfplat.dll", "mfreadwrite.dll", "mfuuid.dll",
    "mpr.dll", "msimg32.dll", "msvcp_win.dll", "msvcrt.dll", "ncrypt.dll", "netapi32.dll",
    "ntdll.dll", "ole32.dll", "oleaut32.dll", "powrprof.dll", "propsys.dll",
    "psapi.dll", "rpcrt4.dll", "secur32.dll", "setupapi.dll", "shcore.dll",
    "shell32.dll", "shlwapi.dll", "synchronization.dll", "twinapi.dll",
    "ucrtbase.dll", "user32.dll", "userenv.dll", "uxtheme.dll", "vcruntime_win.dll",
    "version.dll",
    "windowscodecs.dll", "winhttp.dll", "wininet.dll", "winmm.dll", "wintrust.dll",
    "wldap32.dll", "ws2_32.dll", "wsock32.dll", "wtsapi32.dll",
    "windows.storage.dll",
}


def _find_windows_system_dlls() -> set[str]:
    result: set[str] = set()
    roots = [os.environ.get("SystemRoot"), os.environ.get("WINDIR")]
    if not any(roots):
        roots = [r"C:\Windows"]
    for root in roots:
        if not root:
            continue
        for sub in ("System32", "SysWOW64"):
            d = Path(root) / sub
            if d.is_dir():
                try:
                    result.update(p.name.lower() for p in d.iterdir()
                                  if p.suffix.lower() == ".dll")
                except OSError:
                    pass
    return result


def _is_vc_runtime(name: str) -> bool:
    return bool(VC_RUNTIME_RE.match(name.lower()))


def _is_system_dll(name: str, system_dlls: set[str]) -> bool:
    lower = name.lower()
    if lower.startswith(API_SET_PREFIXES):
        return True
    if lower in COMMON_SYSTEM_DLLS:
        return True
    return lower in system_dlls


def _pe_dependencies(path: Path) -> set[str]:
    """返回 PE 文件的直接导入 DLL 名（小写），含 delay-load。"""
    deps: set[str] = set()
    pe = pefile.PE(str(path), fast_load=False)
    try:
        for entry in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []) or []:
            if entry.dll:
                deps.add(entry.dll.decode(errors="replace").lower())
        for entry in getattr(pe, "DIRECTORY_ENTRY_DELAY_IMPORT", []) or []:
            if entry.dll:
                deps.add(entry.dll.decode(errors="replace").lower())
    finally:
        pe.close()
    return deps


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    release = Path(sys.argv[1]).resolve()
    if not release.is_dir():
        print(f"Release 目录不存在: {release}", file=sys.stderr)
        return 2

    errors: list[str] = []
    all_files = {p.relative_to(release).as_posix().lower(): p
                 for p in release.rglob("*") if p.is_file()}
    top_level = {p.name.lower(): p
                 for p in release.iterdir() if p.is_file()}

    # ---- 必选清单 ----
    # DLL/exe 必须在 Release 根目录；data/ 下的数据文件允许在子目录。
    for rel in REQUIRED:
        present = rel.lower() in top_level if "/" not in rel else rel.lower() in all_files
        if not present:
            hint = "（须在 Release 根目录）" if "/" not in rel else ""
            errors.append(f"缺少关键文件: {rel}{hint}")

    # ---- 禁入清单 ----
    for rel in FORBIDDEN:
        matches = [p for name, p in all_files.items() if Path(name).name == rel]
        if matches:
            errors.append(f"安装包内不应包含 {rel}: {matches[0]}")

    # ---- chinese_core 唯一性 ----
    core_matches = [p for name, p in all_files.items() if Path(name).name == "chinese_core.dll"]
    if len(core_matches) != 1:
        errors.append(
            f"chinese_core.dll 应为 Release 根目录唯一一份，当前 {len(core_matches)} 份: "
            + ", ".join(str(p) for p in core_matches)
        )
    elif core_matches[0].parent != release:
        errors.append(f"chinese_core.dll 未位于 Release 根目录: {core_matches[0]}")

    # ---- PE 依赖扫描 ----
    system_dlls = _find_windows_system_dlls()
    pe_paths = [p for p in release.iterdir() if p.is_file() and p.suffix.lower() in (".exe", ".dll")]
    for path in sorted(pe_paths):
        try:
            deps = _pe_dependencies(path)
        except Exception as exc:  # noqa: BLE001 - 让 CI 看到具体解析失败
            errors.append(f"无法解析 PE 依赖 {path.name}: {exc}")
            continue
        missing: set[str] = set()
        for dep in deps:
            if dep in top_level:
                continue
            if _is_vc_runtime(dep):
                # VC++ 运行库不随 Windows 提供，必须由安装包自行带上。
                missing.add(dep)
                continue
            if _is_system_dll(dep, system_dlls):
                continue
            missing.add(dep)
        if missing:
            errors.append(f"{path.name} 依赖未随包分发的非系统 DLL: {', '.join(sorted(missing))}")

    if errors:
        print("Windows Release 校验失败：", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"Windows Release 校验通过: {release}")
    print(f"  PE 文件 {len(pe_paths)} 个，系统 DLL 集合 {len(system_dlls)} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
