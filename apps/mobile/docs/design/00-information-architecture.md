# 00 · 信息架构 / Sitemap

## 1. 顶层导航

当前产品只保留一套清晰 IA。旧 URL 不再重定向；访问旧路径会进入路由错误页。

```
NaviWealth
├── /                         总览
├── /portfolio                投资组合
│   ├── /portfolio/:assetId   资产详情
│   ├── /portfolio/new/cash   现金资产
│   ├── /portfolio/new/deposit
│   ├── /portfolio/new/wealth
│   ├── /portfolio/physical/:id
│   ├── /portfolio/liabilities
│   └── /portfolio/liabilities/:id
├── /activity                 流水
│   ├── /activity/expenses
│   ├── /activity/expenses/new
│   ├── /activity/expenses/report
│   ├── /activity/accounts
│   ├── /activity/accounts/new
│   ├── /activity/accounts/transfer
│   ├── /activity/accounts/journal
│   └── /activity/trade
├── /plan                     规划
│   ├── /plan/analytics
│   ├── /plan/fire
│   └── /plan/rebalance
├── /ai                       AI 财务助手
└── /settings                 设置
    ├── /settings/devices
    ├── /settings/fx-rates
    ├── /settings/backup
    └── /settings/logs
```

## 2. 主导航

所有断点共享四个一级目的地：

```
总览        /
投资组合    /portfolio
流水        /activity
规划        /plan
```

AI 与设置作为全局入口出现在总览 AppBar、命令面板和快捷键中，不占用底部主导航。新增动作由统一的全局 `+` 面板承载：记账、交易、资产、转账、负债。

### 移动端 (<600)

底部玻璃导航栏展示四个主入口，右下角全局 `+` 打开动作面板。内容区为单列布局，列表与详情通过路由切换。

### 平板 (600–1240)

左侧 Rail 展示四个主入口，右侧为主内容区。全局 `+` 固定在内容区右下角。

### 桌面 (≥1240)

左侧可折叠 Sidebar 展示四个主入口。投资组合与账户等高信息密度页面使用 master-detail；全局 `+` 固定在内容区右下角。

## 3. 页面职责

- `总览 /`：净资产主视觉、关键变化、资产分布、趋势、3-5 个可执行洞察。
- `投资组合 /portfolio`：资产、负债、持仓详情；移动端单列，桌面端 master-detail。
- `流水 /activity`：支出、账户、交易、转账与统一时间线。
- `规划 /plan`：分析、FIRE、再平衡的规划中心，二级页面展示真实摘要与明细。
- `AI /ai`：财务助手，可从全局入口或命令面板进入。
- `设置 /settings`：账户、同步、偏好、数据、安全与诊断。

## 4. 路由原则

- 所有业务导航使用 `lib/app/route_paths.dart` 中的常量或 helper。
- 不保留旧路径兼容；旧路径应 404 或展示错误页。
- 列表选择状态使用 query string，例如 `/portfolio?selected=<id>`。
- 详情 ID 使用不透明字符串；展示前按路由 helper 编码。

## 5. 全局元素

| 元素 | 位置 | 说明 |
|------|------|------|
| AppBar | 页面顶部 | 页面标题与局部操作 |
| 命令面板 | 全局快捷键 | 导航、主题、语言、AI |
| `+` 动作面板 | Shell 右下角 | 记账、交易、资产、转账、负债 |
| Snackbar | 屏幕底部 | 写操作反馈、错误重试 |
| AI 入口 | 总览 AppBar / 快捷键 / 命令面板 | 打开助手页或助手浮层 |

