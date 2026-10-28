# 15 · 设计系统契约

本文规定当前主题、组件和领域 UI 的使用边界，不保留已完成的迁移计划。
跨域导航由 [LifeOS Shell](../../../../docs/architecture/lifeos-shell.md) 拥有，
AI 交互由 [AI 架构](../../../../docs/ai/ai-architecture.md) 拥有。
设计值以 Dart 源码为准，设计工具读取生成的 token export。

## 主题解析与读取

`apps/mobile/lib/design_system/theme/theme_resolver.dart` 的纯函数
`resolveAppTheme(ThemeInputs)` 统一解析亮度、涨跌色模式、系统高对比度、accent seed
和 density，以及独立的 visual style、material style，输出 `AppThemeData`。
页面通过 `context.appTheme` 读取结果，不独立
推导主题，也不直接混用多份颜色表。

| 主题语义 | 用途 |
|---|---|
| `surfaces` / `content` | 表面层级和内容对比度 |
| `accent` / `status` | 交互强调和成功、警告、错误等状态 |
| `market` | 跟随用户偏好的涨跌方向色 |
| `categorical` | 分类色的亮度适配 |
| `type` | 语义字体层级 |
| `glass` | chrome 材质预算 |
| `visual` | 连续圆角、共享表面形状与弹层动效 |
| `press` / `card` / `badge` / `divider` / `metricTile` | 共享组件规格 |

`ColorRole` 统一提供 `fg`、`container`、`onContainer`、`onFg`。SemanticColors、
MarketColors、AccentColors 是 resolver 的数据来源，业务页面消费解析后的语义。
高对比度直接跟随系统，增强文字和边界并取消装饰性材质，不提供独立设置。
不再提供 OLED 纯黑模式；旧的 surface_style 偏好不再读取，回退所选视觉预设的普通明暗配色。
涨跌不能硬编码红绿，状态色和分类色也不能被领域 accent 替换。

外观设置支持经典 / 精致两个视觉预设，使用同一套导航、组件和表单状态。
经典保留既有配色；精致使用中性色阶、连续圆角、减少装饰性描边与阴影、
统一字体及阻尼弹层曲线。`AppVisualStyle` 与明暗模式、系统高对比度、
强调色、涨跌色和材质效果独立；偏好保存在 SharedPreferences，旧安装默认经典。
Material、Forui 和语义主题必须同时消费同一 visual style；不要按预设重建
Navigator、ProviderScope 或表单。外观预览复用正式 theme 和 SoftCard。

材质默认实色，通透需用户选择；系统高对比度优先取消通透。
表单始终不透明。手机 sheet 遮罩只使用 AnimatedModalBarrier 颜色动画，
不得对整页做背景过滤；sheet Future 保持 pop 时返回的既有契约，dock 隐藏持续到退场
动画真正结束，链式导航等待 route.completed。AI sheet 的键盘由内容处理，路由不重复避让。

## Token 与生成物

间距、圆角、线宽、断点、字体和动效使用
`apps/mobile/lib/design_system/tokens/`。不要在 feature 中重建颜色或尺寸系统。
`apps/mobile/design_tokens/tokens.json` 是生成导出，不能手改；更新流程见
[Design Tokens](../../design_tokens/README.md)。

新增 token 时同步 exporter，修改值后重建导出。CI 的
`export_design_tokens_test.dart` 校验生成物新鲜度。

## 页面与组件

- 使用 Forui 与本地设计系统；表面优先 `SoftCard` / `AppSection`，按钮使用共享
  `FButton` 封装。卡片用于重复对象、工具或弹层，不嵌套卡片，不把每个段落都装卡。
- `AppPageScaffold` 与已有任务、详情模板负责页面结构；概览可使用 `BriefScaffold`。
  选择与任务匹配的模板，不要求所有领域页面共用一种布局。
- 复杂多段记录表单使用 `AppFormPageScaffold` 和 `confirmLeave`；轻量单对象录入
  使用 `showAppFormSheet` / `showGuardedFormSheet` 和 `dirtyGuard`。
- AsyncValue 展示复用 `app_async_helpers.dart`；空态、错误与重试使用共享状态组件。
  状态必须有具体动作，错误不能被空态吞掉。
- 用户操作反馈走共享 `AppMessenger`、busy/action button 和提交协议。成功仅在
  操作完成后呈现；已有 wrapper 提供 haptic 时，调用方不重复触发。

## 字体与格式化

读取 `context.appTheme.type`，遵守系统 text scaling，避免 feature 自建字号层级。
金额、百分比、日期和数字复用 `AppFormatters`、`MoneyText` / `SignedMoneyText`、
`DeltaText` 等组件。金额方向与隐私占位由组件处理；不能用字符串拼接绕过本地化、
隐私和涨跌色偏好。数字使用 tabular figures，显示字号可强调整数部分，语义标签
仍保留完整值。

## 响应式与领域组合

窗口分类与限宽使用 `Breakpoints`，布局规则见
[响应式策略](01-responsive-layout.md)。Shell 的领域清单、页签、accent、settings
和 Agent presentation 通过 `DomainPack` 贡献，由 `app/` 组合。
领域内部只依赖自身路由；跨域 composition 不放入 `design_system/` 或 `core/`。

`DomainPack.accent` 仅影响 chrome。页面内容、状态与金融涨跌继续使用语义主题。
新增领域不应要求复制 Shell、另建侧栏或增加 feature 分支到主题 resolver。

## 动效与材质

应用动效经过 `AppMotionPolicy`，交互复用共享原语；实现约束见
[动效与交互](11-motion-and-interactions.md)。Reduced motion 保留可识别的状态变化，
停止装饰性空间运动。关键状态不能只通过动效或声音表达。

Live backdrop 只用于主题允许的浮动 dock 和 modal sheet；内容模块保持不透明，
sticky chrome 使用共享静态光场。Glass 光效不能替代 focus、selection、busy 或错误
语义，也不能增加第二套手势识别。系统高对比度不使用装饰性光场。

## 验证

按改动运行主题分层、Material chrome、格式化、字体、AsyncValue、交互原语和
motion policy lint；脚本清单由 CI 维护。主题变更运行对比度测试及 token export
测试。组件或布局变更运行对应 widget/golden 测试，检查窄屏、宽屏、text scaling、
深浅主题与 reduced motion。跨域 Shell 变更额外检查启用状态、路由和键盘导航。
