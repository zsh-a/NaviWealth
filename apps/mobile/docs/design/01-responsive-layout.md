# 01 · 响应式策略

本文描述当前组件的窗口适配。导航归属以
[LifeOS Shell](../../../../docs/architecture/lifeos-shell.md#multi-domain-ia)
为准；断点以 `apps/mobile/lib/design_system/tokens/breakpoints.dart` 为准。
不要在 feature 内再定义一套 `Breakpoint` 枚举或 Shell。

## 窗口与导航

| 窗口 | 导航策略 |
|---|---|
| 紧凑窗口 | 领域内底栏和工作区切换器 |
| 中等窗口 | 领域内导航轨和工作区切换器 |
| 大窗口（1200dp 起） | 单一侧栏：Life、已启用领域及当前领域页签 |

`Breakpoints.mobile` 为 600dp，`expanded` 为 840dp，`large` 为 1200dp。
组件按可用宽高选择自己的布局，不把屏幕宽度等同于设备或输入类型。
页签数量来自当前 `DomainPack.tabPaths`，不固定为五项。桌面不叠加第二个领域侧栏。

## 内容与表单

内容优先保持阅读顺序、可访问性语义和可执行操作。宽屏可使用现有列表/详情与
多列组件，窄屏保持单列或导航到详情；不要求所有页面都变成表格或分栏。
使用现有 content/reading/dialog/form 限宽 token，不直接铺满超宽窗口。

复杂记录表单在各窗口都使用完整页面和离开确认。轻量录入通过同一
`showAppFormSheet` 入口：可用宽度至少 840dp 且高度至少 480dp 时为中央 dialog，
其他情况为限宽 bottom sheet；最大表单宽度由 `Breakpoints.sheetFormMax` 控制。
键盘弹出、safe area、关闭与 dirty guard 由共享容器处理。

AI 上下文入口始终遵循 [AI surface](09-ai-chat.md) 的 sheet/dialog 规则，
不以桌面宽度为条件切换成常驻聊天 Drawer。

## 输入与可访问性

- 同一布局支持触摸、鼠标和键盘；操作不只依赖 hover、右键或拖动。
- 使用共享控件的 focus、hover、pressed 与 disabled 状态；不重复绑定手势。
- 对话框和 sheet 支持关闭、焦点恢复及键盘避让；已编辑表单保留放弃确认。
- 使用系统 text scaling、语义字号与 tabular figures。密度由主题输入决定，
  不手动缩小系统文本。
- 主从分隔条在提供拖动时也提供键盘和辅助技术操作。
- Cmd/Ctrl+K 与领域页签快捷键沿用 Shell 的绑定。具体快捷键以实现为准，
  不在各页面复制一份全局快捷键表。

## Web 与验证

Web 的字体、路由、离线与平台限制分别由
[Web 字体](13-web-fonts.md)、
[Web Routing](../../../../docs/development/web-routing.md) 和
[Web Compatibility](../../../../docs/development/web-compat-matrix.md) 拥有。

改动布局后检查窄屏和桌面窗口、软键盘、text scaling、触摸/键盘操作和 reduced
motion。关键内容不得被导航 chrome 遮挡；错误和空态仍须可见且可操作。
