# 00 · 信息架构 / Sitemap

## 1. 顶层导航

```
NaviWealth
├── /                    总览 (Dashboard)
├── /assets              资产
│   ├── /assets/:id      资产详情
│   └── /assets/new      添加资产
├── /transactions/new    添加交易（也可从资产详情进入）
├── /analytics           组合分析
│   ├── /analytics/return         收益率 / Benchmark
│   ├── /analytics/allocation     大类 / 行业 / 地域
│   └── /analytics/liquidity      流动性 / 期限
├── /fire                FIRE 追踪
├── /rebalance           再平衡
├── /chat                AI 助手
└── /settings            设置
    ├── /settings/account
    ├── /settings/currency
    ├── /settings/appearance
    ├── /settings/privacy
    └── /settings/about
```

> 资产详情下可深入 `/assets/:id/lots`（批次）、`/assets/:id/history`（流水），但默认作为 Tabs 在详情页内切换，不单独占路由层级（避免 Web URL 噪音）。

## 2. 主导航（按断点）

### 移动端 (<600)
**底部 Tab Bar，5 项**：

```
┌────────────────────────────────────────────┐
│  [总览]   [资产]   [+]   [分析]   [我]    │
└────────────────────────────────────────────┘
   /        /assets  ⮕   /analytics  /settings
```

中间的 `[+]` 是 **FAB-as-Tab**：点开 ActionSheet → 添加资产 / 添加交易 / AI 提问。FIRE 与 Rebalance 入口位于"分析"中，避免底栏过窄。

### 平板 (600–1240)
**左侧 NavigationRail（图标 + 文字）**，主内容右侧。AI 与 FIRE 提升为一级。

```
┌────┬───────────────────────────────────────┐
│ 总览│                                       │
│ 资产│             主内容区                  │
│ 分析│                                       │
│FIRE │                                       │
│再平衡│                                       │
│ AI  │                                       │
│─────│                                       │
│ [+] │                                       │
│ 设置 │                                       │
└────┴───────────────────────────────────────┘
```

### 桌面 (≥1240)
**三栏**：左 NavigationDrawer（永久展开）/ 中主内容 / 右详情或上下文面板（资产详情、AI 抽屉、对账详情）。

```
┌──────┬───────────────────────────┬────────────┐
│Logo  │                           │            │
│总览   │       主内容              │  详情面板   │
│资产   │                           │ (可折叠)    │
│分析   │                           │            │
│FIRE  │                           │            │
│再平衡 │                           │            │
│AI    │                           │            │
│设置   │                           │            │
└──────┴───────────────────────────┴────────────┘
```

## 3. 主要用户流（User Flows）

### 3.1 录入第一笔交易（首次使用）
```
启动 → 引导（暂略） → / (空态 Dashboard)
                        │
                        └─ "添加第一项资产" CTA
                            ↓
                          /assets/new
                            ↓
                     选择资产类型（股票/基金/现金/...）
                            ↓
                  /transactions/new?asset=<id>&kind=buy
                            ↓
                         保存 → /assets/:id
```

### 3.2 日常查询（最高频）
```
/ (Dashboard) 看净值 → 看今日 P/L
   │
   ├─ 点 "资产分布" 卡 → /analytics/allocation
   ├─ 点 "持仓 Top" 卡 → /assets/:id
   └─ 下拉刷新 → 拉行情 → 数字滚动到位
```

### 3.3 月度复盘
```
/analytics → 切到 "收益率" Tab
   ├─ 时间区间 1M / 3M / YTD / 1Y / ALL
   ├─ 切大类（股票 / 基金 / 现金 / 加密 / ...）
   └─ Benchmark 叠加（沪深 300 / S&P 500）
```

### 3.4 再平衡
```
/rebalance
   ├─ 选目标方案（保守 / 平衡 / 激进 / 自定义）
   ├─ 看偏离条
   └─ 点 "生成调整方案" → 弹出建议交易列表 → 一键填入 /transactions/new
```

### 3.5 与 AI 对话
```
/ (Dashboard) → 长按某卡 → "问 AI" 上下文菜单
   ↓
/chat?ctx=<asset-id>|<analytics-snapshot>
   ↓
AI 回复（带引用的本地资产数据 / 公开市场数据）
```

## 4. 路由稳定性 / Web URL 设计原则

- 全部路由可深链（移动端使用 `flutter_web_plugins.urlStrategy = PathUrlStrategy()`，已在 FIR-14 启用）。
- 列表筛选用 query string：`/assets?type=stock&account=hsbc-港股`，便于 Web 上书签 / 分享。
- ID 用 ULID/UUID 字符串，禁止递增数字（隐私 + 防遍历）。
- 详情页 Tab 用 fragment：`/assets/:id#lots`，避免 path 层级膨胀。

## 5. 全局元素

| 元素 | 位置 | 说明 |
|------|------|------|
| 顶部 AppBar | 所有页面 | 标题 + 页面操作（搜索/筛选/导出） |
| 全局搜索 | AppBar 右上（mobile 折叠到图标，desktop 永久展开） | 搜索资产、交易、设置项 |
| 主题切换 | 设置 + 桌面端 AppBar 右上 | system / light / dark |
| 同步状态指示 | AppBar 右上小点 | ●online · ◐syncing · ○offline |
| Snackbar | 屏幕底部 | 写操作反馈、错误重试 |
| FAB | mobile / tablet | 仅在能新增的页面出现（资产、交易、再平衡） |

## 6. 与现有路由的差异

当前 `app/router.dart` 仅 4 个 Tab（home / assets / analytics / settings）。本设计在不破坏现有路由的前提下：

- 新增：`/assets/:id`、`/assets/new`、`/transactions/new`、`/fire`、`/rebalance`、`/chat`、`/settings/*` 子路由。
- 重构 `_RootShell`：依据 `MediaQuery` 的宽度切换底部 Tab / NavigationRail / NavigationDrawer 三种 shell（详见 [01-responsive-layout.md](./01-responsive-layout.md)）。

> 实施由后续 `FIR-15`（路由基础设施）落地，本文件锁定 IA。
