# 古文推荐系统

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/C++-17-00599C?logo=c%2B%2B" alt="C++17">
  <img src="https://img.shields.io/badge/Linux-✓-FCC624?logo=linux" alt="Linux">
  <img src="https://img.shields.io/badge/Windows-✓-0078D6?logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Android-✓-3DDC84?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/iOS-needs%20help-999999?logo=apple" alt="iOS">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

**基于知识追踪模型的文言文个性化学习推荐系统** — Flutter Desktop (Linux/Windows) + Android/iOS · C++ 引擎 · Python 数据管线

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

面向文言文学习者的个性化阅读推荐工具：用**知识追踪模型**建模你的古文能力，结合**多维文本特征**（字频、通假字密度、典故密度、语义复杂度等），推荐难度略高于当前水平的文章（"i+1"递进）——而不是简单的规则或标签分类。

---

## 算法与论文

本项目基于一篇暂未公开的论文，将古文能力分解为字词、语法、典故、修辞等维度。

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 古文库 | 270 篇古文分页浏览，搜索作者/标题，已读/未读标记 |
| 个性推荐 | 高斯 i+1 推荐引擎，推荐数量可调 |
| 阅读器 | 乌丝栏版框、8 档字号、计时器、键盘翻页、阅读锁定 |
| 译文对照 | 阅读器内逐段对照现代文译文（开关可在设置页关闭） |
| 随文答题 | 每篇随堂练习：原句划线标注、知识追踪计分，反馈能力成长 |
| 能力雷达 | 10 维能力雷达图 + 综合评分，追踪学习成长 |
| 亮/暗主题 | 全局一键切换 |
| 数据自动同步 | 启动时自动检查并下载最新文言文库数据包（prerelease），无需等待 App 更新 |
| 版本更新 | GitHub Release 检查，一键跳转下载 |
| 学习统计 | 阅读时长、篇数、日均统计、连续天数 |

---

## 快速开始

仓库已内置数据（270 篇文章 + 题库），直接编译运行即可：

```bash
# 1. 编译 C++ 引擎
cmake -B build && cmake --build build -j$(nproc) --target chinese_core

# 2. 启动 Flutter 应用
cd flutter_app && flutter pub get && flutter run -d linux
```

Windows 将 `-d linux` 换成 `-d windows`；Android 换成 `-d <设备名>`；iOS 见下方。

> 数据重建 / DB Schema 变更 / 数据发布是维护者操作，见 [维护者：数据管线](#维护者数据管线)。

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

### 维护者：数据管线

> 仅维护者需要执行，普通开发无需关心。

**重建数据**（输出 `classical.db` 并同步到应用资产）：

```bash
python3 scripts/project/export_question_id_map.py   # 重建前从旧库导出 q_key→id 映射，保老用户复习数据 id 稳定（首次建库可跳过）。默认读 build/data/classical.db；旧库仅存在于应用资产时传 flutter_app/assets/data/classical.db
python3 scripts/project/generate_questions.py --json   # 生成题库 questions.json（可选；不跑则 questions 表为空）
python3 scripts/project/init_data.py --id-map build/data/question_id_map.json   # 无 id 映射时省略 --id-map
cp build/data/classical.db flutter_app/assets/data/
```

依赖：Python ≥ 3.10（脚本使用 PEP 604 语法）+ numpy + pypinyin（可用 `source venv/bin/activate`，或 `pip install -r requirements-ci.txt` 后补装 pypinyin）。题库生成依赖 `external/tongjiazi`（未入库素材）：缺失时音近/形近换质自动关闭、退化为纯本字池，不影响建库。

**DB Schema 变更**：先 `rm build/data/classical.db` 再重跑上面的重建步骤，最后显式提交：

```bash
git add flutter_app/assets/data/classical.db flutter_app/assets/data/db_version.txt
```

**发布数据包**：数据提交后运行 `bash scripts/project/publish_data.sh`，一键完成：

1. 刷新 db_version.txt（`gen_db_version.sh`）并 amend 进数据提交（`SKIP_AMEND=1` 跳过）
2. 题库可复现性检查（`check_questions_reproducible.sh`，连跑两次生成比对哈希；`SKIP_REPRO_CHECK=1` 跳过）
3. 压缩 DB 发布为 GitHub prerelease

客户端启动时自动检查并同步新数据包，无需发布 App 新版本。

---

## 项目架构

**C++ 核心** — 编译产物 `libchinese_core.so`，通过 27 个 C FFI 符号向 Flutter 暴露

- `CMakeLists.txt` 顶层构建（C++17 · SQLite3 · spdlog）
- `include/` 头文件（引擎 · 知识追踪）
- `bridge/` C FFI 导出函数
- `src/core/` 推荐引擎 · 知识追踪
- `src/database/` SQLite 访问封装
- `tests/` Catch2 单元测试
- `third_party/` 供应商库（sqlite3.c · spdlog · Catch2 · Boost.Nowide）

**Python 数据管线** — 把 `articles/` 加工成 `classical.db`

- `articles/` 270 篇古文数据源（anthology 202 + textbook 68）
- `scripts/project/` 核心脚本：init_data.py（建库）· generate_questions.py（题库）· features.json（13 维特征）· publish_data.sh（发布）· bump_version.sh（发版）· gen_db_version.sh · check_questions_reproducible.sh · build_ios_core.sh
- `scripts/` 辅助脚本：subset_fonts.py（字体子集化）· test_coverage_cpp.sh / summarize_cov.py（覆盖率）

**Flutter 应用** — `flutter_app/`

- `lib/main.dart` 入口 · MainShell（NavigationRail + IndexedStack）
- `lib/bridge/` dart:ffi 绑定（ffi_bindings · c_types）
- `lib/engine/` FFI 封装（tracker · recommendation · read_tracker · text_repository · annotation_parser · translation_builder · update_checker · remote_db_sync · db_version · app_logger · algorithm_constants · github_config）
- `lib/models/` user · text · question · version · reading_view_data
- `lib/state/` 5 个控制器（coordinator · navigation · reading · settings · user）
- `lib/service/` history_service
- `lib/theme/` AppTheme —— 颜色/字体 Token（强调色用户可调：context.accent = ColorScheme.primary）
- `lib/pages/` read_hub · article_detail · my · settings · quiz · quiz_result · review_list
- `lib/widgets/` reading_frame · radar_chart · annotation_popup · marked_sentence · stats_card · recent_reading_list · text_card · empty_state · dialogs
- `assets/` 字体子集化产物（思源宋体 · LXGW 文楷 · HarmonyOS Sans）· 内置 classical.db · icon/app_icon.png

**打包** — `packaging/`（AppImage / NSIS / iOS 脚本）

---

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 许可

[MIT](LICENSE)
