# 采集 AI 追问体验调研：对话时间线（chat timeline）设计与可行性

状态：调研 + 决策记录。Owner 于 2026-11-15 采纳 **chat timeline** 方向；
ADR 已起草：`docs/architecture/capture-conversation.md`（本 worktree），
Product Scope Rule 3、Removed 表与 roadmap 增量（"Conversational capture thread"）
同步修订。本文档保留调研过程，§3 为采纳后的目标体验设计。
Worktree：`feat/ai-capture-chat`（基于 main @ 48659bae4）。日期：2026-11-15。

---

## 结论先行（2026-11-15 更新：方向已定）

**采集本身就是一段有界对话（bounded conversation）。**

- 输入（文字/照片）即线程首条消息；识别结果、追问、纠正都是线程内的回合；
  现在的"输入回顾"块与双角色纠正框随之消失。
- 边界不放松（见 ADR）：线程只存在于一个采集草稿内；模型只回应 owner 主动发起的
  回合（无自主回合、无工具、无跨草稿记忆、无命名代理）；确认仍是原子批写、
  缺字段仍阻断；consent 门不变；线程与草稿一样不进备份。
- 质感四要素不变：问句有 AI 身份、点选优先（tap > type）、问答相邻、确认边界稳定。
- 流式仍不做（NSH fetch 整包返回，`data/vision.rs:29-31`）；线程内 typing indicator
  表达"工作中"，结果整回合出现。
- 实施序列见 §7。

---

## 1. 现状还原："AI 提问"今天长什么样

采集流程（`apps/nsh-client/src/pages/capture/mod.rs`，模块注释：
"One text/image composer. Results are records to review, with one natural language correction box."）：

```
输入文字/照片 → 识别（单次结构化 LLM 请求，strict JSON schema）
  → Draft { records, question, status }
      ├─ records 非空 + question 为空（缺字段用 null 表达，逐卡显示警示行）
      └─ records 为空 + question 非空（两者互斥，domain/capture.rs:184-188）
  → 用户改（打字一句 → 整份重跑；或点记录卡里的账户行开选择器）
  → 确认保存（原子批写，草稿消费）
```

"提问"实际有三种形态，全部汇入同一个通用纠正框：

| 形态 | 来源 | 渲染 |
|---|---|---|
| 模型问句 | `Draft.question`（最多一条字符串） | 纯正文一行，`Type::Body` + `INK`（mod.rs:505-512） |
| 缺字段警示 | `MoneyDraft` 的 `Option` null → `Missing` 枚举 | 逐记录 CAUTION 文案（`capture_need_account` 等，summary.rs:223-233） |
| 新账户提示 | 模型按规则提议 `资产:name` | `"{name} · New account"` + `capture_no_accounts` |

关键代码事实：

- 请求是**单轮**：`LlmRequest.messages = [System, User]`，多轮是伪的——
  把 `{input, correction, previous_draft, context}` 整体塞进一条新 User 消息
  （`data/vision.rs:210-220`）。模型没有"上一轮我问过什么"的连续性。
- 回答成功后 `correction` 被消费清空（`data/capture.rs:158-160`）。
- 问题与输入框分离：问句在记录卡下方，输入框在其下、标题是"补充或纠正一句"，
  placeholder 是通用例句"例如：用的是招行信用卡；只吃了一半"——**不回声当前问题**。
- 点选回答只有一条窄路：记录卡里的账户行 → 账户选择器（`pages/capture/accounts.rs`），
  且选择器只列现有账户；records 为空时连可点的行都没有。
- NSH fetch **整包返回**（`data/vision.rs:29-31`："NSH fetch is local to its engine thread
  and currently returns a whole body"），无流式；`llm-client::Client::stream` 存在但不可用。
- agent-runtime 的 `agent-chat` 已有多轮 + `InteractionEnvelope{options, custom_text}`
  挂起/恢复机制，但 app 只依赖 `llm-protocol`/`llm-client`，未使用（也不建议引入，见 §4）。

### 为什么"感觉不够直观"——六条诊断

1. **问句没有视觉身份。** 一行 `Body/INK` 正文，夹在记录卡和"补充或纠正一句"标题之间，
   读起来像说明文字，不像 AI 在问你，更不像一个待办。
2. **问答断裂。** 问题与答案框之间隔着标题和通用例句；心智上要自己配对。
   缺字段时更糟：三张卡各有一行警示，却只有一个框可答。
3. **点选优先被倒置。** 最高频的问题"这笔钱用哪个账户？"是**有限选项集**
   （`known_accounts` 明明已随 context 发给模型），却要求打字回答，
   或去发现"点账户行"这条隐藏路径。
4. **全量重解析的不稳定感。** 补一句就整份草稿重跑，结果可能整体变化；
   没有对话史，模型可能"改对一处、弄丢另一处"。
5. **AI 没有存在感。** 分析中只有 spinner + "正在整理记录…"；
   `AI_FROM→AI_TO` 渐变（theme.rs:65-66）只在草稿卡边缘用过，问句本身毫无 AI 质感。
6. **等待态单一。** "识别"是一个 150s 超时的黑盒往返，中途无任何状态分层
   （对比：DESIGN.md 的动效清单里餐页有"AI 光扫过照片"）。

---

## 2. 外部调研：行业怎么做"AI 追问"

要点（来源见文末）：

- **澄清式提问（clarifying questions）是公认模式**：意图歧义时先问再动，
  ask-to-disambiguate 优于默默猜测（ShapeofAI 的 Follow-up/clarification 模式）。
- **任务型对话的主流是槽位填充（slot-filling）混合结构化控件**：
  聊天负责开放表达，受限数据（金额、账户、日期）落到 chips/pickers/forms。
  纯聊天时间线用于"受限数据录入"反而增加错误率与学习成本——所以我们把
  记录摘要卡、账户选择器、chips 都内嵌进线程，而不是让一切经过文字。
- **信任来自控制与透明**：显示 AI 在做什么、给用户随时退出的控制。
- **感知性能**：请求发出的瞬间就要有 typing indicator，状态之间不能有死区
  （"no dead air"）；typing dots + 渐变光晕 + 克制动效 = 2025/26 的"高级 AI 质感"标配。
- **Intent-driven shortcuts**：AI 主动给出可点建议而非等用户打字——
  正是"点选优先"的方向。

**推论：chat-like 的"高级感"拆开是四件事**：① 问句有 AI 的视觉身份（渐变/光）；
② 答案能点就不打字；③ 问答视觉相邻、有来有回；④ 确认边界稳定（AI 只补草稿，
不替你保存）。chat timeline 是承载这四件事的完整形态。

---

## 3. 目标体验设计（采纳方向：chat timeline）

采集 sheet 内是一条**对话线程**：owner 的输入是首条消息，AI 的识别结果与追问
是后续回合，答完即就绪，确认边界不变。

### 线程布局

```
┌────────────────────────────────────────────┐
│  新记录                              ✕     │
│                                            │
│              ┌────────────────────┐        │
│              │ 午饭32元 现金付的  │        │ ← owner 首条消息：右侧墨药丸
│              │ [照片]             │        │
│              └────────────────────┘        │
│ ┃ ✦ 正在整理记录… ···                       │ ← typing dots（AI 渐变着色）
│ ┃ ✦ 识别出 1 笔支出：                       │ ← assistant 回合 = 结果卡
│ ┃ ┌────────────────────────────┐           │    （原 receipt 摘要卡内嵌进
│ ┃ │ 支出 ¥32.00 · 餐饮 · 今天   │           │     线程，账户行仍可点开选择器）
│ ┃ │ 账户：______                │           │
│ ┃ └────────────────────────────┘           │
│ ┃ 这笔钱用哪个账户？                         │ ← 同回合内追问气泡
│ ┃ (现金) (支付宝余额) (招行信用卡) (其他…)    │ ← chips：known_accounts
│                                            │
│              ┌──────────────────┐          │
│              │ 招行信用卡        │          │ ← owner 点选 → 药丸回显
│              └──────────────────┘          │
│ ┃ ✦ 已更新：支出 ¥32.00 · 招行信用卡        │ ← 就绪卡；旧版本折叠为"已更新"
│ ┃ ✦ 估计热量约 520 kcal，可修改             │ ← 估算提示保持 CAUTION 语义
│                                            │
│ [想记下什么？或补充一句…             ] [📷][↑] │ ← 输入常驻底部（键盘上方）
│            [ 确认保存 (1) ]                │ ← 固定主操作，就绪才启用
└────────────────────────────────────────────┘
```

### 回合与渲染

- **owner 回合**：右侧墨色药丸（`ACTION`/`ON_ACTION`），文字或缩略照片；点击可撤回重答。
- **assistant 回合**：左侧，AI 渐变 hairline（`AI_FROM→AI_TO`）+ Sparkle 标；一个回合可同时含
  结果卡（1–n 条记录摘要，复用 `summary::records` 的交互）、追问气泡（1–3 问）、估算提示。
  空输入/纯歧义时回合只有问句；失败是带"重新识别"的回合，不再整页换态。
- **旧版本折叠**：结果卡更新后，旧卡收起为一行"已更新"，最新版本完整展开——
  线程保留下文，又不淹没当前事实。
- **chips**：账户/分类类问题必须给 options（`known_accounts`、默认分类，客户端本地生成
  与模型 options 合并）；"其他…"聚焦输入框。自由输入永远可用。
- **空线程态**：进入 sheet 先见"想记下什么？"占位 + 照片按钮；"手动录入"披露与
  收藏 tiles 保留在空线程态，线程开始后收进输入行上方的轻量动作行。
- **动效**：新回合 `appear`（rise 14pt + fade，stagger 50ms）；请求发出的瞬间出现
  typing dots（无死区）；结果整回合进入，不做逐字流式。Reduced motion 全部即时。

### 交互规则（边界，与 ADR 一致）

1. **确认边界不变**：线程永不保存；`capture::ready` 校验不变；确认是固定主操作、
   原子批写；缺字段、未决问题存在时禁用。
2. **records 与问句可同回合**：放宽现在"question XOR records"的互斥——
   AI 可以"先按这样记着，再确认一句"；确认仍以就绪为准。这让"先给结果再追问"成为自然对话。
3. **点选优先**：受限集合（账户/分类）的问题必须先给 chips；文字是补充而非默认。
4. **模型只回应答**：没有自主轮次；每次 AI 说话都对应 owner 的一次发送。
   成本由 owner 主动回合数决定，不设硬轮数上限（无自主性即无失控面）。
5. **线程随草稿生灭**：transcript 存入 draft（`capture_drafts.body`），重开草稿可见完整
   来龙去脉；确认消费、丢弃删除；不进备份（与草稿现状一致）。
6. **多轮请求**：有线程时用真实消息史（`[System, User, Assistant, User, …]`）；
   图只随首轮；旧格式裸字符串问句降级为单条纯问句回合。
7. **consent 不变**：首次发送前仍走识别同意页；"不再询问"按模型账户记忆。

---

## 4. 技术可行性

| 层 | 现状 | 需要的改动 | 量级 |
|---|---|---|---|
| 协议 | `LlmRequest.messages: Vec<LlmMessage>` 支持任意轮（llm-protocol types.rs） | 无改动；线程直接构造交替消息 | 零 |
| Schema | `question: string`，与 records 互斥（domain/capture.rs:184-188） | `questions: [{text, kind, options[]}]`，可与 records 同回合；`PROMPT_VERSION` 递增；strict JSON schema；schema 归 app 层，`navi-finance`/`navi-health` 不动 | 小 |
| 请求 | 单轮，previous_draft 整体塞 JSON（vision.rs:210-220） | 线程存在时改为真实多轮消息史；图仅首轮；无线程（首次）仍是一条 User 消息 | 小 |
| 持久化 | `capture_drafts.body` JSON 整体存储（db.rs:61），不进备份 | `Draft` 加 `transcript: Vec<Turn>`，随 body 序列化，无迁移 | 极小 |
| 传输 | NshTransport 整包返回，`complete()` 单发，150s 超时 + RUNS 竞态丢弃 | 无改动（不做流式） | 零 |
| UI | chip / spinner / shimmer / skeleton / appear / `fitted_task_sheet`（键盘规划已内置）；AI 渐变、Sparkle 已有 | 新增：消息药丸、assistant 回合容器（渐变 hairline）、typing dots、chips 行、旧版本折叠；全部在一个 sheet 内，无新路由 | 中（纯客户端） |
| 测试 | headless capture 流（nsh-testing） | 补：chips 作答、多轮纠正、重开草稿见线程、裸字符串问句降级、records+questions 同回合、失败重试回合 | 中 |

**不建议**引入 agent-runtime 的 `agent-chat`：其挂起/恢复、工具轮、会话状态是为
自主代理设计的；线程只需要"消息史 + 结构化问句"两个概念。app 保持只依赖
`llm-protocol`/`llm-client` 的最小面。

---

## 5. 方案分级（采纳后重述）

- **已采纳 — Chat timeline**：§3 完整设计，ADR 已起草。原 Tier 1 的全部组件
  （问句卡、chips、typing dots、回答药丸）被线程吸收为回合渲染的一部分，不单独落地。
- **暂缓 — 真流式（原 Tier 3）**：需要 NSH `fetch` 分块升级（平台层，需 nsh 侧证据）。
  日用观察后再决定是否立项；此前用 typing dots + 整回合 appear 表达"工作中"，
  不假装流式。

| | 采纳：chat timeline | 暂缓：真流式 |
|---|---|---|
| 解决的痛点 | 诊断 1–6 全部 | 感知性能上限 |
| Scope | ADR + Rule 3 修订（本 worktree 已起草） | 传输层升级另议 |
| LLM 往返 | owner 主动回合数决定（图仅首轮） | 同左 |
| 风险 | 低（边界靠 ADR + 系统提示 + 无自主轮次） | 中（平台依赖） |

---

## 6. 风险与边界

- **确认边界**是信任底线：线程只改草稿；确认按钮固定、原子批写、就绪才启用；
  任何回合都不得产生"AI 已保存"的暗示。
- **成本与延迟**：由 owner 主动回合数决定；图仅首轮；组问（1–3 问一次答）减少往返；
  transcript 随轮次增长但草稿体量小（输入上限 2000 字符、记录 ≤10 条）。
- **键盘与高度**：sheet 已 plan-for-keyboard（`fitted_task_sheet`）；线程滚动区 +
  固定输入行 + 固定确认的组合需在窄屏（360×640）与大字号下过 headless 流。
- **模型输出质量**：结构化问句依赖提示词遵守；strict JSON schema + llm-client 内建
  修复轮 + 裸字符串降级兜底。多轮会放大提示词问题——实施时用真实模型跑常用句式
  （账户指代、金额口语、多记录、与记账无关内容的拒答引导）。
- **跑题风险**：系统提示限定"只讨论把这条输入变成记录"；线程无推荐、无闲聊、
  无记忆，即无 Agent 化路径。
- **备份策略不变**：线程与草稿一样不进备份；若未来要进，是新的 schema 决策。

---

## 7. 落地顺序

1. **决策文档（本 worktree 已完成草稿）**：ADR `capture-conversation.md` +
   Product Scope Rule 3 / Removed 修订 + roadmap 增量 "Conversational capture thread"。
2. **实现**：schema `questions[]` + 真多轮请求 + `transcript` 持久化 + 线程 UI
   （药丸/回合容器/typing dots/chips/折叠）+ i18n（en/zh）+ headless 流；
   实现落地时更新 Product Scope Interaction Model 与 `apps/nsh-client/DESIGN.md`。
3. **真实模型验证**：常用句式与拒答引导（roadmap 既有 "real-model quality" 门）。
4. **日用观察后**决定是否立项流式传输（Tier 3）。

---

## 参考来源

- [What I've learned from 18 months of AI conversational UI design (r/UXDesign)](https://www.reddit.com/r/UXDesign/comments/1ju90qt/what_ive_learned_from_18_mths_of_ai)
- [Chatbot UX Patterns: Streaming, Errors, Citations & More (ai-tldr.dev)](https://ai-tldr.dev/learn/building-ai-apps/ai-ux-patterns/chatbot-ux-patterns)
- 其余为 2026-11 网络检索要点，出处以标题记录（检索结果链接为跳转地址，未逐一固化）：
  "ShapeofAI — AI UX Patterns: Follow-up / clarifying questions"、
  "9 UX Patterns to Build Trustworthy AI Assistants"、
  "AI Chat UI Design: Best Practices for 2026"、
  "Conversational AI Design Patterns: Build Natural Dialogues"（槽位填充/澄清/纠错模式）。
