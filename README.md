# 文言文个性化学习推荐系统

<p align="center">
  <strong>基于 C++ 的CLI文言文个性化学习推荐系统</strong>
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

中国古文推荐系统是一个基于 C++ 的命令行应用程序，旨在根据学习者的古文能力水平提供个性化的阅读推荐。兼容 Windows 和 Linux。

## 功能特性

### 核心功能

| 功能 | 描述 |
|------|------|
| 古文库浏览 | 分页浏览 264 篇经典古文 |
| 个性化推荐 | 基于能力水平的智能推荐 |
| 阅读追踪 | 阅读后自动更新能力模型，支持长期遗忘效应 |
| 用户管理 | SQLite 持久化存储 |

### 命令系统

```
> help                    # 显示帮助信息
> library [页码]          # 分页浏览文章库（每页 10 篇）
> recommend [数量]        # 个性化推荐（默认 5 篇，最多 20 篇）
> read <文章ID>           # 阅读文章并触发知识追踪
> log [debug|info|warn|error]  # 设置日志级别
> exit                    # 退出程序
```

### 使用示例

```
> recommend 3
正在计算推荐...
+------+----------------+--------+--------+
| 序号 |      标题      |  作者  | 匹配度 |
+------+----------------+--------+--------+
|    1 | 苏秦以连横说秦 | (不详) | 1.0000 |
+------+----------------+--------+--------+
|    2 | 宋玉对楚王问   | (不详) | 1.0000 |
+------+----------------+--------+--------+
|    3 | 游侠列传序     | (不详) | 1.0000 |
+------+----------------+--------+--------+
匹配度越高，文章难度越适合您当前的能力水平。

> read 1
═══════════════════════════════════════════════════
  《苏秦以连横说秦》
───────────────────────────────────────────────────
  【先秦】佚名
═══════════════════════════════════════════════════

苏秦始将连横说秦惠王曰：“大王之国，西有巴、蜀、汉中之利...
[阅读完成] 能力已更新
```

## 快速开始

### 环境要求

| 组件 | 版本要求 |
|------|----------|
| C++ 编译器 | 支持 C++17 (GCC 7+, Clang 5+, MSVC 2017+) |
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
mkdir -p build && cd build && cmake .. && make

# 运行
./chinese_classical_rec_sys
```

### 数据初始化

首次运行前需要初始化 SQLite 数据库：

```bash
python scripts/init_data.py
```

**脚本功能**：
- 从 `processed_classical/` 读取 264 篇古文（语文教材 63 篇 + 古文观止 213 篇 - 12 篇重复）
- 导入 10 维特征数据（`features.json`）
- 创建 SQLite 数据库 `data/classical.db`
- 程序首次启动时自动创建用户表

### 运行测试

```bash
cd build && cmake .. && make run_tests
./tests/run_tests
# 或使用 ctest
ctest --output-on-failure
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
├── include/                  # C++ 头文件
│   ├── core/                 # 命令系统、推荐引擎、知识追踪
│   ├── database/             # 数据库访问层
│   ├── models/               # 数据模型 (User, Text)
│   └── utils/                # 工具类 (Logger, PathUtils)
├── src/                      # C++ 源文件
├── tests/                    # 单元测试 (Catch2)
├── scripts/
│   └── init_data.py          # 数据初始化脚本
├── third_party/              # 第三方库
│   ├── spdlog/               # 高性能日志库
│   ├── sqlite3/              # 嵌入式数据库
│   └── catch2/               # 测试框架
├── processed_classical/      # 处理后的古文数据（白名单包含）
│   ├── textbook_annotated/   # 语文教材带注释版
│   ├── anthology/            # 古文观止原文
│   └── features.json         # 10维特征汇总
├── .github/                  # GitHub Actions 工作流
├── CMakeLists.txt            # 构建配置
├── LICENSE                   # MIT 许可证
├── requirements-ci.txt       # CI 环境依赖
└── README.md                 # 项目说明
```

> 注：部分数据文件、模型、实验脚本等文件暂未未包含在仓库中

## 开发指南

### 代码规范

- **命名约定**：类名 PascalCase，方法名 camelCase
- **文件格式**：头文件 `.h`，源文件 `.cpp`
- **注释风格**：Doxygen 风格

### 添加新命令

1. 在 `include/core/` 创建命令类，继承 `Command` 基类
2. 在 `src/core/` 实现命令逻辑
3. 在 `CommandRegistry` 中注册命令

### 日志系统

```cpp
#include "utils/Logger.h"

LOG_DEBUG("调试信息: {}", value);
LOG_INFO("程序启动");
LOG_WARN("警告: {}", warning);
LOG_ERROR("错误: {}", error);
```

日志输出位置：`build/logs/app.log`

### 测试覆盖

| 模块 | 测试内容 |
|------|----------|
| RecommendationEngine | gaussian、calculateLearningGain、calculateDynamicLearningRate |
| KnowledgeTracker | calculateForgettingFactor（幂律遗忘） |

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE)。

## 致谢

感谢所有开源项目和数据贡献者。

---

<p align="center">
  <sub>Made with ❤️ for Chinese classical literature learners</sub>
</p>