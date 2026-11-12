---
name: "NaviWealth Native FinanceOS — 温润纸感"
description: "暖纸、墨绿与精确数字构成的原生个人财务工作空间。"
colors:
  light-background: "#FAF8F4"
  light-foreground: "#242D29"
  light-card: "#FFFDF9"
  light-card-foreground: "#242D29"
  light-hero: "#E6EDE5"
  light-popover: "#FFFDF9"
  light-popover-foreground: "#242D29"
  light-primary: "#315B49"
  light-primary-foreground: "#FFFFFF"
  light-secondary: "#F0EEE7"
  light-secondary-foreground: "#242D29"
  light-muted: "#F0EEE7"
  light-muted-foreground: "#626B63"
  light-faint-foreground: "#626B63"
  light-accent: "#E6EDE5"
  light-accent-foreground: "#242D29"
  light-destructive: "#995F50"
  light-destructive-foreground: "#FFFFFF"
  light-border: "#E5E4DB"
  light-input: "#E5E4DB"
  light-ring: "#315B49"
  light-contrast-border: "#7A7A7A"
  light-contrast-muted: "#4A4A4A"
  light-up: "#315B49"
  light-down: "#995F50"
  light-wash: "#E6EDE5"
  light-warning: "#805F33"
  light-data-cash: "#8A9884"
  light-data-investment: "#315B49"
  light-data-cash-surface: "#B8C7B4"
  dark-background: "#181E1A"
  dark-foreground: "#F0F0E8"
  dark-card: "#202923"
  dark-card-foreground: "#F0F0E8"
  dark-hero: "#304535"
  dark-popover: "#202923"
  dark-popover-foreground: "#F0F0E8"
  dark-primary: "#B5CCB6"
  dark-primary-foreground: "#1C3526"
  dark-secondary: "#29332C"
  dark-secondary-foreground: "#F0F0E8"
  dark-muted: "#29332C"
  dark-muted-foreground: "#ADB6AA"
  dark-faint-foreground: "#ADB6AA"
  dark-accent: "#304535"
  dark-accent-foreground: "#F0F0E8"
  dark-destructive: "#D9AA96"
  dark-destructive-foreground: "#1C3526"
  dark-border: "#384039"
  dark-input: "#384039"
  dark-ring: "#B5CCB6"
  dark-contrast-border: "#9A9A9A"
  dark-contrast-muted: "#C6C6C6"
  dark-up: "#B2CEB8"
  dark-down: "#D9AA96"
  dark-wash: "#304535"
  dark-warning: "#D5B889"
  dark-data-cash: "#8EA38B"
  dark-data-investment: "#B5CCB6"
  dark-data-cash-surface: "#718F79"
typography:
  type-page:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "25px"
    fontWeight: 600
  type-section:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  type-body:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  type-caption:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
  type-action:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "13px"
    fontWeight: 500
  type-surplus:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "49px"
    fontWeight: 400
    lineHeight: 1.15
    letterSpacing: "-1.5px"
  type-net-worth:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "43px"
    fontWeight: 400
    lineHeight: 1.15
    letterSpacing: "-1.5px"
  type-expense:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "39px"
    fontWeight: 400
    lineHeight: 1.15
  type-income:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "20px"
    fontWeight: 500
  type-mini:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "23px"
    fontWeight: 400
    lineHeight: 1.15
  type-allocation:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.15
  type-balance:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "24px"
    fontWeight: 500
  type-record:
    fontFamily: "Manrope ExtraLight, Noto Sans CJK SC, PingFang SC, sans-serif"
    fontSize: "34px"
    fontWeight: 400
  type-amount-input:
    fontFamily: "Manrope ExtraLight, sans-serif"
    fontSize: "51px"
    fontWeight: 400
    letterSpacing: "-1.5px"
rounded:
  control: "10px"
  card: "16px"
  row: "9px"
  field: "10px"
  sheet: "22px"
  pill: "999px"
  progress: "2px"
spacing:
  page: "28px"
  page-narrow: "24px"
  row: "12px"
  control: "12px"
  group: "28px"
  section: "28px"
  icon: "12px"
  choice-gap: "8px"
components:
  workspace-header:
    backgroundColor: "{colors.light-background}"
    typography: "{typography.type-page}"
    height: "76px"
  allocation-bar:
    backgroundColor: "{colors.light-data-cash-surface}"
    rounded: "{rounded.progress}"
    height: "14px"
  button-primary:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.light-primary-foreground}"
    typography: "{typography.type-action}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
    height: "48px"
  button-primary-dark:
    backgroundColor: "{colors.dark-primary}"
    textColor: "{colors.dark-primary-foreground}"
    typography: "{typography.type-action}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
    height: "48px"
  button-secondary:
    backgroundColor: "{colors.light-secondary}"
    textColor: "{colors.light-secondary-foreground}"
    typography: "{typography.type-action}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
    height: "48px"
  button-text:
    textColor: "{colors.light-primary}"
    typography: "{typography.type-action}"
    rounded: "{rounded.control}"
    padding: "0px 12px"
    height: "48px"
  field:
    backgroundColor: "{colors.light-background}"
    textColor: "{colors.light-foreground}"
    rounded: "{rounded.field}"
    padding: "0px 12px"
    height: "48px"
  choice-selected:
    backgroundColor: "{colors.light-wash}"
    textColor: "{colors.light-foreground}"
    typography: "{typography.type-caption}"
    rounded: "{rounded.control}"
    padding: "8px 4px"
    height: "56px"
  chip:
    backgroundColor: "{colors.light-muted}"
    textColor: "{colors.light-muted-foreground}"
    typography: "{typography.type-action}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
    height: "48px"
  flat-row:
    textColor: "{colors.light-foreground}"
    typography: "{typography.type-body}"
    padding: "12px 0px"
    height: "64px"
  navigation:
    textColor: "{colors.light-muted-foreground}"
    typography: "{typography.type-caption}"
    height: "60px"
  mini-card:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-foreground}"
    rounded: "{rounded.card}"
    padding: "12px"
  amount:
    textColor: "{colors.light-foreground}"
    typography: "{typography.type-surplus}"
---
# Design System: NaviWealth Native FinanceOS — 温润纸感

## Overview

**Creative North Star: "温润纸感"**

暖白纸面与墨绿操作色承托开放的大金额、短标签和紧凑流水。数字先于装饰，留白负责分组；表面只在选择、工具和有限的数据模块中出现。深色沿用同一语法，以森林色纸面建立层次。

本规范仅适用于 `apps/client`。用户批准 A「温润纸感」，今日采用 A 的开放主数字与 B 的两个迷你数据卡。视觉来源为 [A 方向稿](../../.impeccable/mocks/2026-11-12-directions/README.md)；运行值以 [theme.json](theme.json) 为准，复用实现以 [src/ui](src/ui) 和 [src/shell.rs](src/shell.rs) 为准；本次完整替换旧 Quiet Workspace 规范。Flutter 的设计系统保持独立。

**Key Characteristics:**

- 暖纸与墨绿，浅深两套完整语义色。
- Manrope 数字、平台中文回退、明确的金额与币种层级。
- 开放主事实、平面流水、有限边界；触控目标与状态可辨识。

## Colors

### Primary

墨绿是操作、焦点、选态和主要图形的共同语言。浅色使用深绿，深色使用浅鼠尾草绿；前景色随模式配对。`up` 与 `down` 保留财务方向语义，深色的 `up` 与主操作色有独立值。默认正常预算条使用主色；可用额为负时使用 destructive 进度与金额，规划分类明确写「超出」。

### Neutral

`background` 是暖纸画布，`card` / `popover` 是较清晰的纸面；`secondary` / `muted` 为控件承托，`hero` / `wash` / `accent` 标记选态与改变的事实。墨色用于主事实，`muted-foreground` 用于说明和币种。`border` / `input` 为细边界，`ring` 为共享焦点；高对比另有 `contrast-border` 与 `contrast-muted`。

`destructive` 承担支出、负余额和危险操作，`warning` 承担警示，`data-cash` 与 `data-investment` 分开现金和投资图形；`data-cash-surface` 专用于资产构成的大色块，不能替代现金文字色。收入有加号，支出有减号；无正号的正余额与零保持中性。颜色与符号共同表达方向；高对比使用既有对比色路径，隐私与方向偏好仍由业务规则负责。

前置 tokens 保留运行主题的完整浅深色角色；组件条目默认展示浅色，运行时按当前模式解析对应色。不要从色名推断新的业务状态。

## Typography

**Display / Body Font:** Manrope；原生注册族名为 `Manrope ExtraLight`，中文依次回退 `Noto Sans CJK SC`、`PingFang SC` 与系统 sans-serif。`ExtraLight` 是资源内部族名，不代表所有文字采用极细字重。

**Character:** 开放字腔和圆润转折给精确数字温度。金额使用 tabular 数字，主金额常规字重，行标题与行金额中等字重，页面与组标题半粗。角色大小和已有显式行高见前置 tokens；未显式指定的行高随原生排版。

`type-surplus` 用于今日结余与规划可用预算；`type-net-worth` 用于净资产；`type-expense` 用于流水汇总；`type-mini` 用于今日小卡；`type-income` 用于并列收支。资产构成双列数字用 `type-allocation`；账户余额与记录详情分别使用 `type-balance`、`type-record`。输入大金额使用 `type-amount-input`。`amount_live` 将完整数字保留在一个可访问段落中，币种为同基线小字；极长金额依据可用宽度适配，不能截断或改变数值。

nsh 把 `font-*` 保留给字体族；字号必须命名为 `type-*`。不要把字号写入 `font-*`，否则主题解析可能丢失维度。

**The Exact Fact Rule.** 金额按 Decimal 原值展示，货币小数位是最低显示位数；视觉格式化不改变业务数值。

`ui::format_money` 保留千分组、紧邻数字的 ASCII 正负号，以及更细的非零位。CNY/USD 最少两位、JPY 零位、KWD 三位、CLF 四位。编辑中的原始草稿与 Decimal 解析保持精确；离焦回显才分组，错误分组不被静默修复。数量、价格、比率与现金各守其精度，金额不做动画插值。

流水行（今日与流水）币种等于账户币种或基础币种时省略可见单位；只有两者均不匹配的外币，才用同基线小号文字紧随金额。未知账户不会隐式假定为本币；可访问标签保留原始币种。托管持仓的收益副行仍独立显示。

字体随包本地提供：[WOFF2](assets/fonts/manrope-latin-variable.woff2)（24,836 B）与 [SIL OFL 1.1](assets/fonts/Manrope-OFL.txt)（4,383 B），来自未修改的 [Fontsource variable Manrope 5.3.0](https://registry.npmjs.org/@fontsource-variable/manrope/-/manrope-5.3.0.tgz)。SHA-256 为 `a30ddcd349703aff7464c34bef3fffdff405ee50c113440d7c8693c02d210972`。原型 CSS 名称 `Manrope` 与原生内部族名指向相同字节，无外部字体服务。

模块通过 `registry.assets(assets!())` 打包，URI 为 `asset:/@naviwealth-client/fonts/manrope-latin-variable.woff2`；桌面直接入口另用 `Root::font(include_bytes!(...))`。GTK 和资源包已核对，编译期 FontAsset 测试断言内部族名。Android/iOS/Web 共享模块资源注册与配置，但未做这些平台的运行验收。

## Layout

以 4/8 逻辑单位节奏组织紧凑内容。前置 `spacing` 记录页边、行内与组间距离；窗口宽度不超过 370 时使用窄页边。尺寸是 nsh 逻辑长度，不承诺物理像素。工作区最小高 76，底部标签最小高 60，安全区另计；四根入口为今日、流水、财富、规划。顶部显示普通根标题；工作空间切换保留在「更多→切换工作空间」（`domain-switcher`），标题不再带箭头或点击行为。今日和流水有同一「记一笔」动作。

共享按钮、输入和图标目标最小高 48，常规流水最小高 64、上下各 12；内容可以增长。分类最小高 56、间距 8，按可用空间自适应一至四列。默认可见 12 类，「全部分类」可到达全部 26 个内置支出类别及自定义类别；已选隐藏类别会自动展开。文字缩放优先于固定行数。

今日以月结余、并列收支、预算可用与单日最高两个小卡、三条近期流水和下一笔安排推进。小卡按币种计算，缺少预算时给出设置入口。流水保持开放汇总、分类比例与日期分组；默认快捷项为全部、餐饮、交通、购物，交通精确对应公共交通分类。搜索按需展开，筛选针对完整分页结果。财富把净资产、双段资产构成、历史趋势和四个有计数的目的地分开阅读；构成条高 14，下方投资/现金双列数字与独立负债行分开。规划保留预算、目标、到期事实与原有细分工具。

## Elevation & Depth

当前共享纸面使用实色、留白、有限细边界和明度差建立深度，没有共享阴影或模糊 token。原生模态叠加半透明黑色遮罩（opacity-scrim），内容保持不透明；不要凭原型补上未实现的玻璃或纸纹。今日两个迷你卡使用细边界，普通流水不重复描边。

**The Flat Reading Rule.** 流水靠对齐与留白阅读；迷你卡、选择器与弹层有明确用途，不把每一行装进卡片。

## Shapes

控件与输入为小圆角，卡片适度舒展，编辑容器为较大的 sheet 圆角；值见前置 `rounded`。分类采用无彩色底徽章的统一线性 SVG；图标按 24-unit 画布、1.5 描边绘制，常规显示 20，分类选择内显示 16。全部内置分类和收入有语义符号，自定义使用 tag 回退；录入与流水共用 `category_icon`。

## Components

### Buttons and Focus

`primary_button` / `toolbar_action` 使用主色和配对前景，`secondary_button` 使用次级表面，`text_button` 用于轻动作与明确危险退出。所有共享目标走 `press_target`：可访问 Button 语义、最小触控高度、共享 2 单位焦点轮廓、按压 opacity 0.82 与 disabled opacity 0.45。输入显式设置文字、占位、光标与选区颜色；普通字段保留一单位边界。

按压过渡 160ms，列表布局 180ms；选择与入场使用 stiffness 420 / damping 34 / mass 0.6 的阻尼弹簧。编辑器入场位移 8。减少动态效果时取消缩放、位移和布局动画，直接显示最终选态；平台导航沿用原生过渡。完整运动和焦点信息放在 [客户端 sidecar](.impeccable/design.json)。

### Choices and Capture

分类为图标加完整标签的独立选择面，选中使用 wash、可见的 12 单位 Check SVG，并保留原生 selected 语义。筛选 chip 使用胶囊形；录入类型切换用安静底轨和 paper 选态。

**The Whole Label Rule.** 分类按最长完整名称、可用宽度与文字缩放决定列数，不在词中折行来维持列数。

轻量记录使用现有原生编辑容器，复杂工具保留现有页面流程。账户值与币种独立布局，选择列表显示全名。额外「对方」字段保留。保存栏独立于滚动区并预留安全区，末尾内容可滚动到达。金额、对方、备注 Enter 与按钮共享同一保存路径；退出继续走脏草稿保护，「继续填写」为主动作，「放弃修改」为危险文字动作。

### Rows, Navigation and Feedback

流水用共享 `transaction_amount_row`：语义分类图标、标题与账户、右对齐完整金额、本币省略单位且外币以小号同基线显示；可截断非关键标题，但完整可访问标签保留。投资记录继续写明操作与持有/结算角色，箭头只表达转账。持仓概览保留精确份额、真实托管账户与损益；完整成本仍在资产详情。导航使用原生 tab 状态、统一 SVG、小字和短选择线，保持既有路径与返回行为。已有 ID 保持不变，新增交互只补新 ID；`ledger-search` 留在展开的搜索输入，`ledger-filters` 留在现有 activity-tools 管理 sheet。

后台刷新保留已挂载内容，失败显示重试并保留最后数据，相同快照不重建；表单入口快照在编辑期间冻结。保存回执贴近改变的事实，受筛选影响时说明可见性。新增与普通删除保留跨根标签、跨详情页的 60 秒撤销、剩余秒数与失败重试；新动作替换旧 offer，编辑不提供删除式撤销，重启或到期结束。结构化投资与计划记录继续遵守原有保护。

### Data Graphics and Native Evidence

预算条、日支出柱和资产比例均来自实际数据；日支出含零支出日，按币种分开，转账和期初余额不计支出。峰值标日期与范围。趋势至少三个完整时点，标高低范围与首末确值，缺失证据保留缺口，缺少价格或 FX 明确提示。

对照见 [comparison.html](../../.impeccable/review/2026-11-12-direction-a/comparison.html) 与 [证据清单](../../.impeccable/review/2026-11-12-direction-a/evidence.json)：实际 Linux GTK 主矩阵 50 张，加录入滚动 10 张、财富滚动 10 张、账户选择 2 张与工作空间菜单 2 张，共 24 张补充，覆盖浅深色、360/390/411 宽和已列明的 1.0/1.3 文字缩放组合。它们不认证手机键盘、辅助技术或硬件表现；本轮未做 Web detector，也未做 Android/iOS/Web 运行验收。

原生相对稿件的有意差异包括平台承担系统 chrome、较大的触控目标、12 类折叠并可展开全部类别、保留对方字段、显式图表坐标与确值。不要称为逐像素复刻。开发预览由显式 opt-in 的 `examples/direction_a_seed.rs` 写入独立临时库，生产没有自动演示数据。

## Do's and Don'ts

### Do:

- **Do** 使用共享 `press_target`、焦点、金额与流水组件，保持原生语义和已有测试标识。
- **Do** 显示币种、方向符号、缺失估值与图表依据；混合币种分别呈现。
- **Do** 让内容和分类列数随文字缩放增长，保持保存栏与滚动内容分离。
- **Do** 用实际原生截图复核主题、窄宽、文字缩放和状态。

### Don't:

- **Don't** 改回冷灰钢蓝、添加纸纹或用玻璃效果替代已批准的实色纸面。
- **Don't** 把金额转成浮点数、四舍五入细位、动画插值或通过颜色单独表达收支。
- **Don't** 缩小触控目标、遮住表单尾部，或让视觉改动绕过草稿、保存与撤销保护。
- **Don't** 把 GTK、HTML 预览或共享资源配置称为 Android、iOS、Web 的运行验收。

### 审查后的数据展示契约

- 月度构成／收支／预算只依赖月份与 DataVersion；搜索、类型、分类与分页只刷新流水。切月立即清空旧月事实，构成错误独立显示；失败不显示旧月比例。
- 预算百分比保留超额值，只有条形宽度钳制到 0—1；今日、记账、流水共用 BudgetDisplay 与警示／“超出”文案。
- 单日最高来自按日、按币种的只读 Decimal 汇总；并列取最早日期，无正支出时不显示日期或高亮柱。
- 缺价币种保留已知资产／负债并标注“部分缺价”；不以已知金额伪造完整估值或占比。近 30 天不足三个完整历史点时回退到全部历史，缺失点保留为缺口。
- 选择器使用 SelectOption 的显式 label、trailing、currency；标签中“ · ”属于原文，不推断单位。根页标题由壳层 PageKind 控制，与标题语言无关。
