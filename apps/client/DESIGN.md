---
name: "NaviWealth Native FinanceOS — 温润纸感"
description: "暖纸、墨绿与精确数字，建立在 nsh 0.5.0 官方组件上的原生财务工作空间。"
colors:
  light-background: "#FAF8F4"
  light-foreground: "#242D29"
  light-card: "#FFFDF9"
  light-card-foreground: "#242D29"
  light-popover: "#FFFDF9"
  light-popover-foreground: "#242D29"
  light-primary: "#315B49"
  light-primary-foreground: "#FFFFFF"
  light-secondary: "#F0EEE7"
  light-secondary-foreground: "#242D29"
  light-muted: "#F0EEE7"
  light-muted-foreground: "#626B63"
  light-accent: "#E6EDE5"
  light-accent-foreground: "#242D29"
  light-destructive: "#995F50"
  light-border: "#E5E4DB"
  light-input: "#E5E4DB"
  light-ring: "#315B49"
  light-chart-1: "#315B49"
  light-chart-2: "#6F856E"
  light-chart-3: "#626B63"
  light-chart-4: "#805F33"
  light-chart-5: "#995F50"
  dark-background: "#181E1A"
  dark-foreground: "#F0F0E8"
  dark-card: "#202923"
  dark-card-foreground: "#F0F0E8"
  dark-popover: "#202923"
  dark-popover-foreground: "#F0F0E8"
  dark-primary: "#B5CCB6"
  dark-primary-foreground: "#1C3526"
  dark-secondary: "#29332C"
  dark-secondary-foreground: "#F0F0E8"
  dark-muted: "#29332C"
  dark-muted-foreground: "#ADB6AA"
  dark-accent: "#304535"
  dark-accent-foreground: "#F0F0E8"
  dark-destructive: "#D9AA96"
  dark-border: "#384039"
  dark-input: "#384039"
  dark-ring: "#B5CCB6"
  dark-chart-1: "#B5CCB6"
  dark-chart-2: "#718F79"
  dark-chart-3: "#ADB6AA"
  dark-chart-4: "#D5B889"
  dark-chart-5: "#D9AA96"
typography:
  type-page: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "24px", fontWeight: 600}
  type-section: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "16px", fontWeight: 600}
  type-body: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "16px"}
  type-caption: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "12px", lineHeight: 1.45}
  type-action: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "14px", fontWeight: 500}
  type-surplus: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "36px", fontWeight: 400, lineHeight: 1.15, letterSpacing: "-1.5px"}
  type-net-worth: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "36px", fontWeight: 400, lineHeight: 1.15, letterSpacing: "-1.5px"}
  type-expense: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "36px", lineHeight: 1.15, letterSpacing: "-1.5px"}
  type-income: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "20px"}
  type-mini: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "24px", fontWeight: 400, lineHeight: 1.15}
  type-allocation: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "18px", fontWeight: 400, lineHeight: 1.15}
  type-balance: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "24px"}
  type-record: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "30px"}
  type-amount-input: {fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif", fontSize: "48px", fontWeight: 400, letterSpacing: "-1.5px"}
rounded:
  theme-radius: "10px"
  utility-md: "6px"
  utility-lg: "8px"
  card-business: "18px"
  field-business: "9px"
  receipt-business: "7px"
  sheet-business: "22px"
  pill: "999px"
spacing:
  page: "16px"
  page-narrow: "16px"
  row: "12px"
  control: "12px"
  group: "24px"
  section: "24px"
  icon: "12px"
  choice-gap: "8px"
components:
  workspace-header: {backgroundColor: "{colors.light-background}", typography: "{typography.type-page}", height: "56px"}
  button-primary: {backgroundColor: "{colors.light-primary}", textColor: "{colors.light-primary-foreground}", typography: "{typography.type-action}", rounded: "{rounded.theme-radius}", padding: "0px 12px", height: "44px"}
  button-primary-dark: {backgroundColor: "{colors.dark-primary}", textColor: "{colors.dark-primary-foreground}", typography: "{typography.type-action}", rounded: "{rounded.theme-radius}", padding: "0px 12px", height: "44px"}
  button-secondary: {backgroundColor: "{colors.light-secondary}", textColor: "{colors.light-secondary-foreground}", typography: "{typography.type-action}", rounded: "{rounded.theme-radius}", padding: "0px 12px", height: "44px"}
  button-text: {textColor: "{colors.light-primary}", typography: "{typography.type-action}", rounded: "{rounded.theme-radius}", padding: "0px 12px", height: "44px"}
  field: {backgroundColor: "{colors.light-background}", textColor: "{colors.light-foreground}", typography: "{typography.type-body}", rounded: "{rounded.field-business}", padding: "0px 12px", height: "44px"}
  choice-selected: {backgroundColor: "{colors.light-accent}", textColor: "{colors.light-foreground}", typography: "{typography.type-caption}", rounded: "{rounded.theme-radius}", padding: "8px 4px", height: "56px"}
  chip: {backgroundColor: "{colors.light-muted}", textColor: "{colors.light-muted-foreground}", typography: "{typography.type-action}", rounded: "{rounded.pill}", padding: "6px 12px"}
  flat-row: {textColor: "{colors.light-foreground}", typography: "{typography.type-body}", padding: "12px 0px", height: "56px"}
  navigation: {textColor: "{colors.light-muted-foreground}", typography: "{typography.type-caption}", height: "56px"}
  record-tab: {backgroundColor: "{colors.light-card}", typography: "{typography.type-action}", rounded: "{rounded.utility-md}", height: "44px"}
  select-trigger: {textColor: "{colors.light-foreground}", typography: "{typography.type-body}", padding: "8px 0px", height: "44px"}
  mini-card: {backgroundColor: "{colors.light-card}", textColor: "{colors.light-foreground}", rounded: "{rounded.card-business}", padding: "12px"}
  allocation-pie: {size: "96px"}
  amount: {textColor: "{colors.light-foreground}", typography: "{typography.type-surplus}"}
---

# Design System: NaviWealth Native FinanceOS — 温润纸感

## Overview

**Creative North Star: "温润纸感"**

暖白纸面与墨绿操作色承托开放的大金额、短标签和紧凑流水。数字先于装饰，留白负责分组；表面只在选择、工具和有限的数据模块中出现。深色沿用同一语法，以森林色纸面建立层次。

本规范仅适用于 `apps/client`。用户批准此次 SYSTEM CHANGE：升级 nsh 0.5.0，优先使用官方组件及图形能力，保留暖白、墨绿、Manrope、四根导航与财务语义。以完成的 Rust 源码和原生运行结果为准；旧 A 方向 HTML 只保留为历史探索，不再是外观忠实度目标。品牌样式 wrappers 与业务组合仍存在；Flutter 的设计系统保持独立。

**Key Characteristics:**

- 暖纸与墨绿，浅深两套语义色，官方控件状态与图形交互。
- Manrope 数字、平台中文回退、完整金额与清晰币种层级。
- 开放主事实、平面流水、有限边界；布局跟随文字缩放和内容增长。

实现权威为 [theme.json](theme.json)、[共享 UI](src/ui.rs)、[控件](src/ui/controls.rs)、[图形](src/ui/plots.rs) 与 [壳层](src/shell.rs)。前置 tokens 是当前实现的提取值；业务角色通过 [tokens.rs](src/ui/tokens.rs) fallback 映射官方常用尺度，并非 `theme.json` 中的自定义尺寸覆盖。

## Colors

### Primary

墨绿用于主动作、焦点、选态和主要数据线。深色模式使用浅鼠尾草绿并配对深色按钮文字。暖棕 `destructive` 表达支出、负余额和危险动作；符号与文案同时表达意义，不能单靠颜色。

### Neutral

`background` 是暖纸画布，`card` / `popover` 是较清晰的纸面，`secondary` / `muted` 承托控件，`accent` 是选态的安静绿洗。正文与辅助说明分别使用 `foreground` 和 `muted-foreground`；边界、输入边界与焦点分别对应官方语义角色。

`chart-1` 对应主数据，`chart-2` 区分现金与普通日柱，`chart-3` 对应中性数据，`chart-4` 供预算警示，`chart-5` 对应暖棕数据。业务 `wash()`、`gain()`、`warning()`、`data_cash()` 分别复用 `accent`、`primary`、`chart-4`、`chart-2`；不新增同义品牌色 token。

前置颜色逐项来自当前主题的浅深模式。旧版 `hero`、`up/down`、`contrast-*`、`data-cash-surface` 不再是客户端主题覆盖。组件示例默认展示浅色，运行时使用当前模式的配对颜色。

## Typography

**Display / Body Font:** Manrope；原生资源内部族名为 `Manrope ExtraLight`，中文依次回退 `Noto Sans CJK SC`、`PingFang SC` 和系统 sans-serif。`ExtraLight` 是族名，不代表整套 UI 使用极细字重。

**Character:** 圆润开放的数字保持温度，tabular 数字保持列对齐。根标题与组标题半粗，流水标题及金额中等字重，开放主金额常规字重。前置角色大小是拟合前的逻辑尺寸；`amount_live` 按可用宽度和文字缩放缩小极长金额，完整数字仍处于一个可访问段落，币种为同基线小字。

`type-surplus`、`type-net-worth`、`type-expense` 使用官方常用的大数字尺度；`type-mini` 用于今日小卡，`type-allocation` 用于投资/现金确值，`type-balance` 与 `type-record` 用于余额和详情，`type-amount-input` 用于录入。正文角色与说明角色保持独立。显式金额行高与辅助行高见前置 tokens；其它行高保留其实际调用与原生排版。

**The Exact Fact Rule.** 金额标签、编辑草稿与保存值保持 Decimal 精度；浮点只服务图形几何，不回写财务事实。

`format_money` 保留千分组、紧邻数字的 ASCII 正负号及更细的非零位。货币小数位是最低显示位数；分组不四舍五入。编辑继续使用官方文本 Input，避免 NumberInput 的 `f64` 公开值丢失超大整数或细小金额；未聚焦时格式化回显，聚焦时保留原始草稿，错误分组不被静默修正。

流水可见币种仅在既不等于账户币种、也不等于基础币种时显示；未知账户不隐式当作本币。可访问标签始终保留原始币种。持仓损益保留独立副行，不给单笔流水或没有历史报价的持仓制造 sparkline。

字体随包本地提供：[WOFF2](assets/fonts/manrope-latin-variable.woff2)（24,836 B）与 [SIL OFL 1.1](assets/fonts/Manrope-OFL.txt)（4,383 B），来自 Fontsource variable Manrope 5.3.0。SHA-256 为 `a30ddcd349703aff7464c34bef3fffdff405ee50c113440d7c8693c02d210972`。资源 URI 为 `asset:/@naviwealth-client/fonts/manrope-latin-variable.woff2`；没有外部字体服务。GTK 与资源字节已核对，其它平台只具共享注册/配置证据。

## Layout

采用官方常用的 4/8 逻辑单位节奏。页边、组间与行内角色见前置 `spacing`；宽度不超过 370 的窄页分支仍存在，当前与普通页边数值相同。尺寸是 nsh 逻辑长度，不是物理像素承诺。

前置组件高度表达最小高度，内容可以增长；`allocation-pie` 的 `size` 为实际图形尺寸。壳层标题区、底部四根标签与常规流水分别使用其前置高度，安全区另计。共享 Button、普通输入、Select trigger / option / search、Menu item 与记录类型 Tab 保持至少 44 高；图标动作是 48 × 48，更多菜单触发器为 44 × 44，领域 Switch 的交互根至少 44 × 44，每日支出交互 Plot 至少 44 高。chip、Radio 等由官方组件及其内容布局确定实际尺寸，不能把所有控件误记成同一固定高度。

四根入口为今日、流水、财富、规划，保留既有路径与返回行为。标题为普通文字；工作空间入口保留在「更多 → 切换工作空间」（`domain-switcher`，`/domains`）。今日与流水共享「记一笔」。

分类网格间距使用前置 `choice-gap`，依据可用宽度、文字缩放和最长完整名称自适应一至四列。默认显示 12 类，「全部分类」可展开全部内置及自定义类别；选中隐藏类别自动展开。账户名、币种与元数据明确分开；选择项的 `label`、`trailing`、`currency` 是显式数据，不从「 · 」拆解含义。

轻量记录保留原生编辑容器，滚动内容与保存栏分开并预留安全区，尾部字段可达。复杂工具保留现有页面流程。今日开放主数字和两个有限边界的小卡、流水日期组、财富净资产/构成/趋势/持仓、规划预算/目标沿用当前业务构成。

## Elevation & Depth

实色纸面、留白与细边界负责主体阅读；小阴影现在有明确用途：共享主/次按钮、类型指示器、Switch thumb 和图形 tooltip 使用官方小阴影；普通 Toast 使用中阴影；Select / Menu 浮层使用大阴影。它们来自 nsh 的 utility 默认值，不是新的品牌阴影覆盖；精确值见 [sidecar](.impeccable/design.json)。

模态使用半透明黑色遮罩（opacity 0.28），内容保持不透明。普通流水不重复描边，今日小卡有单层细边界。

**The Flat Reading Rule.** 用对齐与留白组织流水；卡片、浮层和阴影只服务明确的分组或交互层级。

## Shapes

主要按钮、分类 Radio、选择按钮和部分行内目标使用官方主题默认圆角（前置 `theme-radius`，来自 nsh 的 `0.625rem`）。Select / Menu 浮层与记录类型底轨使用官方较小 utility 圆角，条目与跟随指示器再小一级。

业务外壳仍有明确 fallback：卡片、字段、回执行与记录 sheet 的半径见前置 `*-business`。这些是现有 Rust 布局 helper 的值，不是官方默认值，也未写入主题尺寸覆盖。共享 chip helper 为胶囊；流水快捷筛选使用主题默认圆角的 choice_button。线性图标保持 24-unit 画布、1.5 描边，常规显示 20，分类显示 16，选中 Check 显示 12。SVG 用于语义图标，趋势、日柱与构成圆环由官方 Plot 生成。

## Components

### Official Components First

优先在官方行为层上组织颜色、尺寸与财务内容；已有共享 wrapper 是复用入口。

| 需要 | 当前实现 |
| --- | --- |
| 动作、流水行、图标动作 | Button，经 `press_target` |
| 筛选与选择按钮 | Toggle / ToggleGroup |
| 根导航、记录类型分段 | Tabs / Tab，记录分段使用跟随指示器 |
| 账户和其它选项 | Select，超过 8 项启用搜索 |
| 分类单选 | RadioGroup / Radio |
| 归档显示、领域开关 | Switch |
| 预算、目标进度 | Progress |
| 更多菜单、流水工具 | Menu / MenuItem |
| 普通操作回执 | Toast / ToastStack / ToastManager |
| 趋势、日支出、分类摘要、资产构成 | Plot Area / Line / Grid / Dot / Bar / Pie |

`NativeControl` 只转发官方组件的根属性、可访问属性和 test ID；Button / Toggle 的禁用状态显式交给官方 `disabled` prop。它不重新实现按压、选择、键盘或图形几何。不要绕过官方事件和状态来恢复旧的自绘控件。

迁移清单统计独立行为/图形实现点，不统计运行时 widget 数量：迁移范围 14 → 0，包括两处独立 Menu 和流水分类摘要的横向堆叠 Bar。品牌 wrappers、分类网格和图标映射、精确金额、草稿保护、撤销与壳层布局仍是客户端业务组合。

### Buttons, Focus and Motion

主/次按钮配对主题前景与表面，并有细边界和小阴影；文字动作保持安静。共享 `press_target` 使用 hover opacity 0.9、active 0.88、disabled 0.4 和 2 单位可见焦点轮廓；按下弹簧缩放到 0.97，松开回到 1。

选择只在选态改变时从 0.985 回弹到 1，不在挂载时播放。共享弹簧 stiffness 420 / damping 30 / mass 0.6；编辑器入场位移 8，列表布局采用 180ms EaseOut。Switch thumb 过渡 180ms，减少动态效果时为 0；按压、选态、编辑入场及布局也遵循 `reduce_motion`。完整运动参数在 sidecar。

输入显式配对正文、占位、光标、选区、边界和焦点。Select / Menu 的焦点、选态、键盘与弹出生命周期由官方组件承担；搜索、选项和菜单项目保留足够触控空间。

### Choices and Capture

记录类型使用官方 Tabs 的纸面跟随指示器；分类使用官方 Radio 语义、安静绿洗与可见 Check，共享 chip 采用胶囊样式；流水快捷筛选采用默认圆角 choice_button，二者都使用官方 Toggle。

**The Whole Label Rule.** 分类列数随完整名称、可用宽度和文字缩放变化，不在词中折行来维持列数。

金额、对方、备注的 Enter 与保存按钮走同一提交路径。退出继续走脏草稿保护：「继续填写」为主动作，「放弃修改」为危险文字动作。视觉迁移不能绕过这些保护。

### Rows, Navigation and Feedback

共享流水行保留分类图标、标题、账户、右对齐完整金额、币种规则和持仓副行。非关键标题可截断，完整可访问标签保留。根 Tab 保留图标、短选择线与标签；旧 test ID 与交互路径保持可用。

普通回执由一个官方 ToastStack 托管：普通 notice 8 秒，进入 200ms、退出 160ms，可关闭；减少动态效果时视觉过渡为 0。跨页 60 秒业务撤销是独立 offer，包含剩余秒数与失败重试，存在时遮蔽普通 notice；新 offer 替换旧 offer，重启或到期结束。不要把普通 Toast 的时限当成撤销时限。

后台刷新保留已挂载内容，失败保留最后数据并给重试，表单入口快照在编辑期间冻结。月度收支、预算与分类构成独立于流水搜索/筛选/分页；切月清空旧事实，构成失败不显示旧月比例。

### Data Graphics and Evidence

趋势以官方 Area 渐隐填充、Line、三条 Grid 和最后/hover Dot 构成，保留十字线与精确日期/金额 tooltip。金额轴、高低范围、起末确值来自 Decimal；先在 Decimal 范围内归一化后才转换显示坐标。缺估值拆成独立连续 mark 图层，不能依赖 NaN 被跳过来保持断层。至少三个完整时点才画趋势，不足时解释条件；近 30 天不足三个完整点时使用已有完整历史，仍不补造缺失点。

每日支出使用官方 Bar，包含零支出日、按币种分别计算，转账与期初不计支出；峰值并列取最早日期，无正支出时显示空态。tooltip 显示原始确值。资产构成使用官方 Pie 的圆环，投资/现金确值与负债独立排列；部分缺价时保留「已知」金额与提示并隐藏完整占比圆环。

预算 Progress 的宽度钳制到 0—1，百分比和「超出」金额保留实际超额值。流水月度分类摘要使用官方横向堆叠 Bar：比例线性轴与 Band 轴，按同一 stack 生成各类段；该摘要非交互、高 7，前三类及「其他」图例由 [composition.rs](src/screens/ledger/composition.rs) 的真实 Decimal 汇总生成。客户端保留汇总与文字图例，不手算段宽。

Plot 仅使用短入场/hover 过渡，数据更新动画明确为 `None`；金额标签不做插值。减少动态效果时不启用 Plot motion。没有单笔流水时序，也没有逐持仓历史报价时，不引入装饰性 sparkline 或额外查询。

本轮证据为 [comparison.html](../../.impeccable/review/2026-11-12-nsh050-native/comparison.html)、[迁移清单](../../.impeccable/review/2026-11-12-nsh050-native/component-inventory.md) 和 [原生清单](../../.impeccable/review/2026-11-12-nsh050-native/native/evidence.json)。GTK 主矩阵 20 张：浅/深色 × 390 / font 1.0、360 / font 1.3 × 今日/流水/财富/规划/录入；补充财富滚动、录入滚动、工作区菜单、账户选择各 4 张，以及 390 浅深色的每日支出/财富 hover 各 2 张，共 40 张。官方未修改 Rust Gallery 的 390/1100 GTK 实拍用于组件研究，不是产品实现验收。

这些结果仅支持 Linux GTK 的已列场景；未做 Android、iOS、Web 运行验收、手机键盘或辅助技术验收，也未运行 Web detector。HTML sidecar 是文档面板译本，不替代原生控件。开发样例显式 opt-in 并使用隔离临时库，生产不自动注入演示数据。

## Do's and Don'ts

### Do:

- **Do** 优先使用 nsh 官方控件和 Plot，通过现有 wrapper 复用品牌样式与业务内容。
- **Do** 保留 Decimal 金额、币种、符号、缺估值说明和真实图表依据。
- **Do** 让完整标签、内容和触控空间随文字缩放增长，保持保存栏与滚动内容分离。
- **Do** 用实际原生运行证据核对主题、窄宽、文字缩放与交互状态。

### Don't:

- **Don't** 恢复旧的自绘按压、选择、菜单或 SVG 数据图形来追逐历史 HTML 稿。
- **Don't** 把 NumberInput 的浮点值或 Plot 的浮点几何写回财务事实，也不插值金额标签。
- **Don't** 用已知金额伪造完整估值、连接缺失区间或制造不存在的 sparkline。
- **Don't** 缩小触控空间、遮住表单尾部，或绕过草稿、保存与撤销保护。
- **Don't** 把 GTK、文档 HTML 或共享资源配置称为 Android、iOS、Web 的运行验收。
