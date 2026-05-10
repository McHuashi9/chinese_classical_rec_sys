# 贡献指南

感谢你对古文推荐系统感兴趣！不论你是发现了 Bug、有功能建议，还是想提交代码，都欢迎参与。

## 报告问题

**Bug 报告** — 开一个 Issue，说清楚：
- 运行环境（Linux / Windows / Android）
- 复现步骤
- 实际表现 vs 预期表现

**功能建议** — 也是开 Issue，描述你想要什么、为什么有用即可。

## 开发环境

需要 Flutter 3.27+ 和 CMake 3.28+。

```bash
# Flutter（如果还没装）
export PATH="$HOME/flutter/bin:$PATH"

# 国内镜像（可选）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

## 本地构建

```bash
# 1. 数据初始化
python scripts/init_data.py

# 2. 编译 C++ 共享库
mkdir -p build && cd build && cmake .. && make chinese_core -j$(nproc)

# 3. 启动 Flutter 应用
cd flutter_app && flutter pub get && flutter run -d linux
```

Windows 将 `-d linux` 换成 `-d windows`；Android 换成 `-d <设备名>`。

## 运行测试

```bash
# C++ 单元测试
cd build && make test_runner && ./tests/test_runner

# Dart 静态分析
cd flutter_app && flutter analyze
```

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

常用 type：`feat` `fix` `docs` `refactor` `test` `chore`

## 代码风格

| | 规范 | 例子 |
|---|---|---|
| 类名 | PascalCase | `AppState`, `LibraryPage` |
| 方法/变量 | camelCase | `switchPage`, `loadTextForReading` |
| 文件 | snake_case | `app_state.dart`, `library_page.dart` |
| 私有成员 | 前缀 `_` | `_pageIndex`, `_readingText` |

颜色和字体从 `AppTheme` 取，不硬编码。

## 版本号

格式 `major.minor.patch`，Git tag 加 `v` 前缀。发版前同步：

- `pubspec.yaml` → `version: X.Y.Z`
- `flutter_app/lib/state/app_state.dart` → `currentVersion`
- `CHANGELOG.md` → 将 `[Unreleased]` 整理为正式发布条目

## 注意事项

项目 `.gitignore` 未纳入 Git 管理。

## 维护者专有：发版

```bash
git switch main && git merge --squash dev && git tag v0.x.0 && git push --follow-tags
git switch dev && git reset --hard main && git push --force
```

`--force` 会重写 dev 历史，仅维护者操作，贡献者不要在自己 fork 里执行。
