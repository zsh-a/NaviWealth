# 01 · 响应式策略

## 1. 断点

| 名称 | 范围 | 主导航 | 主内容栏数 | 默认输入设备 |
|------|------|--------|-----------|--------------|
| **mobile**  | `< 600`     | 底部 Tab（5 项） | 1 | 触摸 |
| **tablet**  | `600–1239`  | NavigationRail | 1–2 | 触摸 / 鼠标 |
| **desktop** | `≥ 1240`    | NavigationDrawer + 内容 + 详情面板 | 2–3 | 鼠标 + 键盘 + 滚轮 |

> 1240 的来源：保证桌面三栏布局下，主内容仍有 ≥ 720dp 的可读宽度（240 nav + 720 content + 280 detail）。低于此值降级为两栏（隐藏详情面板）。

`MediaQuery.sizeOf(context).width` 取一次，封装成 `Breakpoint` 枚举：

```dart
enum Breakpoint { mobile, tablet, desktop }

extension BreakpointX on BuildContext {
  Breakpoint get bp {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= 1240) return Breakpoint.desktop;
    if (w >= 600) return Breakpoint.tablet;
    return Breakpoint.mobile;
  }
}
```

## 2. 布局策略

### 2.1 Shell（应用外壳）

```
mobile                tablet                  desktop
┌────────────┐       ┌──┬─────────────┐    ┌────┬───────────┬──────┐
│   AppBar   │       │  │   AppBar    │    │     AppBar           │
├────────────┤       │  ├─────────────┤    ├────┴───────────┴──────┤
│            │       │R │             │    │ Drawer │ Content │ Det │
│  Content   │       │ail│  Content   │    │        │         │ ail │
│            │       │  │             │    │        │         │     │
├────────────┤       │  │             │    │        │         │     │
│  TabBar    │       └──┴─────────────┘    └────────┴─────────┴─────┘
└────────────┘
```

- **mobile**: `Scaffold` + `NavigationBar`
- **tablet**: `Row(NavigationRail, VerticalDivider, Expanded(child))`
- **desktop**: `Row(NavigationDrawer, VerticalDivider, Expanded(content), VerticalDivider, DetailPanel)`，DetailPanel 由各页注入（默认隐藏）。

### 2.2 列表 ↔ 表格

- **mobile**：卡片列表，每条 1 行主信息 + 1 行副信息，右侧拖拽滑动出快捷操作。
- **tablet**：卡片网格 2 列；或当列表数 > 30 时切到密集 List。
- **desktop**：DataTable / DataTable2，支持列排序、列宽拖拽、行 hover、右键菜单。

### 2.3 表单

- **mobile**：单列，每个字段一行；CTA 固定在底部安全区上方。
- **tablet / desktop**：两列对齐表单（label 在上方），CTA 跟随表单尾部，Esc 取消。

### 2.4 模态

| 类型 | mobile | tablet | desktop |
|------|--------|--------|---------|
| 添加交易 | 全屏 ModalSheet | 中央 Dialog 720×自适应 | Dialog 720×自适应 |
| 筛选 | 底部 BottomSheet 高度 75% | BottomSheet | 右侧 Drawer |
| 资产详情 | 全屏 push 路由 | 全屏 push | 右侧 DetailPanel（同时保留主列表） |

## 3. 输入设备适配

### 3.1 触摸（mobile / tablet）
- 触发区 ≥ 44×44dp。
- 主操作放手指可达区（mobile 屏幕下三分之一）。
- 长按出菜单（300ms），右滑列表项出快捷操作（删除/编辑/问 AI）。
- 下拉刷新：所有列表与 Dashboard。

### 3.2 鼠标（tablet / desktop）
- Hover 状态：行 hover 用 `surfaceContainerHighest`，按钮 hover 提升 1 级表面色。
- 右键菜单：表格行 / 资产卡 / 图表区域 → "查看详情 / 添加交易 / 问 AI / 复制数据"。
- 鼠标滚轮：图表区域支持 ctrl+滚轮缩放时间轴；普通滚轮垂直滚动。

### 3.3 键盘（desktop 优先，tablet/mobile 软键盘默认行为）

| 快捷键 | 动作 |
|--------|------|
| `⌘/Ctrl + K` | 全局搜索 / 命令面板 |
| `g d` | 跳到 Dashboard |
| `g a` | 跳到 Assets |
| `g x` | 跳到 Analytics |
| `g f` | 跳到 FIRE |
| `g r` | 跳到 Rebalance |
| `g c` | 跳到 Chat |
| `g s` | 跳到 Settings |
| `n` | 新建（在当前列表上下文中：资产/交易/...） |
| `/` | 页内搜索/筛选 |
| `Esc` | 关闭 Dialog/Sheet/Detail |
| `?` | 显示快捷键帮助浮层 |
| `Tab` / `Shift+Tab` | 焦点环 |
| `Enter` | 激活选中行 |
| `j / k` | 列表上下移动焦点（vim 风） |
| `[` / `]` | 时间区间前后切换（图表） |

> 实现可用 `RawKeyboardListener` 或 `Shortcuts` + `Actions`。在移动端不暴露 `?` 帮助。

## 4. 字体与密度

- **基础字号**：`14sp`（mobile body），桌面端按 `MediaQuery.textScaleFactor` 跟随系统。
- **VisualDensity**：`adaptivePlatformDensity`（已在 `AppTheme`）；桌面端额外允许 `compact` 切换（高密度表格）。
- **行高**：1.45（body）/ 1.20（display & numeric tabular）。
- **数字字体**：所有金额、百分比使用 `tabular figures`（`fontFeatures: [FontFeature.tabularFigures()]`），保证位对齐。

## 5. 图像 / 字体优化（Web 桌面）

- **中文字体**：默认走系统字体（`PingFang SC` / `Microsoft YaHei` / `Noto Sans SC`）。如需统一品牌字体，**子集化**到中日韩常用 8500 字 + 数字符号，`woff2`，单文件 < 1 MB；分片加载（unicode-range）。
- **图标**：Material Icons + 自定义 SVG（独立 sprite）。禁止整个 `material_icons` font 全量引入。
- **首屏**：路由代码切分（`go_router` + `deferred as`），首屏只加载 `/` 所需。
- **PWA**：可缓存的 manifest + service worker；离线 fallback 到 `/` 但提示"无网络"（详见 11-motion）。

## 6. 安全区

- iOS：`SafeArea(top, bottom)`，FAB 距底栏 16dp。
- Android：`SystemUiOverlayStyle` 跟随主题；底栏取消透明导航栏的 inset。
- Web：`max-width` 不限制（任由内容铺满）；但卡片内容用 `ConstrainedBox(maxWidth: 1200)` 居中。

## 7. 实施备忘

- 拆 `_RootShell` 成 `MobileShell` / `TabletShell` / `DesktopShell`，由 `LayoutBuilder` 选择。
- 引入 `ResponsiveValue<T>` 工具或 `flutter_adaptive_scaffold`（评估）。
- `DetailPanel` 通过 `Provider<DetailPanelController>` 暴露 push/pop API，让任何子页都能从右侧打开详情。
