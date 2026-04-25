# GUI 设计规范 — 古典文学阅读推荐系统

## 设计基调

仿古籍线装书视觉，文字横排、从左到右。以旧纸墨色为基底，朱砂红点缀，结合版框、界栏、鱼尾等装帧元素，保持现代桌面应用的清晰可读性。

核心约束：
- 不引入紫色渐变、霓虹色、毛玻璃等现代 UI 陈词滥调
- 不使用 emoji 作为图标替代品；图标缺失时用几何形 + 文字标注
- 不展示虚假数据或装饰性统计数字
- 留白优先于填塞内容

## 色彩

| Token | 色值 | 用途 |
|-------|------|------|
| `paper` | #F5F0E8 | 窗口背景 |
| `card` | #FFFDF7 | 卡片、文本区域背景 |
| `ink` | #2C2416 | 主文字 |
| `inkSecondary` | #5A5245 | 辅助文字 |
| `vermilion` | #B33A3A | 强调色——主按钮、链接、焦点线 |
| `vermilionHover` | #932E2E | 悬停/按下 |
| `stoneGreen` | #5B7B4A | 成功状态、进度完成 |
| `border` | #C2B28F | 通用边框、界栏 |
| `borderLight` | #D4C9A8 | 细分隔线 |
| `overlay` | rgba(28,24,18,0.80) | 遮罩 |

所有 UI 元素必须从以上 Token 取值，不得自行引入新颜色。

## 字体

| 角色 | 字体 | 源文件 |
|------|------|--------|
| 正文（阅读） | 思源宋体 SC Regular | `gui/fonts/SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf` |
| 正文（备选细体） | 思源宋体 SC Light | `gui/fonts/SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Light.otf` |
| 标题、导航 | 霞鹜文楷 Regular | `gui/fonts/LXGWWenKai-Regular/LXGWWenKai-Regular.ttf` |
| 标题（强调） | 霞鹜文楷 Medium | `gui/fonts/LXGWWenKai-Regular/LXGWWenKai-Medium.ttf` |
| UI 辅助文字 | HarmonyOS Sans SC Regular | `gui/fonts/HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf` |
| UI 辅助（加粗） | HarmonyOS Sans SC Bold | `gui/fonts/HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf` |

其他字重和语言变体已保留在 `gui/fonts/` 对应子目录，如需要可追加到 `.qrc`。

字体通过 `FontLoader` 或 `QFontDatabase::addApplicationFont` 内嵌，随可执行文件分发。

字号梯度（4px 模数）：
- Display 36px · H1 24px · H2 20px · Body 16px · Caption 14px · Small 12px

## 间距与布局

基础单位 8px。窗口最小 1024×768。导航栏宽 220px，右侧分隔线 1px `border`。内容区最大宽 900px、居中。卡片内边距 16px，列表项间距 8px，版框正文间距 12px。

## 组件

### 导航栏
无填充直角按钮，文字 `ink`，悬停背景变 `card`、左侧出现 3px `vermilion` 色条，选中态保持色条 + 加粗。

### 卡片
背景 `card`，边框 `1px solid border`，圆角 4px，阴影 `0 1px 2px rgba(44,36,22,0.08)`。悬停时阴影加深至 `0 2px 6px rgba(44,36,22,0.12)`。

### 主按钮
直角，背景 `vermilion`，白字。悬停 `vermilionHover`，按下缩放 0.98。禁用态背景 `border`、文字 `inkSecondary`。

### 次按钮/文字按钮
透明背景，文字 `vermilion`，悬停下划线。

### 输入框
底部 1px `border` 线，聚焦时变 `vermilion` 并加粗至 2px。

### 表格
表头 `paper` 背景、`ink` 加粗、下边框 `border`。行无背景，选中行 10% `vermilion` 透明度。水平分隔线 `borderLight`。

### 阅读版框
正文区四边 `1px solid border`，内部留白 16px。左上角可选回纹装饰。

### 鱼尾页码
装饰符 `ᨯ` + 数字，颜色 `border`，字号 14px。

### 能力雷达图
QML `Canvas` 绘制 10 轴墨色线条、半透明米色填充。数据更新时 500ms ease-out 过渡。

## 交互状态覆盖

每个可交互元素须覆盖：default · hover · press · disabled。过渡 150–200ms，使用 `ease-in-out` 或 `ease-out`。

列表项入场：自上而下 30ms 错开 + 淡入。页面切换：导航触发时横向滑动，否则淡入淡出。

## 页面结构

```
┌──────────┬──────────────────────┐
│ Sidebar  │  Content Area        │
│ (220px)  │  (StackView)         │
│          │                      │
│  文库 ───│  当前页面             │
│  推荐    │                      │
│  能力    │                      │
│  设置    │                      │
└──────────┴──────────────────────┘
```

- **文库页**：搜索框 + 分页 + `TableView`（ID、标题、作者、综合难度），点击跳转阅读
- **推荐页**：数量输入 + 推荐按钮 + 结果卡片列表（标题、作者、匹配度百分比）
- **阅读页**：标题 + 版框包裹正文（18px、行高 1.8） + 底部计时器 mm:ss
- **能力页**：雷达图 + 数值列表
- **设置页**：主题切换 + 日志级别

## 暗色主题

切换后背景 #1C1812，卡片 #2A251D，文字 #D4C9A8，强调色降低饱和度至 #C75B5B。其他 Token 按比例调暗。

## 验收标准

- [ ] 无控制台错误或 QML 警告
- [ ] 所有可交互元素具备完整状态
- [ ] 中文字体正确渲染，无缺字或回退
- [ ] 全部颜色来自 Token，无外来色值
- [ ] 无 emoji 图标、无 Inter/Roboto/Arial
- [ ] 雷达图数据与数据库一致
- [ ] 阅读计时 < 30s 不触发知识追踪
- [ ] 1024×768 窗口布局正常
- [ ] 长文本不溢出，使用省略号
- [ ] 视觉风格统一，符合古籍装帧预期