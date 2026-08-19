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
| 数据自动同步 | 启动时自动检查并下载最新文言文库数据包（预发布包，prerelease），无需等待 App 更新 |
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

> 数据重建 / 数据库结构（DB Schema）变更 / 数据发布是维护者操作，见 [docs/maintainer.md](docs/maintainer.md)。

### 运行测试

```bash
cmake --build build -j$(nproc) --target run_tests
./build/tests/run_tests                       # C++ 单元测试 (Catch2)

cd flutter_app && flutter analyze              # Dart 静态分析
cd flutter_app && flutter test                 # Dart 单元测试
```

> `flutter test` 含真实加载核心引擎的跨语言函数接口（FFI）集成测试（`test/integration/db_replace_flow_test.dart`），需先执行上面的 `cmake --build`；未构建核心（或 CI 非 Linux 作业）时自动跳过，不影响通过。

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

### Android 安装包签名验证

v1.0.0 起 Android 使用正式签名。安装 APK 前可用 Android SDK 的 `apksigner` 核对证书指纹，确认安装包由作者发布：

```bash
$ANDROID_HOME/build-tools/<版本>/apksigner verify --print-certs chinese-classical-rec-sys-1.0.0-android.apk
```

期望输出中的 SHA-256 指纹：

```text
B7:2F:ED:D8:E8:42:52:A4:09:5B:1E:F9:B5:DE:1C:29:4F:F3:88:F3:2D:70:65:4F:0F:0C:E6:F5:36:FE:46:D7
```

> 指纹是公开信息，不是密钥；它是用户验证 APK 真伪的锚点。v1.0.0 起签名已从 debug 切换为正式签名，旧 debug 版升级需卸载重装一次。

### 维护者操作

数据重建、数据库结构（DB Schema）变更、数据发布、版本发版等维护者流程见 [docs/maintainer.md](docs/maintainer.md)。

---

## 项目架构

**C++ 核心** — 编译产物 `libchinese_core.so`，通过 39 个 C 跨语言函数接口（FFI）符号向 Flutter 暴露（v1.0.0 拆双库：主连接 `user.db`，内容库 `classical.db` 以 `content` 附属库挂载）

- `CMakeLists.txt` 顶层构建（C++17 · SQLite3 · spdlog）
- `include/` 头文件（引擎 · 知识追踪）
- `bridge/` C 跨语言函数接口（FFI）导出函数
- `src/core/` 推荐引擎 · 知识追踪
- `src/database/` SQLite 访问封装
- `tests/` Catch2 单元测试
- `third_party/` 供应商库（sqlite3.c · spdlog · Catch2 · Boost.Nowide）

**Python 数据管线** — 把 `articles/` 加工成 `classical.db`

- `articles/` 270 篇古文数据源（anthology 202 + textbook 68）
- `scripts/project/` 核心脚本：init_data.py（建库）· generate_questions.py（题库）· features.json（13 维特征）· publish_data.sh（发布）· bump_version.sh（发版）· gen_db_version.sh · check_questions_reproducible.sh · check_content_db.py（内容库发布校验）· build_ios_core.sh
- `scripts/` 辅助脚本：subset_fonts.py（字体子集化）· test_coverage_cpp.sh / summarize_cov.py（覆盖率）

**Flutter 应用** — `flutter_app/`

- `lib/main.dart` 入口 · MainShell（NavigationRail + IndexedStack）
- `lib/bridge/` dart:ffi 绑定（ffi_bindings · c_types）
- `lib/engine/` 跨语言函数接口（FFI）封装（tracker · recommendation · read_tracker · profile_repository · user_init_repository · text_repository · annotation_parser · translation_builder · update_checker · remote_db_sync · db_version · app_logger · algorithm_constants · github_config · announcement · feedback_mailto · feedback_submit）
- `lib/models/` user · user_profile · text · question · version · reading_view_data
- `lib/state/` 5 个控制器（coordinator · navigation · reading · settings · user）
- `lib/service/` history_service
- `lib/theme/` AppTheme —— 颜色/字体 Token（强调色用户可调：context.accent = ColorScheme.primary）
- `lib/pages/` read_hub · article_detail · my · settings · quiz · quiz_result · review_list · init_onboarding · init_result · reading_preview
- `lib/widgets/` reading_frame · radar_chart · annotation_popup · marked_sentence · stats_card · recent_reading_list · text_card · empty_state · dialogs · announcement_dialog · simple_markdown
- `assets/` 字体子集化产物（思源宋体 · LXGW 文楷 · HarmonyOS Sans）· 内置 classical.db · icon/app_icon.png · data/announcement.md

**Cloudflare Worker 骨架（预研）** — `worker/`（`wrangler.toml` + `src/index.js`）：当前仅用于本地验证反馈接收链路，后续按遥测（telemetry）待办扩展限流 / Cloudflare R2 对象存储 / 服务端转发。

**打包** — `packaging/`（AppImage / NSIS / iOS 脚本）

---

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 许可

[MIT](LICENSE)
