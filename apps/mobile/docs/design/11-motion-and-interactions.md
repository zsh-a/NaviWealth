# 11 · 动效与交互

> 财务 App 的动效原则：**克制、信息驱动、反应快**。每一个动画都要回答"它在告诉用户什么变了"。

## 1. 动效曲线 Token

| Token | curve | duration |
|-------|-------|----------|
| `motion.standard` | `Curves.easeInOutCubic` | 200ms |
| `motion.emphasized` | `Curves.easeOutCubic` | 320ms |
| `motion.decelerate` | `Curves.fastOutSlowIn` | 240ms |
| `motion.linear` (流式) | `Curves.linear` | n/a |
| `motion.spring.standard` | `SpringDescription(mass:1, stiffness:180, damping:22)` | ~ |
| `motion.spring.gentle` | `SpringDescription(mass:1, stiffness:120, damping:18)` | ~ |

> 系统 `reduceMotion` 开启时，所有动画 duration → 0 或减半（保留 cross-fade）。

## 2. 数字滚动 (Number Roll)

- **场景**：净值、估值、P/L、KPI。
- **机制**：从旧值动画到新值，按位逐个翻动；位间错峰 30ms。
- **曲线**：`motion.emphasized`，duration 600ms（首次）/ 240ms（更新）。
- **变化高亮**：上涨用涨色 12% alpha 背景 fade-in/out（800ms）；下跌反之。
- **实现提示**：`AnimatedNumber` widget，内部用 `TweenAnimationBuilder<num>`。

## 3. 骨架屏 (Skeleton)

- **触发**：首次进入页面且无本地缓存。
- **形状**：圆角矩形（与最终内容同高），渐变 shimmer 波从左到右循环 1.4s。
- **不使用 spinner**：spinner 只在"明确不可避免的等待 > 1s"（如 AI 生成中）出现。

## 4. 页面过渡

| 过渡 | 平台 | 实现 |
|------|------|------|
| 标准 push（mobile） | iOS-style slide / Material container transform | `MaterialPageRoute` + `transitionsBuilder` |
| Tab 切换 | crossFade 200ms | `AnimatedSwitcher` |
| Sheet 弹起 | 240ms decelerate, dim 50% | `showModalBottomSheet` |
| Dialog | scale 0.96 → 1 + fade 200ms | M3 默认 |
| Drawer (desktop) | 240ms slide from right | 自定义 |

## 5. 列表交互

- **进入入场**：列表项 stagger 30ms，每项 fade + 8dp 上滑（仅首次进入）。
- **删除**：`AnimatedList.removeItem` 高度收起 200ms + 横向滑出 240ms。
- **排序变化**：使用 `AnimatedReorderableList`，每项位移 motion.emphasized。
- **下拉刷新**：M3 RefreshIndicator（背景 `surfaceContainerHigh`，进度色 `primary`）。

## 6. 图表动效

- **进入**：曲线从左到右 stroke-draw 600ms `easeOutCubic`；面积填充随后 fade-in 200ms。
- **数据更新**：旧曲线 morph 到新曲线 320ms（点对点 lerp）。
- **缩放/平移**：跟手 60fps；松手后用 fling spring 收尾。
- **Hover/十字线**：跟手 0ms 延迟；tooltip 以 motion.standard 80ms cross-fade 切换数据。

## 7. 反馈

- **Snackbar**：`SnackBar` from bottom slide-up 240ms；持续 4s（普通）/ 8s（含撤销）。
- **触觉**：长按、删除确认、撤销点击 → `HapticFeedback.lightImpact`。
- **Toast 错误**：左上角 Banner，6s 自动消失，可手动关。

## 8. AI 流式

- **逐 token 渲染**：60–120 tok/s 视觉速率；新文本 fade-in 80ms。
- **光标**：`▌` 字符，1Hz 闪烁，宽 0.5em，颜色 `primary`。
- **工具调用展开**：`AnimatedSize` + 折叠箭头旋转 180°，duration 200ms。

## 9. 全局快捷键 / 焦点

- **焦点环**：键盘焦点元素显示 2dp `primary` 描边 + 12% alpha 内阴影。
- **`Tab` 顺序**：自上而下、自左而右；Dialog 内 trap 焦点。
- **shortcut 帮助**：`?` 弹出半透明覆盖层，列出当前页面所有快捷键。

## 10. 性能预算

- 动画期间主线程 ≤ 8ms / frame（120Hz 设备）/ 16ms（60Hz）。
- 卡顿边线：连续 4 帧丢帧时降级动画到 cross-fade。
- 数字滚动 + 列表 staggered enter 同时存在时，stagger 缩短到 15ms。

## 11. 全局触发器（Triggers）

| 时机 | 动效 |
|------|------|
| 应用冷启动后第一次显示净值 | 数字滚动 + 涨/跌色背景 fade |
| 完成同步 | 顶部细线 progress 完成后 ✓ 200ms 后消失 |
| 完成大型操作（导入 CSV） | 中央 success ✓ 圆 + scale 0.6→1 spring |
| 跨越 FIRE 里程碑 | 全屏祝贺动画 (confetti) 1.6s + Snackbar |
| 网络断开/恢复 | 顶部 banner 滑入/滑出 240ms |

## 12. 减弱动效（Reduce Motion）

`MediaQuery.disableAnimations` 或自定义 Settings 项启用后：
- 数字滚动：禁用，直接到位。
- 骨架 shimmer：静止灰块。
- 页面过渡：fade-only，180ms。
- confetti：替换为静态 ✓ + Snackbar。

## 13. Don't List

- ❌ 数字闪烁颜色超过 1.2s。
- ❌ 弹窗中嵌套弹窗动画（应该用 Drawer / Sheet 替代）。
- ❌ 非用户操作的卡片随机晃动 / 弹跳。
- ❌ 不必要的 spinner（首选骨架屏）。
- ❌ "成功"动画在错误场景 false-positive。

## 14. 实现锚点（Flutter）

| 概念 | 包/类 |
|------|-------|
| 数字滚动 | 自封装 + `TweenAnimationBuilder` |
| 骨架屏 | `shimmer` 包或自封 `LinearGradient + Animation` |
| 列表入场 | `flutter_staggered_animations` 或自封 |
| 列表删除 | `AnimatedList` |
| 图表动效 | `fl_chart` 内置 `swapAnimationDuration` |
| Confetti | `confetti` 包（仅 FIRE 里程碑） |
| 触觉 | `HapticFeedback` |
| 快捷键 | `Shortcuts` + `Actions` |

> 选包 / 自封的最终决定在 FIR-22 落地。
