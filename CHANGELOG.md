# Changelog

## [0.4.0] - 2026-05-10

字号可调、阅读历史可见、日志更可靠。

### Added

- **字号可调**：设置页新增 4 档字号（小/中/大/特大），阅读页即时联动，重启后保持
- **阅读历史**："我的"页新增阅读统计卡片（总时长/篇数/日均/连续）和最近阅读列表，单击可跳回继续读
- **导航精简**：文库/推荐/阅读合并为"阅读"页，底部导航从 5 项减为 3 项，阅读时自动隐藏导航栏
- **阅读锁定**：阅读中误点其他页面会弹确认，避免丢掉阅读记录
- **日志系统**：应用运行日志改为滚动保存（最多 3 个文件），出错时更方便排查问题
- **iOS 支持**：现在可以在 iOS 设备上侧载运行（需 SideStore）

### Fixed

- 调整字号后阅读页标尺线和分页不刷新的问题
- 长时间阅读后能力追踪不生效的问题
- 切出阅读时知识追踪丢失的问题
- 阅读框缺少完成/放弃按钮无法退出的问题
- 无效文章 ID 进入空白阅读页的问题
- CI 构建失败（CMake 生成目录缺失）的问题

## [0.3.0] - 2026-05-07

CLI → Flutter 桌面端 + Android 全面升级。

### Added

- 全新 Flutter 界面：文库 / 推荐 / 阅读 / 能力 / 设置
- 古籍装帧主题：纸墨底色 + 朱砂红点缀，亮暗色切换
- 响应式布局：桌面、平板、手机自适配
- 分页阅读：键盘翻页、乌丝栏、阅读计时
- 推荐页：匹配度排序
- 能力页：雷达图
- 版本更新检查
- 移动端支持：Android、窄屏适配
- 桌面安装包：Linux AppImage、Windows 安装向导

### Fixed

- Windows 安装后启动崩溃
- Linux AppImage 兼容性

---

## [0.1.0] - 2026-05-01

CLI → Qt6 图形界面重写。

### Added

- 图形界面：文库 / 阅读 / 推荐 / 能力 / 设置
- 古籍风格主题，亮暗色切换
- 文库搜索与筛选
- 分页阅读 + 计时
- 能力雷达图

### Fixed

- 中文搜索不生效
- 阅读计时重复记录
- Linux 中文路径崩溃

---

## [0.0.1] - 2026-04-18

C++ CLI 原型。

### Added

- 命令行操作：搜索、推荐、阅读、记录
- 个性化推荐算法
- 知识追踪（IRT 模型）
- SQLite 本地存储

[0.4.0]: https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v0.4.0
[0.3.0]: https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v0.3.0
[0.1.0]: https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v0.1.0
[0.0.1]: https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v0.0.1
