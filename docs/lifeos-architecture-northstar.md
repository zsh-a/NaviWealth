# LifeOS 北极星（架构约束）

> **这份文档不是路线图、不是产品规划、不是新设计**。
> 它的全部目的是：在我们决定做 LifeOS 之前，先约束**今天的代码不犯将来无法回头的错**。
>
> 重要：本文档定义的是**新增代码必须遵守的规则**。当前仓库已有不少违反规则的历史代码，
> 这些**显式登记为已知例外**，不要求立刻重构。每条规则都给出收敛方向，作为未来碰到该
> 区域时的目标。
>
> 适用对象：所有新增 `lib/core/` / `apps/backend/` 的代码、新增 feature 模块的契约设计、
> 跨 feature 协调代码。

---

## 0. 定位（30 秒）

NaviWealth = LifeOS 的 **FinanceOS** 层（今天唯一存在的域）。
未来可能出现的 HealthOS / TimeOS / LivingOS 是**同级**的域，不是 NaviWealth 的子页面。

LifeOS 的价值在**跨域基础设施**（Identity / Memory / Sync / AI Runtime / Agent / Storage）
能被所有域共享，而每个域**只关心自己的业务**。

> 但 **HealthOS / TimeOS / LivingOS 今天不进开发计划**。本文档只保证：
> 当未来真要做时，我们不必先回头拆 NaviWealth。

---

## 1. 反目标（hard NOT — 当前一律禁止）

| # | 反目标 | 为什么 |
|---|---|---|
| 1 | **不引入"可能用上"的枚举/类型/字段** | 2026-05-24 boundary audit 清理了大量 phantom infrastructure 就是因为历史上有过这种习惯。任何新 API 必须有当前 caller |
| 2 | **不为"将来可能 LifeOS"提前抽象** | 抽象在落地第二个域时再做；只做一个域时的"通用化"全是猜测 |
| 3 | **不全面 pivot 到 Flutter+Rust local engine** | AppFlowy 模式假设有团队；solo 维护 FFI + protobuf + 多端构建会拖垮 FIRE 节奏 |
| 4 | **不重构 NaviWealth 现有 IA** | Today / Activity / Wealth / Plan + Settings + Search 已锁定；LifeOS 多域 shell 是 Phase D 范畴，不在当前 IA 内 |
| 5 | **不在 finance 模块里直接 import Health / Time / 未来域的实体** | 反过来也禁止；跨域依赖只能走基础设施层 |
| 6 | **不为 LifeOS 改 sync-v2 的 row-state 形态** | `docs/sync-v2.md` 的"generic versioned blob + LWW"已经足够通用；不要升级成事件平台 / CRDT 框架 / 多 schema 协商 |
| 7 | **不做大社交 / 高频内容 / 通用 SaaS / 企业协作 / ToC 娱乐** | 这些与 solo + FIRE lifestyle 冲突，运维和支持负担会摧毁北极星 |
| 8 | **不写 LifeOS 路线图文档** | 包括"Phase 0–N"列表、季度目标、模块依赖图；这些只有在真的开始做时再写 |

---

## 2. 边界（新规则 + 已知例外 + 收敛方向）

> 每条规则三段：
> - **Rule**：新增代码必须遵守
> - **Known exceptions**：当前违反规则的现有代码（不要求立刻重构）
> - **Exit direction**：未来碰到这些区域时往哪走（没有 deadline）

### 2.1 跨层依赖方向

**Rule**：依赖只能从**上层 → 下层**，按
`体验层 → 域业务层 → 跨域基础设施层` 单向。
新增 `core/` 代码**禁止** import `features/` 或 `data/domain/`。
新增 `features/<A>/` 代码**禁止** import `features/<B>/`（除 `features/shared/`）。

**Known exceptions**：
- `core/ai/runtime/device/tools/*` 里 21+ 个 Finance tool 实现直接 import
  `features/fire/`、`features/investment/`、`features/cashflow/` 等
- `core/sync/` / `core/auth/` / `core/ai/write/` / `core/ai/trace/` /
  `core/ai/llm_credentials/` 等 import `data/db/`（共享 persistence adapter）和
  `data/domain/`（Finance 业务实体）
- `features/ai_chat/data/providers.dart` 跨 import `features/{assets,expense,fire,
  home,investment,liabilities,settings}` 作 chat context composition root

**Exit direction**：见 §2.2（AI tools 分层）+ §2.3（data/db 重定位）+ §2.4
（cross-feature composition 上提到 app 层）。

### 2.2 AI Tool Contract vs Implementation

**Rule**：**契约**（`ToolDescriptor` / `DeviceTool` 抽象 / dispatcher / agent loop）
跨域中立，放 `core/ai/`。**实现**（具体 `propose_fire_plan_update_tool`、
`get_holdings_tool` 等业务 tool）属于业务域，**不**新增到 `core/ai/runtime/device/tools/`。

```
core/ai/runtime/        provider-neutral agent loop
core/ai/contracts/      ToolDescriptor / DeviceTool 抽象 / AiTrace / ProposalEnvelope
features/<domain>/ai_tools/    该域的 DeviceTool 实现
app/                    composition root：collect 各域 ai_tools → DeviceToolRegistry
```

**Known exceptions**：当前所有 34 个 device tool 实现都在 `core/ai/runtime/device/tools/`，
其中绝大多数是 Finance 业务 tool。

**Exit direction**：未来加新域 tool 必须放进 `features/<域>/ai_tools/`。
现有 Finance tool 的迁移**不在计划中**——既不在下一批重构任务里，也不要求"碰到就顺手迁"。
只有当真的开始做第二个域（Phase D 触发，见 §4）时才统一拆分。在那之前，
`core/ai/runtime/device/tools/` 的现有 Finance tool 维持原位、继续接受常规修改。

### 2.3 持久化层（`data/db/`）

**Rule**：`data/db/` 是**全 App 的本地存储 adapter**（Drift / SQLCipher / sqlite WASM），
不只服务 Finance 域。其它跨域基础设施（sync、auth、AI trace 等）允许 import。
`data/domain/` 是 **Finance 业务实体**（Account / JournalEntry / Money 等），
**只**服务 Finance 域。

**重要**：跨域基础设施依赖 `data/db/` **只能**用于自己拥有的表（`ai_traces`、
`sync_outbox`、`auth_session` 等）。**禁止**通过 DB 句柄直接查询 Finance 业务表
（`accounts`、`journal_entries`、`postings` 等）绕过 domain boundary——这种查询
必须经过 `features/<finance>/data/repositories/`，否则一旦未来出现第二个域，
基础设施就会把 Finance 概念硬编进自己。

**Known exceptions**：当前 `data/` 顶层混合了 adapter 与 domain（命名/位置上不清晰），
读者需要自行区分子目录。

**Exit direction**：当未来出现第二个域时，把 `data/db/` 改名/移到 `core/persistence/`
之类的位置以反映其跨域角色；`data/domain/` 与其它 Finance 专属数据可以保留为
`features/finance/data/` 或 `apps/mobile/lib/finance/data/`。
今天**不**做，纯改名收益不抵成本。

### 2.4 Cross-feature orchestration

**Rule**：跨 feature 的协调代码（典型：AI chat 需要拉取 anomaly + maturity + fire +
investment 信号给 LLM）**禁止**新增到 sibling feature 内。它应该住在 `app/` composition
root 或 `core/` 跨域基础设施里。

**Known exceptions**：`features/ai_chat/data/providers.dart` 当前直接 import 7+ 个 sibling
features 来 compose chat context。

**Exit direction**：把 chat context composition 上提到 `app/composition/` 或
`core/ai/composition/`，让 `ai_chat` 不再认识其它 feature。这一步**今天不做**；
boundary audit 已经把 chat composition 体积大幅压缩，进一步重构的边际收益现在不高。

### 2.5 跨域基础设施的契约面（已守住的红线）

下列子系统**当前数据形状已经跨域中立**——不带 `Money` / `Account` 等 Finance 概念。
新代码**不得**让它们沾上业务实体：

| 子系统 | 中立性约束 |
|---|---|
| `core/ai/contracts/tool_descriptor.dart` | `ToolDescriptor` 字段：`name / access / risk / requiresConfirmation / allowedContextTier / sideEffect`。tool 输入/输出 schema 是 JSON，不要求 Dart 业务类型 |
| `core/ai/contracts/ai_trace.dart` | 无 finance-specific 字段；intent label 自由文本 |
| `core/ai/contracts/ai_span.dart` | Opik 风格 span，纯通用 |
| `core/ai/contracts/proposal_envelope.dart` | 3 子类（LocalImmediateWrite / LocalProposal / ExternalSideEffect），payload 是 `Map<String, Object?>` |
| `core/ai/intent/ai_intent_invocation.dart` | `intent` 是字符串 + 注册表；无域字段（未来加 `domain` field 是 Phase D） |
| `core/sync/` 协议层 | row-state generic blob，不感知 row 是 finance 还是其它 |
| `core/auth/` 协议层 | JWT + user id；与域无关 |

### 2.6 Memory Layer：当前唯一一个"无 caller 但保留"的例外

`core/ai/local/embedding/` 今天是 `StubEmbedder` + `InMemoryVectorStore` + `SemanticMemory`，
**零生产 caller**。docstring 标注"deliberate dormant"。

**Rule**：其它子系统**禁止**沿用此特例。Memory Layer 是唯一可以接受"无 caller 但保留"
的原因是：它跨域价值最高、下一步落地概率最大，并且 contract 重写有非平凡设计成本。

**Exit direction**：未来要把 Memory Layer 做实时：
- **MUST** 先定义 contract（`MemoryEntry / Chunk / EmbeddingModel / SearchQuery / SearchHit`）
- **MUST** contract 跨域中立（不写 "finance memory" 这种类型）
- **MUST** 至少有一个 Finance 域 caller 才合并实现（不空转）

---

## 3. 三层约束（按层归位）

```
   ┌─────────────────────────────────────────────┐
   │  体验层 (Flutter UI / Forui / Design System) │  ← 每个域有自己的
   ├─────────────────────────────────────────────┤
   │  域业务层 (Finance: ledger / portfolio /     │  ← features/ + data/domain/
   │            FIRE / cashflow / options ...)    │     单域内自洽
   ├─────────────────────────────────────────────┤
   │  跨域基础设施 (Identity / Memory / Sync /     │  ← core/ — 必须跨域中立
   │                AI Runtime / Agent / Storage) │     （tool 实现是已知例外）
   └─────────────────────────────────────────────┘
```

- **体验层**：可以 import 域业务层 + 基础设施。Finance 体验 = `features/*/ui/`。
- **域业务层**：可以 import 基础设施，**禁止**反向；禁止跨域（cross-feature 是例外，见 §2.4）。
- **跨域基础设施**：**应该**只依赖 framework；当前有 tool 实现/persistence 例外（§2.2/§2.3）。

PR review 凡触及 `core/` 的，必须能口头答清"它在哪一层 + 是不是登记过的例外 + 新增依赖是否引入新违规"。

---

## 4. Phase D 占位（未来才碰）

> 以下不是计划，不写时间。只是把"如果 Phase D 真要做"的最小必要变更列出来，
> 让今天的人不会无意中关掉这扇门。

**触发条件**：决定要做第二个域（Health / Time / Living）。

**触发时的必做项（不在今天的范围）**：

1. IA 重做：当前 Today / Activity / Wealth / Plan 是 Finance 视角，多域 shell 需要不同形态
2. `core/auth` 增加跨域权限模型（今天是单 user / 全访问，未来可能要"域级 opt-in"）
3. `core/sync` 的 row family 划分要按域 namespace
4. AI Intent 注册表要加 `domain` 字段（今天 intent 全是 finance）
5. Trace `AiTrace.intent.capability` 可能需要加非 finance 的值
6. `core/ai/runtime/device/tools/` 里的 Finance tool 必须先迁到 `features/*/ai_tools/`
7. `data/db/` 改名/移位以反映其跨域角色（§2.3）
8. `features/ai_chat/data/providers.dart` 的 cross-feature composition 上提到 app/composition root（§2.4）

**今天唯一需要做的事**：当某个 PR 想做以上 1-8 任何一项的"提前抽象"时，**拒绝**——
援引本节"未来才碰"。

---

## 5. 与现有文档的关系

| 文档 | 当前 SSOT 状态 | 与本文档关系 |
|---|---|---|
| `docs/ai-architecture.md` | AI 当前架构 SSOT | 本文档约束新增 AI 代码不再制造跨域污染；具体 AI 实现细节看那里 |
| `docs/ai-boundary-audit.md` | 历史审计（已落地） | 本文档继承其"无 caller 不引入"原则 |
| `docs/sync-v2.md` | sync 当前协议 SSOT | 本文档明确禁止为 LifeOS 改 sync 形态 |
| `docs/roadmap*.md` | Finance 域产品路线图 | 本文档**不重复**任何路线内容；只约束架构边界 |
| Locked IA (Today/Activity/Wealth/Plan/Settings/Search) | 仓内尚无独立 IA 文档；现状即 SSOT | 本文档明确 LifeOS 多域 shell 不修改当前 IA |

---

## 6. 如何使用本文档

- 提 PR 前自问：本 PR 是否违反 §1 反目标 / §2 边界？
  - 违反 = 改 PR，**或**新增条目到 §2.x 的 Known exceptions（需要论证为何无法避免）
- 改本文档前自问：是不是真的有新的客观约束变化（如：决定做 HealthOS）？
  只是想"扩抽象"不算
- 本文档应**短**——原则上 < 200 行；超出意味着在写规划，不是约束，需要砍

> 当前长度目标：原则上 < 200 行。
