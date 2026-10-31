# 15 · 设计系统契约

本文规定当前主题、组件和领域 UI 的使用边界，不保留已完成的迁移计划。
跨域导航由 [LifeOS Shell](../../../../docs/architecture/lifeos-shell.md) 拥有，
AI 交互由 [AI 架构](../../../../docs/ai/ai-architecture.md) 拥有。
设计值以 Dart 源码为准，设计工具读取生成的 token export。
全局视觉语言与默认 token 快照见根目录 [DESIGN.md](../../../../DESIGN.md)，
Impeccable 的 Flutter 使用边界见 [.agents/IMPECCABLE.md](../../../../.agents/IMPECCABLE.md)。

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

外观设置保留主题、强调色和材质等有明确效果的控制，不再提供经典 / 精致预览选择器。
运行时兼容已保存的经典 / 精致视觉偏好，使用同一套导航、组件和表单状态。
两个预设共用中性表面，普通卡片无常驻阴影和渐变；经典使用紧凑圆角，精致使用
连续圆角、统一字体及阻尼弹层曲线。`AppVisualStyle` 与明暗模式、系统高对比度、
强调色、涨跌色和材质效果独立；偏好保存在 SharedPreferences。
缺失或无效偏好默认精致、鸢尾蓝（`indigo`）和仅导航通透（`navigation`）；
已保存的经典、青色、紫色、实色和全通透选择仍按原值解析。
Material、Forui 和语义主题必须同时消费同一 visual style；不要按预设重建
Navigator、ProviderScope 或表单。外观预览复用正式 theme 和 SoftCard。

材质默认仅导航通透：浮动 dock 可使用 live backdrop，sticky、sheet 和 overlay
保持不透明。实色关闭 live blur；全通透是显式选择，可按 role 开启更多 chrome
材质。系统高对比度优先取消通透与装饰光场，表单始终不透明。
手机 sheet 遮罩只使用 AnimatedModalBarrier 颜色动画，
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
- 按钮外观由 `theme/app_button_styles.dart` 统一提供给 Forui 和共享封装。
  普通 primary 使用浅色调填充，辅助操作用轻量中性 secondary，边界操作用 outline，
  行内低强调动作使用透明底的 `AppQuietButton`。同一操作组通常只有一个 primary。
  最终提交使用 `AppButtonEmphasis.filled`，`AppFormActionBar` 在固定操作区内提供
  此强调，sheet footer 显式指定；字段内命令继续使用浅填充。实色填充与链接、焦点的
  accent 独立解析，深色模式压低填充亮度，文字和各交互状态保持 AA 对比度。
  普通文字和图标按钮共享经典 12dp / 精致 16dp 圆角，dock 的显式 ring 保留圆形。
  触屏所有尺寸至少 48dp；桌面按位置选择紧凑尺寸。Action 与 Busy 默认同为 lg，
  异步状态不决定尺寸。Busy 保留原按钮底色、文字字号与占位，显示进度并阻止重复
  点按、键盘和语义激活；长文案允许换行，不缩小系统字体。
- 页面背景与内容表面使用中性色阶；默认不叠加时段氛围染色。普通卡片以底色和间距
  分层，浅色交互卡片仅在 pointer hover 使用贴近表面的轻阴影；深色使用明度反馈。
  阴影保留给菜单、弹窗及浮动导航，使用中性色和较短偏移；高对比度保留可见边界。
- 图表短时间范围、展示维度与页面内的少量互斥分类使用 `SegmentedRow.inline`：居中的内容宽度、轻量文字与选中短线，
  不铺满图表宽度或增加整条容器背景。保留 48dp 触控区域，按实际文字宽度与系统
  字体缩放均衡换行；不隐藏选项，也不截断标签。普通表单选择继续使用默认分段样式。
  财富范围、资产分布的类别 / 币种、投资趋势的指标 / 范围、现金流趋势与汇率历史
  共用此变体；健康趋势的分组与时间范围、知识库内容类型、执行任务视图及搜索类型
  也遵循相同契约。多选标签、数据录入与持久化偏好继续使用各自的表单和筛选组件。

## 字体与格式化

读取 `context.appTheme.type`，遵守系统 text scaling，避免 feature 自建字号层级。
Display 使用自托管 Inter 的 `display` / `displaySmall` / `displayCompact`
（48 / 32 / 26），页面级金额为 48dp medium；`numericDisplay` 是 32dp 的次级金额。
精致预设保留字号、字重和 tabular figures，行高在底表上乘以 0.96，26dp 以下字距归零。
金额与图表使用对应 `numeric*` / `chartCaption`。`TypographyTokens` 是主题底表，
业务 UI 不直接读取 display、headline 或 numeric 样式，避免绕过精致预设的字体、
字距和行高；`lint-typography.sh` 守护此边界。
金额、百分比、日期和数字复用 `AppFormatters`、`MoneyText` / `SignedMoneyText`、
`DeltaText` 等组件。金额方向与隐私占位由组件处理；不能用字符串拼接绕过本地化、
隐私和涨跌色偏好。数字使用 tabular figures，显示字号可强调整数部分，语义标签
仍保留完整值。

## 响应式与领域组合

窗口分类与限宽使用 `Breakpoints`，布局规则见
[响应式策略](01-responsive-layout.md)。Shell 的领域清单、页签、accent、settings
和 Agent presentation 通过 `DomainPack` 贡献，由 `app/` 组合。
领域内部只依赖自身路由；跨域 composition 不放入 `design_system/` 或 `core/`。

Finance Today 与 Wealth 的已建立数据视图限宽 1200dp。Today 在可用内容宽度
达到 `contentTwoColumn` 时把常用操作放到净值旁；窄屏与大字体按阅读顺序堆叠。
Wealth 把余额、区间变化与历史曲线组合为一个主区域，对象入口作为辅助区域，
不重复展示第二个净值。加载骨架使用同样的主辅布局。

`AdaptiveSummaryGrid` 中没有辅助项的 featured 占满当前行；它与
`AdaptiveSupportingPane` 都使用稳定的子组件层级，保持窗口缩放或字体放大时的
局部状态、输入内容与键盘焦点。连续列表仍占满一行。
导入审核默认显示账户上下文、队列数量、批量选择与固定筛选；搜索从页头展开并
聚焦，已恢复的查询直接可见。排序、分类、分组按需展开；账户在大字体下回到
完整表单布局，搜索、校验和禁用语义保持一致。

`DomainPack.accent` 仅影响 chrome。页面内容、状态与金融涨跌继续使用语义主题。
新增领域不应要求复制 Shell、另建侧栏或增加 feature 分支到主题 resolver。
Finance chrome 使用鸢尾蓝，Knowledge 保留紫色；当前领域清单与 accent
映射由 registry 和 `DomainAccents` 拥有，不在设计文档中另立清单。

浮动 dock 使用 20dp 连续圆角，普通高度为 64dp。`floatingGlassNavBarHeight`
按当前 `TextScaler` 的实际 11dp 标签增量和 1.15 行高增加高度；Shell 的底部内容预留
复用同一函数，再加 dock 间距与 safe area。不要固定大字体高度或在页面重复留白。

## 动效与材质

应用动效经过 `AppMotionPolicy`，交互复用共享原语；实现约束见
[动效与交互](11-motion-and-interactions.md)。Reduced motion 保留可识别的状态变化，
停止装饰性空间运动。关键状态不能只通过动效或声音表达。

Live backdrop 由 `GlassSpec` 的 role 和材质偏好统一控制；默认只对导航 chrome 开启，
全通透选择才允许 sheet 等额外 role。内容模块保持不透明，sticky chrome 复用共享光场，
调用方不添加独立的滚动模糊层。Glass 光效不能替代 focus、selection、busy 或错误
语义，也不能增加第二套手势识别。系统高对比度不使用装饰性光场。

## 验证

按改动运行主题分层、Material chrome、格式化、字体、AsyncValue、交互原语和
motion policy lint；脚本清单由 CI 维护。主题变更运行对比度测试及 token export
测试。组件或布局变更运行对应 widget/golden 测试，检查窄屏、宽屏、text scaling、
深浅主题与 reduced motion。代表性的 Wealth、Today、导入审核另覆盖精致预设；
截图 harness 同时传递 Material / Forui / AppThemeScope 的 visual style。
视觉基线使用 CI 指定的 Linux Flutter 版本生成。
跨域 Shell 变更额外检查启用状态、路由和键盘导航。

本次澄白更新的视觉证据位于 `.impeccable/review/goldens/`，来自 Flutter widget
renderer，覆盖代表性深浅主题、领域页面、宽屏及大字体导航。HTML 方向稿和 sidecar
预览只表达方向或组件翻译；它们不是 Flutter 验证。真机材质/性能和 Linux golden
基线比对尚未完成，不能由这些截图推断通过。该实现由代码和向量图标构成，未引入
需要溯源的 shipping raster asset。
