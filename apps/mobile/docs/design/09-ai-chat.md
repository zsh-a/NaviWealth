# 09 · Assistant 与上下文 AI

本文只规定 AI surface 的呈现与交互。入口、上下文、工具权限、InteractionSession
和审批行为以 [AI 架构](../../../../docs/ai/ai-architecture.md) 为准；事件字段以
[AI Protocol](../../../../docs/ai/ai-protocol.md) 为准。

## 入口与布局

| 入口 | 当前呈现 | 作用 |
|---|---|---|
| 对象 capsule、insight、artifact follow-up | 当前页 inline bottom sheet | 围绕已有对象继续任务 |
| 命令面板 | 全局 overlay 发起 invocation | 表达动作并携带当前上下文 |
| `/assistant` | 全局会话工作区 | 保存、查看和继续会话 |
| 文件、截图、粘贴和分享 | 摄取及审核流程 | 先生成草稿，确认后写入业务记录 |

上下文 sheet 在视口高度不足 500px 时可升级为 fullscreen dialog。宽屏继续使用
同一交互协议和组件，不引入常驻 AI Drawer。AI 不是业务领域，不增加底栏页签。
所有入口构造 `AiIntentInvocation`，不直接拼装另一套聊天导航。

## 会话内容

- 入口保留 source、intent、当前对象和领域上下文；工具和数据范围由 active
  `DomainPack` 与路由决定。全局 Assistant 可使用全部已启用领域。
- 展示流式正文、工具状态、来源与提案，区分“已生成建议”和“已提交变更”。
- 错误提供所属流程可执行的重试或配置入口，不伪造成功，也不继续显示永久加载。
- 用户可继续已有会话。上下文压缩、恢复快照和 trace 各有独立职责，UI 不通过
  重建文本来代替持久化恢复协议。
- 语音是同一会话的输入/输出能力；部分识别文本保持可编辑。按当前 capability
  显示可用状态，不承诺所有平台都支持全双工。

## 提案与确认

提案卡呈现作用对象、变更及执行状态。确认强度由 `ProposalEnvelope` 的风险和
副作用派生：one-tap、diff 或 typed confirmation，不能由页面自行降低。
Pending `InteractionEnvelope` 优先于新 turn，语音输入不能绕过审批。

写入成功后呈现实际结果；仅在协议支持时提供撤销。摄取草稿未经确认不得进入
journal 或同步表。来源缺失或计算失败时如实呈现，业务金额由领域工具计算。

## 平台与数据边界

原生设备运行 AI Host/Runtime，使用用户配置的 `LlmProfile` 直接连接 provider。
Backend 不代理 AI 请求；Web 不加载 AI runtime。设备端运行不等于离线推理：
远程 provider 会收到本轮选择的 transcript/context。具体隐私权限由当前配置和
运行时策略决定，不在页面另设无法执行的数据保护承诺。

## 视觉与可访问性

使用现有 surface tone、细线图标、克制的 cursor 状态与 reply chip。禁止 neon
光效、机器人头像、悬浮聊天气泡和独立 AI tab。加载、出错、审批与播放状态须有
文字或语义标记，不能只依赖颜色、动效或声音。

键盘焦点、关闭、返回和 reduced motion 遵循共享 sheet、dialog 与设计系统。
展示金额时复用已有隐私展示和格式化组件，不以隐藏 UI 金额代替请求传输策略。

代码入口是 `apps/mobile/lib/features/ai_chat/`、
`apps/mobile/lib/core/ai/intent/` 和 `apps/mobile/lib/app/interaction/`。
