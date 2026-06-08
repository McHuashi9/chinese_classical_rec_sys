<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter" alt="Flutter">
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

完整的数据准备、特征提取、实验对比步骤见 [`论文复现指南.md`](论文复现指南.md)。

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 古文库 | 270 篇古文分页浏览，搜索作者/标题，已读/未读标记 |
| 个性推荐 | 高斯 i+1 推荐引擎，推荐数量可调 |
| 阅读器 | 乌丝栏版框、8 档字号、计时器、键盘翻页、阅读锁定 |
| 能力雷达 | 10 维能力雷达图 + 综合评分，追踪学习成长 |
| 亮/暗主题 | 清爽开关切换，全局统一 |
| 版本更新 | GitHub Release 检查，一键跳转下载 |
| 学习统计 | 阅读时长、篇数、日均统计、连续天数 |

---

## 快速开始

```bash
# 1. 数据初始化（生成 classical.db）
python3 scripts/project/init_data.py

# 2. 编译 C++ 引擎
cmake -B build && cmake --build build -j$(nproc) --target chinese_core

# 3. 启动 Flutter 应用
cd flutter_app && flutter pub get && flutter run -d linux
```

Windows 将 `-d linux` 换成 `-d windows`；Android 换成 `-d <设备名>`。iOS 见下方。

### 运行测试

```bash
cmake --build build -j$(nproc) --target run_tests
./build/tests/run_tests                       # C++ 单元测试 (Catch2)

cd flutter_app && flutter analyze              # Dart 静态分析
```

### iOS 侧载

CI 自动构建未签名 `.ipa`，可使用 SideStore / AltStore 自签安装。详细步骤见 [`SIDELOAD_IOS.md`](SIDELOAD_IOS.md)。

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
processed_classical/   论文实验数据（归档保留）
scripts/               Python 数据管线（特征提取 · ML 训练 · 实验）
assets/                字体（SourceHanSerifSC）· 内置 classical.db
data/                  字频表 · 权重 · 典故索引
packaging/             AppImage / iOS 打包脚本
flutter_app/
  lib/main.dart        入口 · MainShell (NavigationRail + IndexedStack)
  lib/bridge/          dart:ffi 绑定
  lib/engine/          FFI 封装
  lib/models/          User · ChineseText · RecommendResult
  lib/state/           AppState (ChangeNotifier + Provider)
  lib/theme/           AppTheme —— 颜色/字体 Token
  lib/pages/           read_hub · my · settings · article_detail
  lib/widgets/         reading_frame · radar_chart · stats_card · dialogs
```

---

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## 许可

[MIT](LICENSE)
