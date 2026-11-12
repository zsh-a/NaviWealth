FinanceOS Rust 客户端升级到 nsh 0.5.0，界面改用 nsh-base 官方组件与图表，保留温润纸感品牌色和今日／流水／财富／规划四个入口。

- 按钮、筛选、记账类型分段、账户选择、分类单选、开关、进度条、保存回执和更多菜单改为官方 Button、ToggleGroup、Tabs、Select、RadioGroup、Switch、Progress、Toast、Menu，状态、焦点与动效统一由框架提供。
- 净资产趋势改为官方面积图，带渐变、末点高亮和悬停查看；今日日支出改为官方柱状图；资产构成改为环形图；流水分类摘要改为堆叠条。缺价区间不跨缺口连线。
- 主题以 nsh 官方默认主题为底，只覆盖品牌颜色与数字字体。
- 金额输入仍为文本加精确 Decimal 解析，不使用会损失精度的浮点数字输入。

验证：251 项 Rust 工作区测试、23 个套件、格式检查和严格 Clippy 通过。GTK 原生截图覆盖浅深色、360／390 宽度、1.0／1.3 字号、弹层与悬停状态。

包信息：`com.naviwealth.client`，版本 `0.6.0`，build `8`，支持 `arm64-v8a` / `armeabi-v7a`。沿用 0.3.1 起的固定发布签名，可覆盖安装 0.3.1 及以上版本。内置 Android 运行时随 nsh 升级至 0.5.0。

Android、iOS、Web 的界面、字体与触摸手感尚未在设备上验收；本版 Android 运行时变化较大，建议先在测试设备上安装确认。

本轮未改 Flutter 客户端、数据模型及财务写入、余额、撤销规则。

[完整变更](https://github.com/zsh-a/NaviWealth/compare/client-v0.5.0...client-v0.6.0)
