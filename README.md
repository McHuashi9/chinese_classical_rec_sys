# 文言文个性化学习推荐系统

<p align="center">
  <strong>基于 Qt 6 + QML 的 GUI 桌面应用，根据古文能力水平提供个性化阅读推荐</strong>
</p>

<p align="center">
  <a href="#项目概述">概述</a> •
  <a href="#功能特性">功能</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#算法原理">算法</a> •
  <a href="#开发指南">开发</a>
</p>

---

## 项目概述

中国古文推荐系统是一个基于 Qt 6 + QML 的桌面 GUI 应用，面向文言文学习者。系统通过 10 维特征模型量化 268 篇古文的难度，追踪用户阅读后的能力变化，使用高斯 i+1 模型生成个性化推荐。

兼容 Windows 和 Linux 平台。

## 功能特性

### 五大页面

| 页面 | 描述 |
|------|------|
| 文库 | 搜索 + 列表浏览 268 篇古文，点击进入阅读 |
| 推荐 | 设定篇数，一键生成个性化推荐，显示匹配度百分比 |
| 阅读 | 版框正文（思源宋体 18px / 行高 1.8）+ 计时器，<30s 不触发知识追踪 |
| 能力 | 10 轴 Canvas 雷达图 + 各维度数值进度条 |
| 设置 | 亮/暗主题切换（QSettings 持久化）+ 日志级别 ComboBox |

### 主题系统

- 10 色 Token（paper / card / ink / vermilion / border 等），全部 UI 元素引用 Token
- 亮/暗双模式，一键切换，重启保留偏好
- 三款字体：霞鹜文楷（标题）· 思源宋体（正文）· HarmonyOS Sans（UI）

### 交互状态

所有可交互元素覆盖 default / hover / press / disabled 四态，过渡 150–200ms。
页面切换：侧栏导航横向滑动 200ms，阅读页淡入淡出。
列表项：自上而下 30ms 错开淡入。

## 快速开始

### 环境要求

| 组件 | 版本要求 |
|------|----------|
| C++ 编译器 | 支持 C++17 (GCC 7+, Clang 5+, MSVC 2017+) |
| Qt | 6.x (QML + Quick Controls) |
| CMake | 3.28+ |
| Python | 3.12+ |

### 构建与运行

```bash
# 克隆仓库
git clone https://github.com/McHuashi9/chinese_classical_rec_sys.git
cd chinese_classical_rec_sys

# 数据初始化（首次运行前）
python scripts/init_data.py

# 构建
mkdir -p build && cd build
cmake .. -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x.x/gcc_64
make -j$(nproc)

# 运行
./chinese_classical_rec_sys
```

### 数据初始化

首次运行前需要初始化 SQLite 数据库：

```bash
python scripts/init_data.py
```

**脚本功能**：
- 从 `processed_classical/` 读取 268 篇古文（语文教材 63 篇 + 古文观止 213 篇 - 12 篇重复 + 补充）
- 导入 10 维特征数据（`features.json`）
- 创建 SQLite 数据库 `data/classical.db`
- 程序首次启动时自动创建用户表

### 运行测试

```bash
cd build && cmake .. -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x.x/gcc_64 && make run_tests
./tests/run_tests
```

## 算法原理

### 1. 难度量化模型

采用 10 维特征体系量化古文难度，使用 CRITIC 法确定各特征权重：

| 维度 | 特征 | 说明 | 权重 |
|------|------|------|------|
| d1 | 平均句长 | 句法复杂度指标 | 9.22% |
| d2 | 句子数 | 文本长度指标 | 9.38% |
| d3 | 虚词比例 | 语法复杂度指标 | 13.11% |
| d4 | 字平均对数频次 | 字词熟悉度指标 | 9.25% |
| d5 | 通假字密度 | 古汉语特有难度 | 10.34% |
| d6 | 古汉语困惑度 | 语言模型评分 | 11.62% |
| d7 | 现代文困惑度 | 古今差异指标 | 8.77% |
| d8 | 词汇多样性 (MATTR) | 词汇丰富度 | 8.54% |
| d9 | 典故密度 | 文化背景要求 | 10.09% |
| d10 | 语义复杂度 | 语义深度指标 | 9.68% |

### 2. 高斯 i+1 推荐算法

基于 Krashen 的 i+1 理论，采用高斯概率模型：

$$P(article|user) = exp(-(|d - u - δ*|²) / (2σ²))$$

其中：
- $d$：文章难度向量
- $u$：用户能力向量
- $δ* = 0.13$：理想难度差距（敏感度分析优化结果）
- $σ = 0.25$：容差参数

### 3. 知识追踪模型

**动态学习率**：学习增益随能力接近程度自适应调整

$$η = η₀ · (1 - |d - u|)^γ$$

**幂律遗忘**：能力增益随时间衰减

$$
u_j(t) = u_j^base + Σ Δu_j^(k) · ψ(t - t_k)
ψ(Δt) = (1 + Δt/τ)^(-c)
$$

参数：$τ = 10.0 天，c = 0.70$

## 目录结构

```
chinese_classical_rec_sys/
├── gui/                       # Qt Quick GUI
│   ├── qml/                   # QML 页面 (5页面 + Theme + Sidebar + MainWindow)
│   ├── viewmodel/             # C++ ViewModel (AppViewModel, 数据模型)
│   └── main_gui.cpp           # 入口
├── core/                      # 推荐引擎、知识追踪
├── database/                  # SQLite 仓库层 (5个 Repository)
├── models/                    # User (10维能力)、Text (10维难度)
├── utils/                     # Logger、PathUtils、FeatureExtractor
├── tests/                     # Catch2 单元测试
├── scripts/                   # Python 预处理与实验
│   └── init_data.py           # 数据初始化脚本
├── third_party/               # 第三方库 (spdlog, sqlite3, catch2)
├── data/                      # classical.db 等运行时数据
├── processed_classical/       # 处理后的古文数据
├── design-spec.md             # GUI 设计规范与组件定义
├── CMakeLists.txt             # 构建配置
├── LICENSE                    # MIT 许可证
└── README.md                  # 项目说明
```

## 开发指南

### 代码规范

- **命名约定**：类名 PascalCase，方法名 camelCase
- **文件格式**：头文件 `.h`，源文件 `.cpp`
- **注释风格**：Doxygen 风格
- **QML**：所有颜色/字体/间距从 `Theme.qml` Token 取值

### 提交规范

格式：`type(scope): 中文描述`

- `feat` 新功能 · `fix` 修 bug · `refactor` 重构 · `chore` 杂项 · `test` 测试
- scope 小写英文，如 `gui` `core` `db`
- 描述用中文，简明扼要

### 日志系统

```cpp
#include "utils/Logger.h"

LOG_DEBUG("调试信息: {}", value);
LOG_INFO("程序启动");
LOG_WARN("警告: {}", warning);
LOG_ERROR("错误: {}", error);
```

日志输出位置：`logs/app.log`，默认 INFO 级别，可通过设置页 ComboBox 调整。

### 测试覆盖

| 模块 | 测试内容 |
|------|----------|
| RecommendationEngine | gaussian、calculateLearningGain、calculateDynamicLearningRate |
| KnowledgeTracker | calculateForgettingFactor（幂律遗忘） |

## 参考文档

- `design-spec.md` — GUI 设计系统与组件规范（颜色、字体、间距、组件定义、验收标准）
- `scripts/experiments/e*_*/README.md` — 各实验说明

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE)。

## 致谢

感谢所有开源项目和数据贡献者。

---

<p align="center">
  <sub>Made with ❤️ for Chinese classical literature learners</sub>
</p>
