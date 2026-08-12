<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/C++-17-00599C?logo=c%2B%2B" alt="C++17">
  <img src="https://img.shields.io/badge/Linux-✓-FCC624?logo=linux" alt="Linux">
  <img src="https://img.shields.io/badge/Windows-✓-0078D6?logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Android-✓-3DDC84?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/iOS-needs%20help-999999?logo=apple" alt="iOS">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<h1 align="center">古文推荐系统</h1>

<p align="center">
  <strong>基于知识追踪模型的文言文个性化学习推荐系统</strong><br>
  Flutter Desktop (Linux/Windows) + Android/iOS · C++ 引擎 · Python 数据管线
</p>

---

## 目录

- [项目简介](#项目简介)
- [算法与论文](#算法与论文)
- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [项目架构](#项目架构)
- [贡献](#贡献)
- [许可](#许可)

---

## 项目简介

这是一个面向文言文学习者的个性化阅读推荐工具。它不依赖简单的规则或标签分类，而是通过**知识追踪模型**建模学习者的古文能力状态，结合**多维文本特征**（字频、通假字密度、典故密度、语义复杂度等），实现"i+1"难度递进推荐。

---

## 算法与论文

本项目基于一篇暂未公开的论文，将古文能力分解为字词、语法、典故、修辞等维度。旨在为读者推荐难度略高于当前能力水平的文章。

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 古文库 | 270 篇古文分页浏览，搜索作者/标题，已读/未读标记 |
| 个性推荐 | 高斯 i+1 推荐引擎，推荐数量可调 |
| 阅读器 | 乌丝栏版框、8 档字号、计时器、键盘翻页、阅读锁定 |
| 能力雷达 | 10 维能力雷达图 + 综合评分，追踪学习成长 |
| 亮/暗主题 | 清爽开关切换，全局统一 |
| 数据自动同步 | 启动时自动检查并下载最新文言文库数据包（prerelease），无需等待 App 更新 |
| 版本更新 | GitHub Release 检查，一键跳转下载 |
| 学习统计 | 阅读时长、篇数、日均统计、连续天数 |

---

## 快速开始

```bash
# 1. 数据初始化（生成 classical.db 并同步到应用资产）
python3 scripts/project/generate_questions.py --json   # 生成题库 questions.json（可选，只跑 init_data.py 则 questions 表为空）
python3 scripts/project/init_data.py
cp build/data/classical.db flutter_app/assets/data/

# 2. 编译 C++ 引擎
cmake -B build && cmake --build build -j$(nproc) --target chinese_core

# 3. 启动 Flutter 应用
cd flutter_app && flutter pub get && flutter run -d linux
```

> 第 1 步需要 Python 3 + numpy（本机开发可用 `source venv/bin/activate`，或 `pip install -r requirements-ci.txt`）。
>
> （维护者操作：DB 版本号生成见 `scripts/project/gen_db_version.sh`，按"先提交 → 执行 → amend"顺序；DB Schema 变更时先 `rm build/data/classical.db` 再重跑第 1 步，最后用 `git add flutter_app/assets/data/classical.db flutter_app/assets/data/db_version.txt` 显式提交。数据更新对外发布见 `scripts/project/publish_data.sh`——一键压缩 DB 并发布为 prerelease，客户端自动同步，无需发 App 新版本。）

Windows 将 `-d linux` 换成 `-d windows`；Android 换成 `-d <设备名>`。iOS 见下方。

### 运行测试

```bash
cmake --build build -j$(nproc) --target run_tests
./build/tests/run_tests                       # C++ 单元测试 (Catch2)

cd flutter_app && flutter analyze              # Dart 静态分析
cd flutter_app && flutter test                 # Dart 单元测试
```

> `flutter test` 含真实加载核心引擎的 FFI 集成测试（`test/integration/db_replace_flow_test.dart`），需先执行上面的 `cmake --build`；未构建核心（或 CI 非 Linux 作业）时自动跳过，不影响通过。

### 覆盖率报告（只出报告，不设门槛）

```bash
./scripts/test_coverage_cpp.sh                 # C++：独立 build-cov 目录跑 gcovr，输出 HTML+JSON+行覆盖率汇总
cd flutter_app && flutter test --coverage     # Dart：生成 coverage/lcov.info
python3 scripts/summarize_cov.py flutter_app/coverage/lcov.info   # Dart 行覆盖率汇总
```

> C++ 覆盖率需 `pip install 'gcovr>=8'`（venv 内已装）。两套报告在 CI（`flutter-build.yml` Linux 作业）自动生成并作为 `coverage-reports` artifact 上传，不阻塞构建。

### iOS 侧载

CI 自动构建未签名 `.ipa`，可使用 SideStore / AltStore 自签安装。

> **诚征 macOS 贡献者** — CI 已能构建出未签名 `.ipa`，但维护者没有 Mac / 开发者账号，无法本地测试或签名。对苹果生态不熟悉，有意者欢迎邮件：3407131764@qq.com

---

## 项目架构

```
CMakeLists.txt         C++ 顶层构建（C++17 · SQLite3 · spdlog）
include/               C++ 头文件（引擎 · 知识追踪）
bridge/                C FFI 导出函数 -> libchinese_core.so
src/core/              推荐引擎 · 知识追踪（公式 19/20/14/15/17/18）
src/database/          SQLite 访问封装
tests/                 Catch2 单元测试
third_party/           供应商库（sqlite3.c · spdlog · Catch2 · Boost.Nowide）
articles/              应用数据源 — 270 篇古文（anthology 202 + textbook 68）
scripts/               Python 数据管线（scripts/project/：init_data.py · features.json · gen_db_version.sh · bump_version.sh · publish_data.sh · build_ios_core.sh；subset_fonts.py 字体子集化）
packaging/             AppImage / iOS 打包脚本
flutter_app/
  lib/main.dart        入口 · MainShell (NavigationRail + IndexedStack)
  lib/bridge/          dart:ffi 绑定（ffi_bindings · c_types）
  lib/engine/          FFI 封装（tracker · recommendation · read_tracker · text_repository · annotation_parser · update_checker · remote_db_sync · db_version · app_logger · algorithm_constants · github_config）
  lib/models/          user · text · version · reading_view_data
  lib/state/           5 个控制器（coordinator · navigation · reading · settings · user）
  lib/service/         history_service
  lib/theme/           AppTheme —— 颜色/字体 Token
  lib/pages/           read_hub · article_detail · my · settings
  lib/widgets/         reading_frame · radar_chart · annotation_popup · stats_card · recent_reading_list · text_card · dialogs
  assets/              字体子集化产物（思源宋体 · LXGW 文楷 · HarmonyOS Sans）· 内置 classical.db
```

---

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 许可

[MIT](LICENSE)
