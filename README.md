<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/C++-17-00599C?logo=c%2B%2B" alt="C++17">
  <img src="https://img.shields.io/badge/Linux-✓-FCC624?logo=linux" alt="Linux">
  <img src="https://img.shields.io/badge/Windows-✓-0078D6?logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Android-✓-3DDC84?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<h1 align="center">古文推荐系统</h1>

<p align="center">
  <strong>基于 Flutter Desktop 的古文个性化学习推荐系统</strong><br>
</p>

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

## 算法

#### 10 维难度量化

| 维度 | 特征 | 权重 |
|:----:|------|-----:|
| d1 | 平均句长 | 9.22% |
| d2 | 句子数 | 9.38% |
| d3 | 虚词比例 | 13.11% |
| d4 | 字平均对数频次 | 9.25% |
| d5 | 通假字密度 | 10.34% |
| d6 | 古汉语困惑度 | 11.62% |
| d7 | 现代文困惑度 | 8.77% |
| d8 | 词汇多样性 (MATTR) | 8.54% |
| d9 | 典故密度 | 10.09% |
| d10 | 语义复杂度 | 9.68% |

#### 高斯 i+1 推荐

$$P = \exp\!\left(-\frac{\|d - u - \delta^*\|^2}{2\sigma^2}\right) \qquad \delta^*=0.13,\ \sigma=0.25$$

#### 知识追踪

**学习率** $\eta = \eta_0 \cdot (1 - |d - u|)^\gamma$ &nbsp;&nbsp;|&nbsp;&nbsp; **遗忘率** $\psi(\Delta t) = (1 + \Delta t/\tau)^{-c},\ \tau=10.0,\ c=0.70$

## 架构

```
bridge/          C FFI 桥接层
src/core/        推荐引擎 · 知识追踪
src/database/    SQLite 访问层
flutter_app/lib/
  bridge/        dart:ffi 绑定
  engine/        FFI 封装
  models/        User · ChineseText · RecommendResult
  state/         AppState (ChangeNotifier + Provider)
  theme/         AppTheme — 颜色 · 字体 Token
  pages/         library · recommend · read · ability · settings
  widgets/       library_card · recommend_card · radar_chart
```

## 许可证

MIT
