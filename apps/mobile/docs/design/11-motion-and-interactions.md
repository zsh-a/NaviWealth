# 11 · 动效与交互

> 财务 App 的动效原则:**克制、信息驱动、反应快**。每一个动画都要回答"它在告诉用户什么变了"。
> 本文与实现同步(SSOT 为代码):`design_system/tokens/motion_tokens.dart`、
> `design_system/tokens/app_motion_policy.dart`、`design_system/theme/app_page_transitions.dart`。

## 1. 动效 Token(实现值)

| Token | 值 | 用途 |
|-------|-----|------|
| `Motion.fast` | 120ms | 按压反馈、chip 切换 |
| `Motion.medium` | 220ms | 组件状态变化、内容过渡 |
| `Motion.ambient` | 300ms | 表单区域展开等氛围级变化 |
| `Motion.slow` | 360ms | 页面转场入场 |
| `Motion.chartEnter` | 600ms | 图表首次数据揭示 |
| `Motion.ticker` | 800ms | 数字滚动 / 变化脉冲 |
| `Motion.shimmerCycle` | 1400ms | 骨架 shimmer 循环 |

曲线:`Motion.standard` = `Cubic(0.2,0,0,1)`(导出的 `emphasized` token 是它的别名),
`Motion.emphasizedDecelerate` = `Cubic(0.05,0.7,0.1,1)`,
`Motion.standardDecelerate` = `Cubic(0,0,0,1)`,
`Motion.standardAccelerate` = `Cubic(0.3,0,1,1)`。无 spring 体系(有意省略)。

语义别名:`tapFeedback=fast`、`componentChange=medium`、`contentTransition=medium`、`pageTransition=slow`。

## 2. 动效角色与 reduce-motion 分级

所有应用动画必须通过 `AppMotionPolicy.duration(context, d, role: …)` 取时长,
禁止直接读 `MediaQuery.disableAnimationsOf`(`tool/lint-motion-policy.sh` 拦截)。

| 角色 | 正常 | reduce-motion |
|------|------|----------------|
| `transition`(导航/浮层) | 全速 | **时长减半**,滑动降级为 cross-fade |
| `decorative`(shimmer/stagger/按压/图表入场) | 全速 | 禁用(0ms) |
| `status`(数字滚动/同步指示) | 全速 | 禁用;状态一律双编码(色 + 图标/文字),不丢信息 |

## 3. 数字滚动与变化高亮(已实现)

- 组件:`AnimatedMoneyText`(`status` 角色)。
- 800ms(`Motion.ticker`)/ 小幅同号变化 300ms(`Motion.ambient`);
  `minDeltaThreshold` 可让密集表格的小 tick 直接落位。
- **变化脉冲**:滚动同时在数字背后打一层方向色 wash
  (正弦 0 → 12% alpha → 0,颜色走 `theme.market.roleForDelta`,
  自动跟随涨跌色偏好与色盲模式);`highlightChanges: false` 可关。

## 4. 骨架屏

- 首次进入且无本地缓存 → 页面级具名骨架(`widgets/skeletons/`,`PageSkeletonShell`)。
- spinner(`FCircularProgress`)只用于按钮内 busy 态与 "明确不可避免的等待"(AI 生成中)。
- shimmer 1.4s 循环;reduce-motion 下静止。

## 5. 页面过渡(已实现)

- **主题级全局默认**:`AppPageTransitionsBuilder` 注册在 `pageTransitionsTheme`
  (android/linux/windows/macOS/fuchsia),所有 `GoRoute(builder:)` 自动获得:
  - 窄屏(<600):右侧全宽滑入(`emphasizedDecelerate`);
  - 宽屏(≥600):16dp 位移 + 淡入 —— 宽窗口的全宽滑动是视觉噪音;
  - reduce-motion:纯 cross-fade。
- iOS 保留 `CupertinoPageTransitionsBuilder`(边缘右滑返回手势)。
- 命令式导航用 `buildAppPageRoute`;共享元素用 `OptionalHero`。
- Tab 切换有意不做动画(图表 + 玻璃拟态的全屏合成代价过高)。

## 6. 列表交互(已实现)

- **首帧入场 stagger**:activity feed 与持仓列表的首屏行(≤8–10 行)
  以 30ms 间隔 `FadeSlideIn`(fade + 6dp 上滑);之后的构建(滚动、加载更多、
  数据 tick)直接出现,表格不"晃"。
- 下拉刷新:唯一入口 `AppRefreshIndicator`(品牌色进度、raised 面盘、
  2.2 stroke),覆盖四域 + Life;禁止直接使用 Material `RefreshIndicator`。

## 7. 图表动效(已实现)

- **首次数据揭示**:`NwLineChart` 首帧从左到右 600ms(`Motion.chartEnter`)
  clip 揭示(`decorative` 角色,reduce-motion 直接呈现)。
- 数据更新走 fl_chart 内建 tween morph。
- 十字线/tooltip 跟手 0 延迟(独立于图表重建的触摸层)。

## 8. 反馈

- 通知唯一路径 `AppMessenger`(toast);持久性状态用 `AppStatusBanner`;
  AI 写操作配 `PersistentUndoBanner`。`SnackBar` 被 lint 封禁。
- **触觉语法**:一律经 `AppInteraction.signal(intent)` 的七种语义意图
  (commit / select / reveal / navigate / destroy / success / failure);
  禁止直接调用 `Haptics.*`(`SoftCard`、`FloatingGlassNavBar` 等组件已内建)。

## 9. 按压与桌面态(已实现)

- 按压缩放**全 App 单值** `theme.press.scale = 0.98`
  (`SoftCard` / `PressableScale` / FAB 共用,无 per-site 覆盖)。
- 交互卡片 hover:阴影抬升(`AppShadow.cardHover`)+ `click` 光标。
- **键盘焦点**:交互卡片可聚焦,焦点环 = 2dp `primary` 描边,
  Enter/Space 激活并触发与点按相同的触觉意图。
- `Cmd/Ctrl+1..N` 作用于当前域 tab;`Cmd/Ctrl+K` 命令面板。

## 10. AI 流式

- 逐 token fade-in;光标闪烁 `Motion.caretBlink`(900ms);
  工具调用展开 `AnimatedSize` + 箭头旋转(`componentChange`)。

## 11. 性能预算

- 动画期间主线程 ≤ 8ms/frame(120Hz)/ 16ms(60Hz)。
- 数字滚动与列表 stagger 并存时,stagger 保持 30ms 且行数封顶(≤10)。
- 图表主体包 `RepaintBoundary`;触摸层独立重建。

## 12. Don't List

- ❌ 数字闪烁颜色超过 1.2s(脉冲为 800ms 单次)。
- ❌ 弹窗中嵌套弹窗动画(用 Sheet 链式 `closeSheetThen`)。
- ❌ 非用户操作的卡片随机晃动/弹跳。
- ❌ 页面级 spinner(首选骨架屏;lint 锁 0)。
- ❌ 绕过 `AppMotionPolicy` 自读系统动效设置。
