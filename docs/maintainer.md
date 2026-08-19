# 维护者操作手册

> 面向维护者；普通贡献者不需要阅读。
> 本文件是**数据管线 / 数据库结构（DB Schema）/ 数据发布 / 版本发版**的权威源；构建与测试命令仍以 [README.md](../README.md) 为准。

## 环境依赖

- Python ≥ 3.10（脚本使用 PEP 604 语法）
- `numpy`、`pypinyin`（音近干扰项读音权威源；缺失自动关闭换质）
- `fonttools`（新增文章后跑 `scripts/subset_fonts.py` 时需要）
- `external/tongjiazi`（未入库素材）：缺失时音近/形近换质自动关闭，退化为纯本字池，不影响建库
- 推荐先激活 `venv/`：`source venv/bin/activate`

## 常规数据重建

输出 `build/data/classical.db` 并同步到应用资产：

```bash
# 重建前从旧库导出题目指纹 q_key→id 映射，保老用户复习数据 id 稳定（首次建库可跳过）
# 默认读 build/data/classical.db；旧库仅存在于应用资产时传 flutter_app/assets/data/classical.db
python3 scripts/project/export_question_id_map.py flutter_app/assets/data/classical.db

# 生成题库 questions.json（可选；不跑则 questions 表为空）
python3 scripts/project/generate_questions.py --json

# 建库；无 id 映射时省略 --id-map
python3 scripts/project/init_data.py --id-map build/data/question_id_map.json

cp build/data/classical.db flutter_app/assets/data/
```

## 数据库结构（DB Schema）变更

严格按以下顺序执行：

```bash
# 1. 旧库 id 映射（首次建库跳过）
python3 scripts/project/export_question_id_map.py flutter_app/assets/data/classical.db

# 2. 重新生成题库
python3 scripts/project/generate_questions.py --json

# 3. 删除旧内容库并重建
rm build/data/classical.db
python3 scripts/project/init_data.py --id-map build/data/question_id_map.json

# 4. 同步到应用资产
cp build/data/classical.db flutter_app/assets/data/

# 5. 先 commit 数据变更，再运行版本号刷新并 amend
bash scripts/project/gen_db_version.sh

# 6. 显式提交 DB 文件
git add flutter_app/assets/data/classical.db flutter_app/assets/data/db_version.txt
```

## 新增文章

1. 新增文章后必跑 `python3 scripts/subset_fonts.py`（需 `fonttools`；字体原文件来自 `fonts-v1` Release tag，勿删）。
2. 如需随文答题，先 `python3 scripts/project/generate_questions.py --json`，再跑 `init_data.py`。
3. 题库重建必须按上面的顺序先导出旧库 id 映射，避免老用户复习数据漂移。

## 发布数据包

数据提交后运行：

```bash
bash scripts/project/publish_data.sh
```

一键完成：

1. 刷新 `db_version.txt`（调 `gen_db_version.sh`）并修订提交（amend）进数据提交；`SKIP_AMEND=1` 跳过版本号刷新与 amend。
2. 题库可复现性检查（`check_questions_reproducible.sh`，连跑两次生成比对哈希）；`SKIP_REPRO_CHECK=1` 跳过。
3. 内容库一致性校验（`check_content_db.py`，硬闸门：表集合 / user_version / 初始化 q_key / q_key 唯一 / 题数 / db_version blob hash）。
4. 压缩 DB 发布为 GitHub 预发布（prerelease）。

约束：

- 数据变更须先 commit，工作树除 `db_version.txt` 外必须干净，否则脚本拒绝。
- 客户端启动时自动检查并同步新数据包，无需发布 App 新版本。

## 版本号与发版

- 版本号唯一源：`flutter_app/pubspec.yaml`。
- 格式 `major.minor.patch`，Git tag 加 `v` 前缀。
- 发版入口：`bash scripts/project/bump_version.sh X.Y.Z`（自动同步版本号、CHANGELOG 与 `flutter_app/assets/data/announcement.md` 的 id/版本改动）。
- 公告作者的话维护在 `flutter_app/assets/data/announcement.md`；发版脚本只自动同步“版本改动”段，作者的话需维护者手动更新。若整理 CHANGELOG 后需要重新同步，可执行 `bash scripts/project/sync_announcement.sh X.Y.Z`。
- 数据独立发布用 `publish_data.sh`（tag `data-*` 预发布 + gz），**先于 App 发布**。
- 每次功能变更同时更新 `CHANGELOG.md`。

### App 发版步骤

1. 开发期间持续更新 `CHANGELOG.md`（只写用户可感知变化）。
2. 执行 `bash scripts/project/bump_version.sh X.Y.Z`：
   - 自动更新 `flutter_app/pubspec.yaml`、`flutter_app/lib/state/coordinator.dart`、`packaging/nsis/installer.nsi`
   - 在 CHANGELOG 生成 `[X.Y.Z]` 头部和版本链接
   - 自动把最新 CHANGELOG 的 Added / Changed / Fixed 同步到 `flutter_app/assets/data/announcement.md` 的“版本改动”，并更新 front matter `id`
3. 人工检查/整理 CHANGELOG 的发布描述；若改动过 CHANGELOG 文案，重跑 `bash scripts/project/sync_announcement.sh X.Y.Z`。
4. 人工编辑 `flutter_app/assets/data/announcement.md` 的作者的话（脚本不会覆盖该部分）。
5. 提交并推送 `dev`（提交信息可参考 `CONTRIBUTING.md`，例如 `release: vX.Y.Z`）。
6. 合并到 `main` 并打 tag `vX.Y.Z`，推送 tag。
7. 等待 CI 构建/发布；如使用 `gh` 可关注 release 状态。
