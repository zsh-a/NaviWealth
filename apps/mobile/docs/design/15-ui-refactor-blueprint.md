# 15 · UI 统一重构蓝图(Refactor Blueprint)

> 本文是 UI/主题重构的 **SSOT**:目标架构、API 形态、迁移分期、守护机制、验收标准。
> 依据 2026-07 全库 UI 审查(设计系统 / 壳层导航 / FinanceOS / 跨领域四份走查)撰写。
> 原则:**不推翻现有 token 纪律,只补齐"解析层 + 唯一入口 + 类型护栏"**;所有阶段可独立合入、可独立回滚。

> **实施进度(2026-07-26)**:P0 ✅(4 个 lint 护栏进 CI,`DESIGN.md` 已删)· P1 ✅(`AppThemeData`/`ColorRole`/`resolveAppTheme`/`context.appTheme` 落地,108 项对比度不变量测试,4 项既有色板债入豁免表)· P2 ✅(§3.6 四个 bug 修复;`SignedMoneyText`/Health 趋势接 `MarketColors`;badge/banner 换 `on*Container`;手拼百分比 19→0;SnackBar/Material Divider/页面级 spinner 清零;`KnowledgeEmptyState` 补 `action`;zh ARB 知识类型补译)。P3 部分 ✅(静默加载 10 处判定完毕——4 处换骨架、7 处标注为有意为空;裸错误态 7 处接 `AppEmptyState.error`/`userSafeErrorMessage`;Material spinner 清零并锁 0;sheet 桌面限宽 720)· P4 核心 ✅(`shellDesktop` 并入 1240;切换 chip 在 <1240 常驻、平板侧栏新增切域与 Ask-AI 入口;撤销横幅上移至全部布局;`Cmd/Ctrl-1..N` 域内化)· P5 部分 ✅(浅色 info 前景 cyanBrand700、色盲浅色 down 前景 cbOrangeDark,对比度豁免表清零)。P5 主体 ✅(73 处旧主题入口迁至 `context.appTheme`,`ColorRole` 补 `onFg`;剩余 8 处 = 6 处 `MarketColors.of` 偏好关键部件——与 `MarketColorsScope` 一并退役——加 2 处 `AccentColors.series` 图表常量,lint 基线锁 8)· P4 返回协议 ✅(非首 tab 根先回本域首 tab 再退出确认)· `/life` 补下拉刷新与 1200 限宽。MarketColorsScope 退役 ✅(最后 6 处 `MarketColors.of` 迁至 `context.appTheme.market`,scope/provider/`MarketColors.of` 删除,基线锁 2 = 仅 `AccentColors.series`)· tokens.json 导出管线 ✅(Dart → JSON 单向,406 token,`check-design-tokens-export.sh` 进 CI)· 未开通域深链提示 ✅(`?blocked=` + 说明横幅)· 死部件删除 ✅(`AppSidePanel`/`AppClosePageScaffold`/`DomainAiPromptBar` 部件,保留在用的 `DomainAiPromptAction` 值类)。旧表折叠 ✅(`SemanticColors.of` 上下文查找删除,与 `MarketColors` 同构——常量表仅作为 `resolveAppTheme` 输入存活)· raw `.when` 收编 ✅(标准形态迁 `whenOrLoading`/`kDefaultError`,详见提交记录)。**Scaffold 8→3 重新判定**:审查所列 8 种中,`AppTaskScaffold`/`ObjectDetailScaffold`/`AppFormPageScaffold` 实为基于 `AppPageScaffold` 的分层模板(组合而非竞争),予以保留;真正的竞争实现(`AppClosePageScaffold`、死件 `AppSidePanel`)已删除;`DomainTabScaffold` vs `ShellTabScaffold` 的归并留待专项。**预设主题第一批 ✅**:新增 `AppSurfaceStyle {standard, oled, highContrast}` 第三偏好轴(与明暗、市场色正交)——OLED 纯黑面(深色专属,浅色回退标准)与高对比风格(内容梯度 AAA 7:1、状态/市场前景 4.5:1,经色相保持的 HSL 增强);`ThemeInputs` 扩维后对比度不变量测试自动扩至 324 项;Forui 表面同步、SharedPreferences 持久化、设置页外观区新增选择行、tokens.json 新增 `color.oled` 组。第二批(AccentSeed 换色种子、命名组合包)待启动。剩余:排版比例尺统一(§4,两套 scale 合一——影响全局渲染,需带 golden 基线更新的专项)、`/life` 进壳已由"切换 chip 全宽可见 + 桌面 dock"覆盖(底栏属设计取舍,不强加)、`AccentColors.series` 2 处图表常量(可接受的稳定余量)。注:P1 聚合对象命名为 `AppThemeData`(避让既有 Material 工厂类 `AppTheme`)。

---

## 0. 诊断摘要:五个根因

现状机械 token 纪律极好(全库无硬编码色值/间距/圆角字面量),问题全部出在结构层:

| # | 根因 | 典型症状 |
|---|------|---------|
| R1 | **主题有五个读取入口,无统一解析** — `FTheme.of` / `SemanticColors.of` / `MarketColors.of` / `AccentColors.*(brightness)` / 两套字体预设 | 暗色双绿双红同屏;盈亏色不随用户偏好;`chart_palette.dart:43` 自判亮度出 bug |
| R2 | **前景/背景不成对,对比度靠调用方自觉** | badge/banner 用 `semantic.X` 配 `XContainer` 得 1.92~3.58:1;`on*Container` 定义了但 0 调用;`delta_text.dart:100` 覆盖调用方颜色 |
| R3 | **设计系统组件存在但被绕开,无护栏** | ~60 个节标题只有 4 个用 `SectionHeader`;度量瓦片 4 套;加载态 30+ 种;分隔线 5 种;金额/百分比 5 套格式化 |
| R4 | **领域各写各的 UI 方言,无跨域契约** | 页面骨架 / 卡片描边 / 空状态 / 刷新手势 / 新建入口 / Agent 面板四域四样 |
| R5 | **壳层响应式只做了手机和 ≥1280 两端** | 600–1280 无域切换入口、无撤销横幅、无 AI 入口;sheet 桌面无宽度约束;快捷键绑死 Finance |

---

## 1. 设计原则(北极星)

1. **单向分层,越界即 lint 报错**:`primitives → roles → component specs → 页面模板 → 领域契约`,每层只准引用紧邻下层。UI 代码永远接触不到 `ColorPalette`。
2. **一次解析,一个不可变对象**:`AppTheme = resolve(ThemeInputs)`,根部算一次整树下发。组件层出现 `brightness == dark` 判断即违规。
3. **配对即类型**:颜色以"保证过对比度的角色对"(`ColorRole`)为最小消费单元,错误配色在 API 上写不出来。
4. **扩展 = 加数据,不加代码**:新域强调色 / 新暗色方案 / 新色盲模式 / 新分类色,都只是给 resolver 换输入,组件零改动。
5. **契约优于约定**:跨域一致性由 `DomainPack` 层的类型契约保证,不靠 code review 记忆。

---

## 2. 目标架构总览

```text
┌─────────────────────────────────────────────────────────────┐
│ L4  领域 UI 契约  DomainPack.uiSpec(accentSeed, todaySurface,│
│                   emptyState, agentPanel, settingsSpec)      │
├─────────────────────────────────────────────────────────────┤
│ L3  页面模板     AppPageScaffold · BriefScaffold ·           │
│                  AppFormPageScaffold · AppAsyncView          │
├─────────────────────────────────────────────────────────────┤
│ L2  组件规格     theme.badge / theme.card / theme.divider /  │
│                  theme.metricTile / theme.press (spec 预算好)│
├─────────────────────────────────────────────────────────────┤
│ L1  语义角色     AppTheme { surfaces, content, accent,       │
│                  status, market, categorical, type,          │
│                  geometry, motion }   ← resolveAppTheme()    │
├─────────────────────────────────────────────────────────────┤
│ L0  原料         ColorPalette 色阶 / 尺寸值 / 字号值          │
│                  (@internal,由 tokens.json 单向生成)         │
└─────────────────────────────────────────────────────────────┘
```

读取入口全库唯一:`context.appTheme`(以及既有 `FTheme.of` 供 Forui 组件内部使用,其色值由 L1 反向写入,见 §3.5)。

---

## 3. 主题系统

### 3.1 L0 · Primitives

- `tokens/color_palette.dart` 保留纯色阶,标注 `@internal`;新增 lint(§10)禁止 `design_system/theme/` 之外 import。
- **业务分类色上移**:`KnowledgeTypeColors`、`ExpenseCategoryColors`(现为 34 个不适配暗色的固定 hex)、`features/health/ui/health_metric_colors.dart` 全部移出 L0,改由 resolver 按明暗生成(§3.3),UI 通过 `theme.categorical` 消费。
- **色阶修复**(数据级,无 API 影响):
  - `navy300 #8F9BB3`(Tailwind slate,蓝紫)重新推导回青灰 navy 色相族 — 它是暗色 `mutedForeground`,影响全部暗色次要文字;
  - `#002A38` 幽灵基色命名入阶(如 `navyShadowBase`)或统一改用 `navy950`;
  - 合并两个 cyan 家族在语义角色上的混用(light info 用 `cyanBrand500`、dark infoContainer 用 `cyan950` 的交叉);
  - 删除 `ExpenseCategoryColors.cart = #16A34A`(回流的已弃用绿),10 个与既有 token 重复的 hex 改别名;
  - `amber450` 非标阶名并入 400/500。

### 3.2 L1 · 角色与聚合对象

核心类型 —— **配对即类型**:

```dart
/// 一组构造时保证对比度的配色角色。组件整组消费,不拆散拿色。
@immutable
class ColorRole {
  final Color fg;          // 直接落在 surface 上的前景(图标/强调文字),对 card ≥ 4.5:1
  final Color container;   // 该角色的填充底
  final Color onContainer; // 容器上的文字/图标 —— 容器前景的唯一合法取色,对 container ≥ 4.5:1
}
```

聚合对象(全部不可变、值语义,便于 golden/单测):

```dart
@immutable
class AppTheme {
  final AppSurfaces surfaces;   // canvas/card/raised/hero/border/hairline/scrim
  final AppContent  content;    // strong/default/muted/faint 四档文字梯度
  final ColorRole   accent;     // 品牌交互色(取代 AccentColors 静态类)
  final AppStatus   status;     // success/warning/danger/info : ColorRole ×4
  final AppMarket   market;     // up/down/flat : ColorRole ×3 + forDelta()/roleForDelta()
  final Map<CategoricalKey, ColorRole> categorical; // 支出分类/知识类型/健康指标
  final AppTypeScale type;      // 唯一字体比例尺(§4)
  final AppGeometry geometry;   // pageRhythm/cardPadding/radius/stroke/iconTile 档位
  final AppMotion   motion;
  // L2 组件规格(§6 消费):
  final BadgeSpec badge; final CardSpec card; final DividerSpec divider;
  final MetricTileSpec metricTile; final PressSpec press;
}
```

关键合并:**`status.danger` 与 `market.down`(red-up 模式下)在 resolver 里引用同一 `ColorRole` 实例**。"暗色两种红/两种绿同屏"(`semantic_colors.dart:82` vs `market_colors.dart:236`)在构造上不可能再发生。`SemanticColors` 此后只表达"状态"(校验/同步/错误),方向色一律走 `market`。

### 3.3 解析管线(纯函数)

```dart
@immutable
class ThemeInputs {
  final Brightness brightness;
  final MarketColorMode marketMode;  // 红涨绿跌(默认)/绿涨红跌/色盲
  final AccentSeed accent;           // 预留:域强调色/品牌换色
  final AppDensity density;          // touch / desktop(显式化 Forui 的隐式分叉)
}

AppTheme resolveAppTheme(ThemeInputs inputs);  // 纯函数,无 BuildContext
```

- 根部由 Riverpod 组合 `themeModeProvider × marketColorModeProvider × densityProvider` 算一次,经单一 `AppThemeScope`(InheritedWidget)下发;`MarketColorsScope` 退役。
- 纯函数 ⇒ 对比度是**单元测试**:枚举全部 `ThemeInputs` 组合 × 全部 `ColorRole`,断言两条不变量(fg/surface、onContainer/container ≥ 4.5:1)。现有 1.92:1 的 info 徽章从"上线后才看见的缺陷"变成"跑不过 CI 的测试"。

### 3.4 读取入口

```dart
final t = context.appTheme;
Text(label, style: t.type.numericBody.withColor(t.market.roleForDelta(delta).fg));
```

- `SemanticColors.of` / `MarketColors.of` / `AccentColors` 标 `@Deprecated`,迁移期作为 facade 转发到 `AppTheme`(§11 Phase 1)。

### 3.5 与 Forui 的关系

保持现有方向不变:`buildAppForuiTheme` 继续存在,但其 `colors.copyWith(...)` 的取值改为**从 resolver 结果反向写入**(单一来源),同时补上 `app_forui_theme.dart:38` 只换字体族不管字号的缺口 —— `FTypography` 的字号对齐到 §4 的唯一比例尺。Material `ThemeData` 同理(修掉 `surfaceContainerLow=navyGlass` vs `SoftCard.raised=navyRaised` 的 4% 色差)。

### 3.6 随迁修复的既有 bug(实锤清单)

| Bug | 位置 | 修法 |
|---|---|---|
| `DeltaText` 覆盖调用方颜色 → `DeltaChip` 永远拿不到 onContainer | `widgets/delta_text.dart:88-100` | `copyWith(color:)` 仅在调用方未显式传色时应用 tone;`DeltaChip` 改传 `role.onContainer` |
| 图表亮度 OR 了 OS 亮度 | `charts/chart_palette.dart:43-46` | 删 `platformBrightness ||`,只认 `colors.brightness`(重构后:只认 `theme.surfaces`) |
| badge/banner 前景对比度 | `widgets/app_badge.dart:107-124`、`app_status_banner.dart:124-141` | 改消费 `theme.badge`(spec 内取 `role.onContainer`) |
| Health 趋势箭头写死 up=primary/down=红 | `features/health/ui/metric_grid_primitives.dart:119`、`metric_grid.dart:349`(逐字节重复) | 删两份私有实现,换 `DeltaChip` + 语义翻转参数(`higherIsBetter`) |

---

## 4. 排版系统:一套语义比例尺

现状:`TypographyTokens`(Material 系,128 处)与 Forui `FTypography`(~900 处、touch/desktop 隐式变号、`body.sm > body.xs` 命名陷阱)并行;794 处 `.copyWith` 散改;行高 7 种值各屏自造。

**目标**:

1. 唯一比例尺 `AppTypeScale`,语义命名、**每档带定行高**:
   `display · title · heading · body · label · caption · numericDisplay · numericTitle · numericBody · numericCaption`
2. touch/desktop 差异由 `ThemeInputs.density` 在 resolver 显式乘档(现 `captionStyle` 手机 14px/Web 12px 且无文档的问题,变成一处可读代码)。
3. Forui `FTypography` 反向对齐到这套值(§3.5);`TypographyTokens` 近重复对(`numericTitle/Strong` 等 4 对)合并。
4. 受控变体替代自由 `copyWith`:`.muted / .emphasized / .onRole(role)`;新增 lint 拦 `style.copyWith(fontSize:|fontWeight:|height:)`(白名单:design_system 内部)。
5. 图表内 7 处 `fontSize: 10` 收编为 `type.chartCaption`。

---

## 5. 数字与格式化:唯一渲染路径

理财 App 的第一可信度来源。规则收敛为一张职责表:

| 内容 | 唯一路径 | 禁止 |
|---|---|---|
| 金额 | `MoneyText` / `AnimatedMoneyText`(内部走 `AppFormatters.currency`) | 一切 `'${currency} ${amount}'` 拼接 |
| 带方向金额(盈亏) | `DeltaText` / `DeltaChip`(色取 `theme.market`) | `MoneyText(showSign: true)` 表达盈亏、`SignedMoneyText` 走 status 色 |
| 百分比 | `AppFormatters.percent / signedPercent`(locale 感知) | `(v*100).toStringAsFixed(n) + '%'` |
| 空值 | `l10n.commonNotAvailable` 统一(`'—'` 由 `MoneyText.placeholder` 内部输出) | 裸 `'—'` 字面量 |
| 符号风格 | 全 App 默认 `MoneySymbolStyle.symbol`;isoCode 仅在多币种歧义上下文用,并成为组件参数默认值,不由页面各自决定 | 页面级 override |

**删除清单**(私有格式化函数,共 8+ 处):`income_strategy_page.dart:558 _metricMoney`、`opportunities.dart:384 _moneyCompact`、`opportunity_detail_sheet.dart:374 _moneyLabel`、三份 `_pct`、`strategy_profile_sheet.dart:626 _percentText`、`options_trade_stats_page.dart _signedMoney`。

`SignedMoneyText` 与 `DeltaText` 合并为一个组件(参数区分是否携带容器),五个金额组件收敛为三个:`MoneyText` / `AnimatedMoneyText` / `DeltaText(+Chip)`。

---

## 6. 组件层收敛

### 6.1 页面骨架:8 → 3 + 1

| 保留 | 用途 | 收编对象 |
|---|---|---|
| `AppPageScaffold` | 通用列表/详情页 | `DomainTabScaffold`、`AppCanvasScaffold`、`AppTaskScaffold`、`AppClosePageScaffold`(后两者 0-4 调用) |
| `BriefScaffold` | 各域 Today/仪表盘面(折叠头 + 吸顶摘要 + 氛围底纹 + `onRefresh`) | Knowledge 三页的 `Stack+ListView` 自拼、`LifePage` 的无刷新变体 |
| `AppFormPageScaffold` | 表单页/表单 sheet 主体 | `app_form_scaffold_body.dart` |
| `ObjectDetailScaffold` | (保留,基于 AppPageScaffold 的薄封装) | — |

下拉刷新是 `AppPageScaffold`/`BriefScaffold` 的一等参数;删除 `KnowledgePullToRefresh`(110 行手写滚动数学)。

### 6.2 异步状态:一个契约

新增 `AppAsyncView<T>`(或扩展现有 `whenOrLoading/whenOrError`),法定三态:

- **loading** = 骨架屏(`page_skeletons.dart` 家族),spinner 全部退役(含 5 处 Material `CircularProgressIndicator`);
- **error** = `AppEmptyState.error` + `userSafeErrorMessage` + 重试回调 —— 修掉 `'$e'` 直出(`income_planner_page.dart:69`)、错误渲染成空态(`wheel_lifecycle_page.dart:39`)、静默吞错(`leaps_call_position_sheet.dart:268`);
- **empty** = `AppEmptyState`(带 `action` CTA)。

**删除清单**:10 处 `SizedBox.shrink()` 静默加载、7 处裸 `Text` 错误、`KnowledgeLoadingState/EmptyState/ErrorState`(补 `action` 后仅作转发别名过渡)、`ExecutionStateView`、5 个私有 `_EmptyState`、`_ErrorCard`(全红块)、options_income 的 `_LoadingState/_LoadingTile/_EmptyCard/_ApprovedEmpty/_StartState`。

Web 不支持提示统一为一个 `WebUnsupportedPage`(现存三种答案,其中 `wheel_lifecycle_page.dart:30` 返回空白路由)。

### 6.3 小部件规格(由 theme spec 驱动)

| 部件 | 规格决定 | 收编 |
|---|---|---|
| `AppBadge` | `theme.badge`:tone → role/padding/radius/字号 | 12 个自制 chip(`_StrategyChip`、`_FilterChip` 等) |
| `AppIconTile` | 尺寸/透明度改枚举档位(`sm=28 / md=36 / lg=44`,opacity 由 spec 定) | 5 种手拼图标方块(36/40/48px) |
| `AppMetricCluster` | `theme.metricTile` 定唯一瓦片宽度与值字号 | 3 个 `_Metric` 类(128/132/140px)与 `_StatsGrid`;>6 个指标必须分组(修 13 瓦片数字墙) |
| 分隔线 | 唯一 `AppDivider`,可见度提到 ≥ hairline 对比;`AppGradientDivider` 仅保留 hero 装饰用途 | Material `Divider`(6)、`FDivider` 直用(语义场景) |
| `SectionHeader` | 唯一节标题(标题+可选 trailing) | 5 种自造样式、两个 `_SectionLabel` |
| 按压反馈 | `theme.press.scale` 单值 | 0.985/0.97/0.96/0.99 四种系数 |

### 6.4 表单契约

所有表单 sheet/页遵守五件套:`Form` + 字段级 `validator` + `autovalidateMode` + `FormDirtyController`(脏表单守卫)+ `submitFormAndLeave`(成功/失败 toast)。共享字段组件(`DateField/CurrencyPicker/AccountPicker/SymbolField/_DecimalField→AppDecimalField` 带前后缀)入 design_system。首个整改对象:`income_strategy_plan_sheet.dart`(现无 Form、`:138` `Decimal.parse` 先于守卫执行会崩、无成功反馈)。

### 6.5 反馈与浮层

- 通知唯一路径 `AppMessenger`;`ScaffoldMessenger/SnackBar` 3 处清零并 lint 封禁(`life_event_scenarios_page.dart:344` 同一 try/catch 双机制是反面教材)。
- **Sheet 桌面化**:`showAppSheet/showAppFormSheet` 在 `width ≥ Breakpoints.mobile` 时自动转中央对话框(`maxWidth: 560/720`),对齐 `01-responsive-layout.md §2.4`。~180 个调用点零改动(在入口函数内分流)。

---

## 7. 壳层与响应式

### 7.1 断点统一

| Token | 现值 | 目标 | 说明 |
|---|---|---|---|
| `mobile` | 600 | 600 | 不变 |
| `desktop` | 1240 | 1240 | 内容层 |
| `shellDesktop` | 1280 | **删除,并入 1240** | 消除 1240–1279 壳/内容错位带 |
| `contentTwoColumn/ThreeColumn` | 1024 / 720(倒置) | 重命名 `contentWide=1024 / contentMedium=720` | 命名与数值一致 |
| 散落硬编码 560/520/480 | 4 处 | 收编为 `Breakpoints.dialogMax` 等 | `command_palette_dialog.dart:210`、`health_trend_page.dart:143`、`app_sheet.dart:379`、`forui_dialogs.dart:19` |

### 7.2 域切换死区(600–1280)

- `DomainSwitcherChip` 删掉 `width >= Breakpoints.mobile` 自隐藏(`shell_chrome.dart:81`),在 [600, 1240) 常驻页头;
- `_TabletLayout` 的 `FSidebar` 顶部加域切换入口;
- ≥1240 维持左 dock。三层入口覆盖全部宽度,无死区。

### 7.3 全局能力提升到壳层

`PersistentUndoBanner` 与 Ask-AI 入口从 `_MobileLayout` 上移到 `DomainTabsShell.build`,三种布局(mobile/tablet/desktop)统一获得;`/life` 与 `/agent/:id` 改为壳内分支(或显式包一层导航 chrome),`LifePage` 补 `onRefresh` + `maxContentWidth`。

### 7.4 快捷键域内化

`primaryTabPathsProvider` 由"全域拍平"改为"当前域的 tabPaths":`Cmd+1..n` = 当前域各 tab,`Cmd+Shift+1..4`(或 `g` 前缀)= 切域。删除 `kPrimaryTabCount = 4` 常量。

### 7.5 返回栈协议

Android 返回四步协议落实(现文档写了、代码只做到第 1 步):子页出栈 → 回本域首 tab → 回上一个域(域切换记一层历史)→ 退出确认。

### 7.6 响应式内容适配推广到全域

`AdaptiveContentFrame` / `MasterDetailLayout` / `ResponsiveTwoColumn` 目前是 Finance 独占;Health/Knowledge/Execution/Life 的 tab 根页面全部套 `AdaptiveContentFrame`(默认 `AdaptiveMaxWidth.dashboard`),消除 1920px 下 1800px 宽的卡片。这是 L4 契约的一部分(§8)。

### 7.7 其余壳层项

- 深链进未开通域:redirect 到 `/settings/domains` 时附 toast 说明(现为静默瞬移);
- 触感反馈补齐 `_switchToDomain`/`_TabletRailItem`/`DesktopSidebar._SidebarItem`;
- deferred route 策略统一:Knowledge/Execution 对齐 Finance/Health 的 `DeferredRoute` 拆包;
- 双 l10n 解析路径合一(`domain_composition.dart:172` 的 `lookupAppLocalizations` fallback);
- 删除死配置 `kFinancePack.additionalPathPrefixes`。

---

## 8. 跨领域 UI 契约(L4)

在 `DomainPack` 增加类型化 UI 规范,一致性由编译器与 lint 保证:

```dart
class DomainUiSpec {
  final AccentSeed accentSeed;          // 域强调色(dock/切换器/图表主系列)
  final WidgetBuilder todaySurface;     // 必须返回 BriefScaffold
  final DomainSettingsSpec settings;    // 统一为"Settings 总览内嵌 section"一种深度
  final AgentPanelSpec agentPanel;      // 统一 loading/empty/error 与 meta 格式
}
```

**法定跨域规范**:

1. **Today 面**:一律 `BriefScaffold`(折叠头 + 吸顶摘要 + `onRefresh`);Knowledge 三页迁入。
2. **新建入口**:一律页头 action(`ShellHeaderActionSpec`);删除 Knowledge 独有 FAB(`AppFloatingActionSurface` 全 App 退役)与 `KnowledgeFloatingActionMotion`。
3. **卡片描边**:全 App 一个策略 —— `raised = 无边框 + 阴影`、`flat = hairline 边`(spec 定,`knowledge_section_widgets.dart:78` 的写死删除);`SoftCard(level:)` 一律用命名构造器。
4. **空状态**:一律 `AppEmptyState` 且必须给 `action`(空态不许是死路);opt-in 域未开通时展示统一的 `DomainActivationCard`(从 `FinanceActivationCard` 泛化,Health 的"埋在 hero 里的一行灰字"与 Knowledge/Execution 的"完全无感知"对齐到同一体验)。
5. **Agent 面板**:唯一 `AgentResultsSection`(含 swipe 栈);loading=骨架、empty=带 CTA 状态卡、meta 一律 `AppFormatters.relativeTime`;删除三份逐字节重复的 `_*AgentPanelFrame` 与 Health 独有的单卡变体;`DomainAiPromptBar` 二选一 —— 四域全部启用(推荐,作为 `BriefScaffold` 可选槽位)或删除。
6. **知识域 proposal 面**:`_ai_suggestions_card.dart`(537 行平行体系)并入共享 `propose_card.dart` 管线,Execution/Health 的 propose 工具补上同一面。
7. **分类色**:全部来自 `theme.categorical`;补齐 Knowledge 缺失的 decision/note 两色;解决 `violet500` 在 knowledge.concept 与 health.body 的语义冲撞(分配不同 hue)。

---

## 9. 本地化与文案规范

1. **wire 枚举永不直接渲染**:`knowledge_library_tiles.dart` 等 13 处 `status.wire` 全部改走既有 `decisionStatusLabel` 类 helper(Execution 的 `executionStatusLabel` 是正确范式);加 lint 拦 `\.wire\b` 出现在 `ui/` 目录。
2. 中文 ARB 补齐 7 个 `knowledgeCaptureKind*`;域设置页标题 `'HealthOS'` 等 6 处硬编码入 ARB。
3. `MM-dd` 回退逻辑(4 份复制)收编进 `AppFormatters.shortDate`;`opportunity_detail_sheet.dart:299` 全角冒号改 l10n 模板。
4. Health 命令面板中文别名对齐 Finance 的 ARB 方案(`commandKeyword*Cn`)。
5. RTL:5 处 `EdgeInsets.only(left:/right:)` 改 `EdgeInsetsDirectional`;`'• $line'` 文本弹头改真列表布局。

---

## 10. 守护机制(让回归不可能)

**新增 lint 脚本**(与现有 `tool/lint-*.sh` 同构,进 CI):

| 脚本 | 拦截 |
|---|---|
| `lint-theme-layering.sh` | `theme/` 外 import `color_palette.dart`;组件层 `brightness ==` 判断;`SemanticColors.of/MarketColors.of` 新增调用(迁移期白名单递减) |
| `lint-material-chrome.sh` | `ScaffoldMessenger`、`SnackBar(`、`CircularProgressIndicator`、Material `Divider(`、`showModalBottomSheet` |
| `lint-format-path.sh` | `'$'{.*currency}` 拼接、`toStringAsFixed.*%`、UI 目录里的 `.wire` |
| `lint-typography.sh` | `copyWith(fontSize:\|fontWeight:\|height:)`(design_system 外) |

**测试**:

- `theme_contrast_test.dart`:纯函数枚举 `ThemeInputs` × `ColorRole`,断言 §3.3 两条不变量;
- 组件 golden:`AppBadge/SoftCard/AppEmptyState/DeltaChip/SectionHeader` × 4 组输入(light/dark × redUp/colorblind);
- 既有 widget test 约定不变(`makeTestDatabase` 等)。

**SSOT 治理**:`tokens.json` 定为 **Dart → JSON 导出**(Dart 是权威,脚本导出供设计工具),删除手写漂移;删除 `apps/mobile/DESIGN.md`(前代 M3 规范);`AppControlWidths` 20 个单调用 token 就地内联删除,`AppOpacity` 0.02–0.15 九档收敛为 `whisper/faint/subtle` 三档。

---

## 11. 迁移计划(六期,每期独立可合入)

| 期 | 内容 | 主要产出 | 验收 |
|---|---|---|---|
| **P0 护栏** | 四个 lint 脚本(先 warn 后 error)+ 对比度测试骨架 + 删 `DESIGN.md` | `tool/lint-*.sh` ×4 | CI 绿;基线违规数入 allowlist |
| **P1 主题内核** | `ColorRole/AppTheme/ThemeInputs/resolveAppTheme` + `AppThemeScope` + `context.appTheme`;先作为既有对象的 facade,不动任何视觉 | `design_system/theme/app_theme.dart` 等 | 对比度测试通过(容许 P2 前的已知豁免表);全部现有 widget test 不变绿 |
| **P2 热点迁移(修 bug 即迁移)** | §3.6 四个实锤 bug;`SignedMoneyText`/cashflow 图表/activity feed 方向色接 `theme.market`;badge/banner 接 spec;§5 格式化唯一路径落地(删 8 个私有 helper);`income_strategy_plan_sheet` 表单五件套 | 盈亏色全 App 随偏好;对比度豁免表清零 | golden ×4 组输入通过;`lint-format-path` 转 error |
| **P3 组件收敛** | §6:AppAsyncView 迁 96 处 raw `.when`(先 10 处静默加载、7 处裸 Text);骨架矩阵 8→3;分隔线/度量瓦片/badge/图标瓦片收编;sheet 桌面化 | 删除 ~30 个私有状态/瓦片/chip 类 | `lint-material-chrome` 转 error;删除类清单清零 |
| **P4 壳层与跨域契约** | §7 断点统一、死区修复、undo/AI 上移、快捷键域内化、`/life` 进壳;§8 `DomainUiSpec` 落地,Knowledge 迁 `BriefScaffold`、FAB 退役、Agent 面板统一、激活卡泛化 | 600–1280 全功能;四域同语言 | 三档视口手动走查清单(12-usability-self-check 增补);web_smoke 通过 |
| **P5 清理** | 旧入口删除(`SemanticColors.of` 等)、`ColorPalette` 私有化、tokens.json 导出管线、色阶修复(§3.1)、排版比例尺切换(§4)、本地化清单(§9) | 五入口 → 一入口 | `lint-theme-layering` 转 error;`rg SemanticColors.of` = 0 |

依赖关系:P1 → P2 → P5;P3、P4 与 P2 可并行。每期一个 PR 系列,单 PR 控制在一个收编主题内。

---

## 12. 文件级变更地图(关键项)

**新增**

```text
design_system/theme/app_theme.dart          AppTheme / ColorRole / 子聚合
design_system/theme/theme_resolver.dart     ThemeInputs / resolveAppTheme
design_system/theme/app_theme_scope.dart    AppThemeScope / context.appTheme
design_system/widgets/app_async_view.dart   三态契约
design_system/widgets/web_unsupported_page.dart
core/lifeos/domain_ui_spec.dart             L4 契约
tool/lint-theme-layering.sh / lint-material-chrome.sh / lint-format-path.sh / lint-typography.sh
test/design_system/theme_contrast_test.dart + goldens/
tool/export_design_tokens.dart              Dart → tokens.json
```

**退役/删除(P3–P5)**

```text
apps/mobile/DESIGN.md
theme/semantic_colors.dart(并入 resolver)· theme/accent_colors.dart · MarketColorsScope
knowledge_state_widgets.dart 三态类 · execution_card_widgets.dart#ExecutionStateView
knowledge_motion_widgets.dart#KnowledgePullToRefresh · app_floating_action_surface.dart
3× _*AgentPanelFrame · 3× _Metric · 12× 自制 chip · 5× _EmptyState · 8× 私有格式化函数
AppControlWidths 20 个单调用 token · AppRadius.xxl/none · AppToast 死出口
domain_ai_prompt_bar.dart(若表决为删)· kFinancePack.additionalPathPrefixes
```

---

## 13. 验收清单(Definition of Done)

- [ ] 全库颜色读取入口唯一(`context.appTheme`);`rg "SemanticColors.of|MarketColors.of|AccentColors\."` = 0
- [ ] 对比度不变量测试覆盖全部 `ThemeInputs × ColorRole`,零豁免
- [ ] 切换涨跌色偏好/色盲模式,全 App 每一处方向色同步变化(含 Health 趋势、cashflow 图表)
- [ ] 同一金额/百分比在任意两屏渲染格式一致;`rg "toStringAsFixed.*%"` 在 UI 层 = 0
- [ ] 四域 Today 面同为 `BriefScaffold`;空态 100% 带 CTA;Agent 面板三态与 meta 格式一致
- [ ] 400 → 1920px 连续拉宽:域切换/撤销/AI 入口全程可达,内容限宽,sheet ≥600px 转对话框
- [ ] 键盘 `Cmd+1..n` 作用于当前域;Android 返回走四步协议
- [ ] zh/en ARB 无缺口;UI 层 `\.wire` = 0
- [ ] 四个 lint 全部 error 级进 CI;golden 基线入库
