# 贡献指南

感谢你对古文推荐系统感兴趣！不论你是发现了 Bug、有功能建议，还是想提交代码，都欢迎参与。

## 报告问题

**Bug 报告** — 开一个 Issue，说清楚：
- 运行环境（Linux / Windows / Android）
- 复现步骤
- 实际表现 vs 预期表现

**功能建议** — 也是开 Issue，描述你想要什么、为什么有用即可。

## 开发环境

需要 Flutter 3.47+（与 CI 的 `flutter-version: 3.47.x` 对齐）和 CMake 3.28+。

```bash
# Flutter（如果还没装）
export PATH="$HOME/flutter/bin:$PATH"

# 国内镜像（可选）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

## 本地构建

构建、运行与测试命令参见 [README.md 快速开始 / 运行测试](README.md#快速开始)。

> 字体已预置子集化版本（36MB）在仓库中。如需增删文章，先运行 `python3 scripts/subset_fonts.py`（需 `fonttools`；字体原文件来自 `fonts-v1` Release tag，勿删）更新字体。

## 运行测试

见 [README.md#运行测试](README.md#运行测试)（C++ Catch2 + `flutter analyze` + `flutter test`）。

## 贡献代码流程

1. 从 `dev` 分支 checkout 新分支：`git checkout -b feat/xxx dev`
2. 开发、本地测试
3. 确保 Commit 命名符合规范（见下文）
4. 推送并提交 Pull Request 到 `dev`

如果你只改一个文件，直接在 GitHub 网页上编辑并"Create a new branch for this commit" 提 PR 也行。

---

下面是维护者需要了解的规范，日常开发也请尽量遵守。

## Commit 命名

```
<type>(<scope>): <中文描述>
```

示例：`feat(gui): 搜索添加防抖`、`fix(engine): 知识追踪除零错误`

常用 type：`feat` `fix` `docs` `refactor` `test` `chore`；发版专用：`release: vX.Y.Z`（由 bump_version.sh 引导）

## 代码风格

| | 规范 | 例子 |
|---|---|---|
| 类名 | PascalCase | `AppState`, `LibraryPage` |
| 方法/变量 | camelCase | `switchPage`, `loadTextForReading` |
| 文件 | snake_case | `app_state.dart`, `library_page.dart` |
| 私有成员 | 前缀 `_` | `_pageIndex`, `_readingText` |

颜色和字体从 `AppTheme` 取，不硬编码。

- `ChangeNotifier` 必须被 `context.watch` / `Selector` / `Consumer` 监听，否则不重建
- 每次功能变更同时更新 `CHANGELOG.md`

## 版本号与发版

版本号格式 `major.minor.patch`，Git tag 加 `v` 前缀。来源于`pubspec.yaml`。

发版入口：`bash scripts/project/bump_version.sh X.Y.Z`（自动同步版本号与 CHANGELOG）。

数据更新独立于 App 发版：数据变更 commit 后运行 `bash scripts/project/publish_data.sh`——自动刷新 db_version 并 amend 进数据提交、题库可复现性检查、压缩 DB 发布为 prerelease，客户端启动时自动同步（详见 [README.md#快速开始](README.md#快速开始) 维护者操作说明；`SKIP_AMEND=1` / `SKIP_REPRO_CHECK=1` 可分别跳过版本号刷新与可复现性检查）。

发版仅维护者操作，贡献者不要在自己 fork 里执行。
