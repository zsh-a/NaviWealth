# 00 · 信息架构

本文记录当前导航的设计约束。跨域 Shell 由
[LifeOS Shell](../../../../docs/architecture/lifeos-shell.md#multi-domain-ia)
拥有，AI 入口由 [AI 架构](../../../../docs/ai/ai-architecture.md#5-interaction-grammar)
拥有。具体路由清单来自领域路由与 `DomainPack`，不在设计文档复制第二份清单。

## 工作区与导航

- FinanceOS 始终启用；HealthOS、KnowledgeOS、ExecutionOS 由用户选择启用。
- Life 是跨域概览；仅启用 Finance 时，`/life` 解析为 Finance Today。
- 每个领域通过 `DomainPack.tabPaths` 声明自己的页签，通过
  `additionalPathPrefixes` 声明其他所属路径。
- 桌面布局在 1200dp 起使用一个侧栏，显示 Life、已启用领域和当前领域页签。
  紧凑布局使用领域内底栏/导航轨和工作区切换器。
- Settings、登录、引导和 `/assistant` 位于领域 Shell 之外；它们不是业务页签。
- 搜索与命令面板是全局操作入口，不占用领域页签。

导航组合入口：`apps/mobile/lib/app/domain_packs.dart`、
`apps/mobile/lib/app/routing/router_builder.dart` 和
`apps/mobile/lib/app/shell/app_dock_shell.dart`。

## Finance 页签边界

| 页签 | 拥有的内容 | 交互边界 |
|---|---|---|
| Today | 当日状态、待处理事项和 Agent 结果 | 概览保持只读；CTA 进入所属对象或流程 |
| Activity | 已发生的事件、流水和录入 | 交易、消费、转账和摄取审核从这里进入 |
| Wealth | 所拥有或承担的对象及当前状态 | 账户、持仓、负债和组合分析 |
| Plan | 决策和未来状态 | FIRE、再平衡、收益策略、预算和情景分析 |

Settings 只拥有全局偏好与配置，不嵌套为 Wealth/Plan 子页。
“Analytics”不单独成为一级栏目；分析跟随其对象或决策归属。
Finance 业务规则见 [FinanceOS](../../../../docs/domains/financeos-domain.md)。

## AI 入口

上下文操作通过 `AiIntentInvocation` 打开当前页面的 inline sheet；狭小视口可
使用全屏 dialog。`/assistant` 是保存和继续会话的全局工作区。两者使用同一套
会话、工具、提案确认与恢复协议，不增加 AI tab 或常驻聊天 Drawer。

工具与上下文按当前路由所属领域限定；全局 Assistant 才聚合全部已启用领域。
Web 不加载 AI runtime，入口按平台能力呈现不可用状态。

## 路由所有权与返回行为

领域内部使用自身 `features/<domain>/composition/` 下的路由常量。
`app/routing/route_paths.dart` 聚合全局导航，跨域跳转由 app composition 组装；
领域不能为引用全局路径而反向依赖 `app/`。

详情、表单和弹层保留来源上下文；返回行为由现有 Router、DomainTabsShell 和
AppDockShell 处理。复杂表单使用全页与 dirty guard，轻量录入使用统一 sheet
入口；不得自行添加第三套导航或表单容器。

新增路径时同时检查所属领域、启用状态、深链和返回行为。若代码与文档不一致，
依据各自拥有的契约修复并同步两者，不以文档时间或“本文优先”覆盖代码事实。
