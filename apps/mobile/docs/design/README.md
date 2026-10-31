# NaviWealth · 设计文档

> 关键页面线框图 + 高保真稿（Light / Dark） + 关键交互动效 + 设计走查。

这些文档提供页面布局、交互与 Token 使用约束。跨域导航以
[LifeOS Shell](../../../../docs/architecture/lifeos-shell.md) 为准，AI 行为以
[AI 架构](../../../../docs/ai/ai-architecture.md) 为准，实际路由与设计值以代码中的
registry 和 token 为准。页面示意不另行定义全局架构。
全局澄白视觉语言见根目录 [DESIGN.md](../../../../DESIGN.md)，
Flutter 的 Impeccable 工作流边界见 [.agents/IMPECCABLE.md](../../../../.agents/IMPECCABLE.md)。

## 阅读顺序

| # | 文档 | 内容 |
|---|------|------|
| 00 | [信息架构 / Sitemap](./00-information-architecture.md) | 工作区、领域页签、路由所有权与 AI 入口 |
| 01 | [响应式策略](./01-responsive-layout.md) | 窗口分类、现有 Shell、表单与输入适配 |
| 02 | [Dashboard 总览](./02-dashboard.md) | 净资产、今日 P/L、资产分布、FIRE、待办 |
| 03 | [资产列表](./03-assets-list.md) | 多账户、分组、筛选、移动卡片 ↔ 桌面表格 |
| 04 | [资产详情](./04-asset-detail.md) | 持仓概况、走势、批次（Lot）、交易流水 |
| 05 | [添加交易](./05-add-transaction.md) | 买/卖/股息/拆股/转账，手动 + 模板复用 |
| 06 | [组合分析](./06-analytics.md) | 大类饼图、行业/地域、收益率、Benchmark |
| 07 | [FIRE 追踪](./07-fire.md) | 目标、储蓄率、达成预测、敏感度 |
| 08 | [再平衡](./08-rebalance.md) | 目标权重 vs 实际、偏离、操作建议 |
| 09 | [AI 对话](./09-ai-chat.md) | Assistant 工作区、上下文 sheet、提案与平台边界 |
| 10 | [设置](./10-settings.md) | 账户、币种、主题、涨跌色、隐私、关于 |
| 11 | [动效与交互](./11-motion-and-interactions.md) | 数字滚动、骨架屏、过渡曲线、键盘快捷键 |
| 12 | [可用性自查](./12-usability-self-check.md) | 走查清单、可访问性、暗黑模式、空态/错误态 |
| 13 | [Web 字体子集化](./13-web-fonts.md) | Noto Sans SC 子集流水线、`@font-face` 加载、首屏 335,000 B（约 327 KiB）预算 |
| 14 | [图表库 / Charts](./14-charts.md) | fl_chart vs syncfusion 选型、统一封装、主题接入、降采样、钻取 |
| 15 | [设计系统契约](./15-ui-refactor-blueprint.md) | 主题解析、语义角色、共享组件、领域组合与验证 |

## 与代码的关系

- **设计 Token + 组件库**：本文档以 Token 名（如 `color.fg.primary`、`type.body.md`、`space.4`）引用；代码中对应到 `lib/design_system/`。
- **图表封装**：已选 `fl_chart` 作为底层渲染器，统一封装在 `lib/design_system/charts/`；详见 [14-charts.md](./14-charts.md)。所有业务页面（分析、FIRE、再平衡）通过 `Nw*Chart` 系列消费，不直接 import `fl_chart`。
- **路由与 Shell**：响应式策略与路由结构对齐 `lib/app/routing/route_paths.dart`、`lib/app/routing/router.dart` 与 `lib/app/shell/app_dock_shell.dart`。

## 标记约定

- `[L]` light mode 下生效；`[D]` dark mode 下生效。
- `〈token.name〉` 表示设计 Token 引用；实现必须映射到现有语义 token，不自行引入 fallback 颜色。
- ASCII 线框中：`█` 实心填充区，`▒` 占位/骨架，`···` 文字内容，`▸` 折叠/可展开，`*` 选中态。
- 所有金额示例使用 `¥` 前缀但展示规则按 [10-settings.md](./10-settings.md) 中的"数字与货币展示规范"。
