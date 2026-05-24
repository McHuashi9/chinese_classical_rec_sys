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
  <strong>基于 Flutter Desktop 的古文个性化学习推荐系统</strong><br>
</p>

>  **诚征 macOS 贡献者 / Help Wanted: macOS Contributor**
>
> 项目维护者没有 Mac，也没有 $99 开发者账号。iOS 代码适配正在进行，但没有 macOS 环境无法完成构建。对苹果生态不熟悉，有意者欢迎邮件细聊。
>
> The maintainer has no Mac or $99 Apple developer account. iOS code adaptation is in progress, but building requires macOS. Not familiar with the Apple ecosystem — feel free to email me for details.
>
> 联系方式 / Contact：3407131764@qq.com

---

## 功能

| 页面 | 能力 |
|------|------|
| 📚 古文库 | 268 篇分页浏览、搜索作者/标题 |
| 🎯 个性推荐 | 高斯 i+1 算法、数量可调 |
| 📖 阅读页 |乌丝栏版框、计时器、键盘翻页 |
| 🕸️ 能力雷达 | 10 维雷达图 + 综合评分 |
| ⚙️ 设置 | 亮/暗主题、版本更新检测、DB 自动同步 |

## 快速开始

```bash
# 1. 数据初始化
python scripts/init_data.py

# 2. 编译 C++ 引擎
mkdir -p build && cd build && cmake .. && make chinese_core -j$(nproc)

# 3. 启动 Flutter
cd ../flutter_app && flutter pub get && flutter run -d linux
```

### 运行测试

```bash
cd build && make test_runner && ./tests/test_runner   # C++ 测试
cd ../flutter_app && flutter analyze                    # Dart 静态分析
```

## iOS 安装（侧载）

CI 每次发版自动构建未签名 `.ipa`，需用户自行签名安装：

| 工具 | 说明 |
|------|------|
| **SideStore** ⭐⭐⭐ | 手机无线自签续签，无需电脑 |
| AltStore ⭐⭐ | 需电脑 AltServer 后台自动续签 |
| Sideloadly ⭐ | 每 7 天手动重拖 |

步骤：下载 CI Release 的 `Runner.ipa` → SideStore 导入 → 用免费 Apple ID 签名安装 → `设置 → VPN与设备管理` 信任证书。

> 构建由 `macos-14` runner 执行，产物始终未签名。无 Mac 贡献者时 CI 注入占位 Team ID。

## 架构

```
CMakeLists.txt    C++ 顶层构建（SQLite3 + spdlog）
include/          C++ 头文件（引擎 · 知识追踪）
bridge/           C FFI 导出层
src/core/         推荐引擎 · 知识追踪
src/database/     SQLite 访问层
tests/            Catch2 单元测试
third_party/      供应商库（sqlite3 · spdlog · Catch2）
scripts/          Python 数据管线（特征提取 · 实验）
assets/           字体 · 内置数据库
data/             字频表 · 权重 · 典故索引
packaging/        AppImage / iOS 打包脚本
processed_classical/  预处理缓存（特征 · 通假字 · 困惑度）
flutter_app/lib/
  main.dart       引导入口
  bridge/         dart:ffi 绑定
  engine/         FFI 封装
  models/         User · ChineseText · RecommendResult
  service/        历史记录
  state/          AppState (ChangeNotifier + Provider)
  theme/          AppTheme — 颜色 · 字体 Token
  pages/          read_hub · my · settings · article_detail
  widgets/        reading_frame · radar_chart · stats_card · dialogs
```

## 论文复现

论文全文因保密暂未公开。数据准备、特征提取、实验对比等完整复现步骤见根目录下的 [`论文复现指南.md`](论文复现指南.md)。

## 许可证

MIT
