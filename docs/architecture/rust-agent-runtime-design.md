# Rust Agent Runtime 设计文档

> Current implementation note: this document describes the long-term design
> direction. For the current code map, maintenance routing, and known design
> drift, start with
> [`agent-runtime-current.md`](agent-runtime-current.md), then use
> [`rust-agent-runtime-mvp.md`](rust-agent-runtime-mvp.md) for implemented
> feature status.

## 1. 背景与目标

希望将现有应用内的 agent 架构抽象成一个独立、可复用、可调试的 runtime，使其可以用于：

- Flutter 本地应用
- 后端服务
- 新的业务应用
- 独立 CLI 调试环境
- 类似 Claude Code 的本地 agent 运行、replay、trace、tool 调试

核心目标是把 agent 的通用能力从具体业务中剥离出来。

通用能力包括：

- agent 注册
- 调度与触发
- 执行生命周期
- tool 调用协议
- LLM 调用协议
- proposal / human approval 协议
- run state 持久化
- trace / event / replay
- CLI 调试

非目标：

- 不把所有业务逻辑都迁入 runtime。
- 不让 runtime 直接依赖 Flutter、Riverpod、Drift、NaviWealth 数据模型。
- 不绑定某个 LLM provider。
- 不绑定某个数据库或队列系统。

## 2. 总体架构

推荐独立 repo：

```text
agent-runtime/
  crates/
    agent-core/
    agent-runtime/
    agent-tools/
    agent-llm/
    agent-store/
    agent-cli/
  bindings/
    dart/
    ts/
  examples/
    local-agent/
    backend-worker/
    flutter-host/
  schemas/
    agent-spec.schema.json
    run-request.schema.json
    run-result.schema.json
  docs/
    architecture.md
    protocol.md
    cli.md
```

模块关系：

```text
Business App
   |
   | implements ports
   v
Host Adapter
   |
   v
agent-runtime
   |
   +-- agent-core
   +-- agent-tools
   +-- agent-llm
   +-- agent-store
   +-- trace / replay
```

业务应用只需要实现 runtime 需要的端口，例如：

- 数据读取
- 数据写入
- 用户身份
- event sink
- tool handler
- proposal applier
- LLM provider
- notification service

## 3. 核心抽象

### 3.1 Agent

```rust
#[async_trait::async_trait]
pub trait Agent: Send + Sync {
    fn spec(&self) -> AgentSpec;

    async fn run(
        &self,
        ctx: AgentContext,
    ) -> Result<AgentRunResult, AgentError>;
}
```

`Agent` 是最小执行单元。它只关心：

- 自己是谁
- 什么时候应该运行
- 如何运行一次
- 返回什么结果

它不直接关心宿主应用如何存储、展示、同步。

### 3.2 AgentSpec

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSpec {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub version: String,
    pub schedule: ScheduleSpec,
    pub capabilities: Vec<String>,
    pub metadata: serde_json::Value,
}
```

`AgentSpec` 应该可以独立序列化，供 CLI、注册表、UI、后端服务读取。

### 3.3 AgentContext

```rust
pub struct AgentContext {
    pub run_id: RunId,
    pub now: DateTime<Utc>,
    pub user: Option<UserContext>,
    pub input: serde_json::Value,
    pub services: Arc<dyn AgentServices>,
    pub cancellation: CancellationToken,
    pub trace: Arc<dyn TraceSink>,
}
```

这里不放具体业务类型。业务能力通过 `AgentServices` 或 tool 端口注入。

### 3.4 AgentServices

```rust
#[async_trait::async_trait]
pub trait AgentServices: Send + Sync {
    async fn call_tool(
        &self,
        name: &str,
        input: serde_json::Value,
    ) -> Result<serde_json::Value, ToolError>;

    async fn emit_event(
        &self,
        event: AgentEvent,
    ) -> Result<(), AgentError>;

    async fn load_state(
        &self,
        key: &str,
    ) -> Result<Option<serde_json::Value>, AgentError>;

    async fn save_state(
        &self,
        key: &str,
        value: serde_json::Value,
    ) -> Result<(), AgentError>;
}
```

这样 runtime 不需要知道宿主 app 用的是数据库、HTTP、Riverpod、队列还是文件系统。

## 4. 调度模型

### 4.1 ScheduleSpec

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ScheduleSpec {
    Manual,
    Interval {
        every_seconds: u64,
        preferred_hour_local: Option<u8>,
        jitter_seconds: Option<u64>,
    },
    Cron {
        expression: String,
        timezone: String,
    },
}
```

初期可以只支持：

- manual
- interval
- daily preferred hour

后续再加 cron。

### 4.2 Scheduler

```rust
pub trait AgentScheduler {
    fn should_fire(
        &self,
        spec: &AgentSpec,
        now: DateTime<Utc>,
        last_run: Option<AgentRunRecord>,
    ) -> bool;
}
```

调度器只做判断，不执行 agent。执行由 `AgentRunner` 负责。

## 5. AgentRunner

```rust
pub struct AgentRunner {
    registry: Arc<dyn AgentRegistry>,
    run_store: Arc<dyn AgentRunStore>,
    lock_store: Arc<dyn AgentLockStore>,
    event_sink: Arc<dyn AgentEventSink>,
    scheduler: Arc<dyn AgentScheduler>,
    policy: ExecutionPolicy,
}
```

职责：

- run once
- tick
- 处理超时
- 处理 cancellation
- 捕获错误
- 写 run record
- 写 event
- 写 trace
- 控制并发
- 避免重复运行

### 5.1 run_once

```rust
impl AgentRunner {
    pub async fn run_once(
        &self,
        agent_id: &str,
        request: RunRequest,
    ) -> Result<AgentRunResult, AgentError>;
}
```

### 5.2 tick

```rust
impl AgentRunner {
    pub async fn tick(
        &self,
        request: TickRequest,
    ) -> Result<Vec<AgentRunResult>, AgentError>;
}
```

`tick` 遍历 registry 中的 agent，根据 schedule 和 last run 决定是否触发。

## 6. Registry 设计

```rust
#[async_trait::async_trait]
pub trait AgentRegistry: Send + Sync {
    async fn list_agents(&self) -> Result<Vec<AgentSpec>, AgentError>;

    async fn get_agent(
        &self,
        id: &str,
    ) -> Result<Option<Arc<dyn Agent>>, AgentError>;
}
```

支持多种 registry：

- in-memory registry
- file-based registry
- HTTP registry
- plugin registry
- app-provided registry

CLI 场景可以从文件加载：

```yaml
agents:
  - id: morning_briefing
    module: ./agents/morning_briefing.wasm
    schedule:
      type: interval
      every_seconds: 86400
      preferred_hour_local: 7
```

## 7. Tool 系统

### 7.1 ToolSpec

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
    pub output_schema: Option<serde_json::Value>,
    pub risk: ToolRisk,
}
```

### 7.2 ToolRegistry

```rust
#[async_trait::async_trait]
pub trait ToolRegistry: Send + Sync {
    async fn list_tools(&self) -> Result<Vec<ToolSpec>, ToolError>;

    async fn call(
        &self,
        name: &str,
        input: serde_json::Value,
        ctx: ToolContext,
    ) -> Result<serde_json::Value, ToolError>;
}
```

工具可以由宿主应用实现。runtime 只负责协议和调用流程。

## 8. LLM Provider 抽象

```rust
#[async_trait::async_trait]
pub trait LlmProvider: Send + Sync {
    async fn complete(
        &self,
        request: LlmRequest,
    ) -> Result<LlmResponse, LlmError>;

    async fn stream(
        &self,
        request: LlmRequest,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<LlmEvent, LlmError>> + Send>>, LlmError>;
}
```

Provider 实现：

- Anthropic
- OpenAI-compatible
- local model
- mock provider

runtime 不依赖具体 vendor。

## 9. Proposal / Human Approval

Agent 不应该直接修改高风险业务数据。建议使用 proposal 模型。

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalEnvelope {
    pub proposal_id: String,
    pub kind: String,
    pub summary: String,
    pub payload: serde_json::Value,
    pub risk: ProposalRisk,
    pub created_at: DateTime<Utc>,
}
```

应用侧负责：

- 展示 proposal
- 用户确认
- 用户拒绝
- apply
- undo

runtime 只定义协议。

## 10. Run State 与持久化

```rust
#[async_trait::async_trait]
pub trait AgentRunStore: Send + Sync {
    async fn last_run(
        &self,
        agent_id: &str,
        user_id: Option<&str>,
    ) -> Result<Option<AgentRunRecord>, StoreError>;

    async fn save_run(
        &self,
        record: AgentRunRecord,
    ) -> Result<(), StoreError>;
}
```

可选实现：

- SQLite
- Postgres
- file store
- in-memory
- host callback store

## 11. Trace 与 Replay

每次 run 输出标准 trace：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentTrace {
    pub run_id: String,
    pub agent_id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub spans: Vec<TraceSpan>,
    pub events: Vec<TraceEvent>,
    pub input: serde_json::Value,
    pub output: serde_json::Value,
}
```

CLI 支持：

```bash
agent run morning_briefing --input fixtures/today.json
agent tick --registry agents.yaml
agent replay traces/run_123.json
agent inspect run_123
agent tool call list_due_routines --input '{}'
```

Replay 是独立调试能力的核心。

## 12. CLI 设计

`agent-cli` 是一等公民。

CLI 同时支持两种使用方式：

- 非交互命令：适合 CI、脚本、自动化测试、后端 worker 调试。
- TUI 交互模式：适合像 Claude Code 一样本地运行、观察、暂停、批准 tool/proposal、replay trace。

### 12.1 非交互命令

核心命令：

```bash
agent init
agent list
agent run <agent-id>
agent tick
agent replay <trace-file>
agent inspect <run-id>
agent tool list
agent tool call <tool-name>
agent eval <eval-file>
```

示例：

```bash
agent run knowledge_inbox_triage \
  --registry ./agents.yaml \
  --input ./fixtures/inbox.json \
  --trace-out ./traces/inbox_triage.json
```

CLI 需要支持：

- mock tools
- fixture input
- env config
- LLM provider config
- trace 输出
- replay
- dry run
- approval simulation

### 12.2 TUI 交互模式

TUI 是 agent 独立调试体验的核心，而不是普通 CLI 的附属输出模式。

启动方式：

```bash
agent tui
agent tui --registry ./agents.yaml
agent tui --trace ./traces/inbox_triage.json
agent run knowledge_inbox_triage --input ./fixtures/inbox.json --interactive
```

TUI 需要支持：

- 选择 agent 并运行
- 输入或编辑 run request
- 选择 fixture
- 查看实时 token / tool / event / trace stream
- 暂停、继续、取消当前 run
- 单步执行 tool call
- 查看 tool input / output diff
- approve / deny 高风险 tool
- approve / deny proposal
- replay 历史 trace
- 比较两次 run 的 trace 差异
- 查看 agent state / last run / schedule 判断
- 切换 LLM provider 或 mock provider
- 导出 trace、run result、debug bundle

建议界面布局：

```text
+---------------------------------------------------------------+
| agent-runtime tui                         profile: local-dev   |
+----------------------+----------------------------------------+
| Agents               | Run                                    |
| > inbox_triage       | status: running                        |
|   execution_review   | run_id: 01HY...                        |
|   morning_briefing   | started: 2026-06-28 09:12:31Z          |
|                      |                                        |
| Fixtures             | Events                                 |
| > inbox-small.json   | [llm] round-1 started                  |
|   inbox-empty.json   | [tool] list_notes {...}                |
|                      | [tool] result 10 notes                 |
|                      | [proposal] 3 pending approvals         |
+----------------------+----------------------------------------+
| Inspector                                                     |
| tool: list_notes                                             |
| input:  {...}                                                |
| output: {...}                                                |
+---------------------------------------------------------------+
| [r] run  [s] step  [a] approve  [d] deny  [p] pause  [q] quit |
+---------------------------------------------------------------+
```

TUI 的内部实现不应该绕过 runtime。它应该通过同一套 `AgentRunner`、`ToolRegistry`、`TraceSink`、`AgentRunStore` 执行，只是换成交互式前端。

推荐 Rust crates：

- `ratatui`
- `crossterm`
- `tui-textarea`
- `tokio`
- `tracing`

### 12.3 调试包

CLI / TUI 都应该能导出 debug bundle，方便复现问题：

```text
debug-bundle/
  manifest.json
  agent_spec.json
  run_request.json
  run_result.json
  trace.json
  tool_calls.jsonl
  events.jsonl
  state_snapshot.json
  redactions.json
```

debug bundle 默认应支持敏感字段脱敏，由宿主应用提供 redaction policy。

## 13. Flutter / Dart 集成

Rust runtime 通过两种方式接入 Flutter：

### 方案 A：FRB / FFI

适合本地运行。

```text
Flutter
  -> Dart adapter
  -> flutter_rust_bridge
  -> agent-runtime-rs
```

Dart 侧实现：

- Riverpod service adapter
- local tool adapter
- memory/event adapter
- proposal adapter

### 方案 B：CLI / subprocess

适合开发调试，不适合移动端生产。

```text
Flutter dev tool
  -> agent CLI
  -> trace file
```

## 14. 后端集成

后端服务可以直接使用 Rust crate：

```rust
let runner = AgentRunner::new(...);
runner.tick(TickRequest { user_id: Some(user_id) }).await?;
```

也可以封装成 worker：

```text
cron / queue
  -> backend worker
  -> AgentRunner
  -> DB / tools / LLM
```

## 15. 推荐技术栈

Rust crates：

- `tokio`
- `async-trait`
- `serde`
- `serde_json`
- `schemars`
- `thiserror`
- `anyhow`
- `uuid`
- `chrono`
- `tracing`
- `tracing-subscriber`
- `clap`
- `sqlx` 可选
- `reqwest` 可选
- `tokio-util` cancellation

## 16. MVP 范围

第一阶段不要做太大。

MVP 只需要：

- `Agent`
- `AgentSpec`
- `AgentSchedule`
- `AgentRunner`
- in-memory registry
- file run store
- tool registry
- trace output
- CLI `run`
- CLI `replay`
- 一个示例 agent

暂不做：

- WASM plugin
- distributed scheduler
- complex cron
- multi-tenant auth
- UI
- cloud sync
- advanced eval

## 17. 迁移策略

从现有应用迁移时：

1. 先定义 Rust contract。
2. 用 Rust 实现 runner/scheduler/store/trace。
3. 在当前 Flutter app 中写 Dart adapter。
4. 先迁一个低风险 agent，例如 `execution_review`。
5. 让该 agent 可以同时通过 Flutter 和 CLI 跑。
6. 再迁 Knowledge / Health agent。
7. 最后抽出独立 repo。

## 18. 最终边界

Rust runtime 应该负责：

- agent 生命周期
- 调度
- 执行
- 状态
- trace
- tool/proposal/LLM 协议
- CLI 调试

业务应用负责：

- 业务数据模型
- 业务 repository
- UI 展示
- 用户确认
- 具体 tool 实现
- 具体 proposal apply
- 权限与用户身份

这个边界可以保证 runtime 足够通用，同时不会把业务复杂度塞进框架。

## 19. 跨语言 Schema 最佳实践

跨语言 schema 的核心原则是：schema 是 wire contract，不是业务模型、数据库模型，也不是某个语言的类型系统镜像。

对 Rust agent runtime，推荐采用：

- JSON Schema 作为核心跨语言契约。
- OpenAPI / AsyncAPI 作为服务接口契约。
- Protobuf 只作为高吞吐内部 RPC 的可选补充。

原因：

- Agent CLI、TUI、trace、fixture、debug bundle 都天然是文件化 JSON。
- LLM tool calling 本身也依赖 JSON Schema 风格的 tool input schema。
- Rust、TypeScript、Dart、Python 都能较好消费 JSON。
- Debug、replay、diff、人工审查时 JSON 比 Protobuf 更友好。

推荐目录：

```text
schemas/
  agent-spec.schema.json
  run-request.schema.json
  run-result.schema.json
  tool-spec.schema.json
  proposal-envelope.schema.json
  trace.schema.json

openapi/
  agent-runtime-api.yaml

fixtures/
  run-request.valid.json
  run-result.valid.json
  trace.valid.json
```

### 19.1 Contract-first

先写 schema，再生成或校验各语言类型。不要从 Rust struct、Dart class、TypeScript interface 反向散落生成多份“差不多”的类型。

推荐流程：

1. 修改 JSON Schema。
2. 更新 fixtures。
3. 运行兼容性测试。
4. 生成或更新 Rust / Dart / TypeScript DTO。
5. 更新 runtime 或 adapter 代码。

### 19.2 稳定 Envelope，业务 Payload 可扩展

顶层 envelope 必须稳定，业务 payload 保持扩展性。

示例：

```json
{
  "protocol_version": "agent.v1",
  "run_id": "01HY...",
  "agent_id": "knowledge_inbox_triage",
  "input": {},
  "metadata": {}
}
```

核心字段如 `run_id`、`agent_id`、`status`、`started_at` 必须稳定。`input`、`payload`、`metadata` 可以是 `object`，由具体 agent/tool 再声明二级 schema。

### 19.3 使用保守的跨语言类型

所有跨语言类型都应避免依赖某个语言特有表达。

推荐：

- ID：`string`
- 时间：RFC3339 UTC string，例如 `2026-06-28T09:12:31Z`
- decimal / money：`string`，不要用 float
- enum：`string`
- bytes：base64 string
- map：`object` + `additionalProperties`
- union：显式 tag，不用隐式 `oneOf` 猜测

示例：

```json
{
  "type": "object",
  "required": ["type"],
  "properties": {
    "type": { "const": "interval" },
    "every_seconds": { "type": "integer", "minimum": 1 },
    "preferred_hour_local": {
      "type": ["integer", "null"],
      "minimum": 0,
      "maximum": 23
    }
  }
}
```

### 19.4 Discriminated Union 必须有 Tag

Rust enum、TypeScript union、Dart sealed class 跨语言时最容易漂移。统一使用显式 tag。

示例：

```json
{
  "type": "object",
  "required": ["kind"],
  "properties": {
    "kind": { "enum": ["completed", "skipped", "failed"] }
  }
}
```

不要依赖字段形状推断类型。

### 19.5 版本策略

每个顶层消息都必须带版本：

```json
{
  "protocol_version": "agent.v1"
}
```

兼容规则：

- 只做 additive changes。
- 字段新增必须 optional 或有 default。
- 不删除字段，只 deprecate。
- enum 新增值时，客户端必须能处理 unknown。
- breaking change 升级到 `agent.v2`。

### 19.6 边界校验

schema 校验必须发生在系统边界。

必须 validate 的位置：

- CLI 读取 fixture
- TUI 编辑 request
- agent run request 入站
- tool input 入站
- tool output 出站
- trace/debug bundle 写出前
- replay 前

Rust 推荐使用：

- `serde`
- `schemars`
- `jsonschema`
- `serde_json`
- `thiserror`

生成类型适合 SDK，但 runtime 内部仍应保留边界校验。

### 19.7 LLM Tool Schema 使用 JSON Schema 子集

LLM provider 对 JSON Schema 支持并不完全一致。tool input schema 要保守。

建议：

- 少用复杂 `oneOf` / `anyOf`
- 避免深层递归
- 明确 `required`
- 明确 `description`
- enum 用 string
- object 层级控制在可读范围内

### 19.8 Golden Fixtures 与兼容性测试

每个 schema 至少提供 valid / invalid fixtures。

示例：

```text
fixtures/
  run-request.valid.json
  run-request.invalid.missing-agent-id.json
  run-result.completed.valid.json
  run-result.failed.valid.json
  trace.valid.json
```

CI 应该覆盖：

- schema validate
- Rust round-trip
- TypeScript round-trip
- Dart round-trip
- backward compatibility test

### 19.9 不暴露数据库 Schema

数据库表是持久化细节，不应该成为跨语言 wire schema。

跨语言 contract 应该是：

- `AgentSpec`
- `RunRequest`
- `RunResult`
- `ToolCall`
- `ToolResult`
- `ProposalEnvelope`
- `TraceEvent`

而不是 `agent_runs` 表结构。

### 19.10 三层 Schema 策略

推荐采用三层 schema：

```text
Core Wire Schema:
  JSON Schema
  用于 CLI/TUI/trace/fixture/tool/proposal

Service API Schema:
  OpenAPI / AsyncAPI
  用于后端 HTTP、worker、队列事件

Internal High-throughput Schema:
  Protobuf，可选
  只在确实需要低延迟/高吞吐 RPC 时引入
```

第一优先级是稳定 JSON Schema、fixtures 和 compatibility tests。它们决定 Rust、Dart、TypeScript、后端服务、CLI/TUI 是否能长期低成本协作。

## 20. Agent 插件与外部执行协议

Runtime 需要支持多种 agent 交付形态，但 MVP 不应该一开始就做复杂的动态插件系统。

推荐演进顺序：

1. 静态 Rust agent：agent 作为 Rust crate 直接链接进 runtime 或宿主服务。
2. 外部进程 agent：Rust runtime 负责编排，agent 可以用任意语言实现。
3. Remote agent：agent 通过 HTTP/gRPC 暴露 `run` 接口。
4. WASM plugin：后续再考虑，适合更强隔离和分发，但不适合 MVP。

### 20.1 静态 Rust Agent

静态 Rust agent 是最简单、最可靠的形态。

```rust
let registry = InMemoryAgentRegistry::new()
    .register(Arc::new(ExecutionReviewAgent::new()))
    .register(Arc::new(InboxTriageAgent::new()));
```

适用场景：

- 后端服务直接链接 runtime。
- Flutter native runtime 通过 FFI 调用。
- 业务 agent 与 runtime 同仓库开发。

### 20.2 外部进程 Agent

外部进程 agent 是跨语言复用的优先方案。Rust runtime 通过标准输入输出传递 JSON 消息。

运行协议：

```text
runtime -> agent process:
  RunRequest JSON via stdin

agent process -> runtime:
  RunResult JSON via stdout
  TraceEvent JSONL via stderr or side-channel file
```

示例：

```bash
agent run inbox_triage \
  --agent-command "node ./agents/inbox_triage.js" \
  --input ./fixtures/inbox.json
```

外部 agent manifest：

```yaml
id: knowledge_inbox_triage
name: Knowledge Inbox Triage
version: 0.1.0
runtime: process
command: node ./agents/inbox_triage.js
schema:
  input: ./schemas/inbox-triage-input.schema.json
  output: ./schemas/run-result.schema.json
schedule:
  type: interval
  every_seconds: 900
```

外部进程协议的好处：

- TypeScript、Python、Dart、Rust 都能实现 agent。
- CLI/TUI 调试体验一致。
- 不需要先实现 WASM ABI。
- 适合快速迁移现有业务逻辑。

### 20.3 Remote Agent

Remote agent 适合后端服务拆分。

```http
POST /agents/{agent_id}/run
Content-Type: application/json

{
  "protocol_version": "agent.v1",
  "run_id": "01HY...",
  "input": {}
}
```

Remote agent 必须返回标准 `RunResult`，并可选通过 streaming endpoint 输出 trace event。

### 20.4 Agent Manifest

无论 agent 是静态、进程、remote，建议都提供统一 manifest。

```yaml
id: execution_review
name: Execution Review
version: 0.1.0
runtime: rust
description: Weekly execution review agent.
schedule:
  type: interval
  every_seconds: 604800
capabilities:
  - execution.read
  - memory.write
schemas:
  input: ./schemas/execution-review-input.schema.json
  output: ./schemas/run-result.schema.json
metadata:
  owner: execution
```

Manifest 用于：

- CLI/TUI 展示 agent。
- registry 加载 agent。
- compatibility check。
- eval 绑定 agent version。
- trace 记录运行时元数据。

## 21. 状态、锁与幂等

Agent runtime 需要明确区分不同状态层级，避免把所有内容都塞进一个通用 KV。

### 21.1 状态类型

推荐状态分层：

```text
Run State:
  单次运行状态，包含 status、started_at、finished_at、error、output。

Agent State:
  agent 自己的长期状态，例如 cursor、last_processed_id、summary cache。

Scheduler State:
  last_run_at、next_due_at、failure_count、backoff_until。

Tool Call State:
  tool_call_id、input hash、output、duration、status。

Approval State:
  proposal/tool approval 的等待、确认、拒绝、过期、应用结果。

Replay State:
  replay 所需的 clock、fixture、tool output、LLM output、config snapshot。
```

### 21.2 Run Store

```rust
#[async_trait::async_trait]
pub trait AgentRunStore: Send + Sync {
    async fn create_run(&self, run: AgentRunRecord) -> Result<(), StoreError>;
    async fn update_run(&self, run: AgentRunRecord) -> Result<(), StoreError>;
    async fn get_run(&self, run_id: &str) -> Result<Option<AgentRunRecord>, StoreError>;
    async fn last_run(&self, agent_id: &str, scope: RunScope) -> Result<Option<AgentRunRecord>, StoreError>;
}
```

`RunScope` 用于区分全局 agent、用户级 agent、租户级 agent。

### 21.3 Agent State Store

```rust
#[async_trait::async_trait]
pub trait AgentStateStore: Send + Sync {
    async fn load(&self, agent_id: &str, key: &str) -> Result<Option<serde_json::Value>, StoreError>;
    async fn save(&self, agent_id: &str, key: &str, value: serde_json::Value) -> Result<(), StoreError>;
    async fn compare_and_swap(
        &self,
        agent_id: &str,
        key: &str,
        expected_version: StateVersion,
        value: serde_json::Value,
    ) -> Result<StateVersion, StoreError>;
}
```

`compare_and_swap` 是现代 runtime 的重要能力，可以避免并发 tick 覆盖状态。

### 21.4 锁与 Lease

后端部署会遇到多实例 tick、重复触发、worker 重试。需要 lease 型锁，而不是永久锁。

```rust
#[async_trait::async_trait]
pub trait AgentLockStore: Send + Sync {
    async fn acquire(
        &self,
        key: &str,
        owner: &str,
        ttl: Duration,
    ) -> Result<Option<RunLease>, StoreError>;

    async fn renew(&self, lease: &RunLease, ttl: Duration) -> Result<(), StoreError>;
    async fn release(&self, lease: RunLease) -> Result<(), StoreError>;
}
```

锁 key 推荐格式：

```text
agent:{agent_id}:scope:{scope_id}
```

### 21.5 幂等策略

每次 run 都应该有 idempotency key。

```text
idempotency_key = hash(agent_id + scope + trigger_kind + scheduled_for)
```

用途：

- 避免 cron 重复触发产生两次结果。
- 避免 worker retry 重复写 proposal。
- replay 时能对齐原始 run。

Tool call 也应该有 `tool_call_id` 和 input hash，支持记录输出、复用输出和 diff。

### 21.6 Recovery Policy

Runner 启动时应能处理历史 stuck run。

```text
running + lease expired -> abandoned
pending_approval + expired_at < now -> expired
failed + retryable -> scheduled_retry
```

MVP 可以先只实现 `running -> abandoned`，但数据模型应预留状态。

## 22. 错误分类与重试策略

错误不能只有字符串。需要结构化错误类型，供 runner、CLI、TUI、eval、observability 统一处理。

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentErrorKind {
    ValidationError,
    ToolError,
    LlmError,
    Timeout,
    Cancelled,
    ApprovalRequired,
    TransientExternalError,
    InternalError,
}
```

错误结构：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentErrorRecord {
    pub kind: AgentErrorKind,
    pub code: String,
    pub message: String,
    pub retryable: bool,
    pub details: serde_json::Value,
}
```

推荐重试策略：

```text
validation_error:
  不重试

tool_error:
  根据 tool error retryable 判断

llm_error:
  provider transient error 可重试

timeout:
  可按 agent policy 重试或 backoff

cancelled:
  不自动重试

approval_required:
  进入 pending approval

transient_external_error:
  exponential backoff + jitter

internal_error:
  默认不重试，除非明确标记 retryable
```

ExecutionPolicy 示例：

```rust
pub struct ExecutionPolicy {
    pub timeout: Duration,
    pub max_retries: u32,
    pub retry_backoff: BackoffPolicy,
    pub max_concurrent_runs: usize,
}
```

## 23. Approval 与 Proposal 生命周期

Proposal 是人机协作协议，不只是 agent 的输出字段。

推荐状态机：

```text
created
  -> pending_approval
  -> approved
  -> denied
  -> expired

approved
  -> applying
  -> applied
  -> apply_failed

applied
  -> undoing
  -> undone
  -> undo_failed
```

Proposal envelope：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalEnvelope {
    pub protocol_version: String,
    pub proposal_id: String,
    pub run_id: String,
    pub agent_id: String,
    pub kind: String,
    pub summary: String,
    pub payload: serde_json::Value,
    pub status: ProposalStatus,
    pub created_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}
```

Approval decision：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalDecision {
    pub proposal_id: String,
    pub decision: ApprovalDecisionKind,
    pub decided_at: DateTime<Utc>,
    pub comment: Option<String>,
}
```

TUI、Flutter UI、后端 API 都应该消费同一套 proposal 协议。

## 24. Trace、Replay 与 Debug Bundle 语义

Trace / replay 是独立调试能力的核心，必须定义清楚语义。

### 24.1 Trace 内容

每次 run 应记录：

- protocol version
- runtime version
- agent id / version
- run id
- input
- output
- started / finished time
- schedule decision
- tool calls
- LLM request / response summary
- prompt version
- model
- approval decisions
- state reads/writes
- errors

### 24.2 Replay 模式

推荐三种 replay：

```text
view replay:
  只查看 trace，不重新执行 agent。

deterministic replay:
  复用 trace 中记录的 clock、LLM output、tool output、approval decision。

live replay:
  使用相同 input 重新调用真实 tools / LLM。
```

CLI 示例：

```bash
agent replay traces/run_123.json --mode view
agent replay traces/run_123.json --mode deterministic
agent replay traces/run_123.json --mode live
```

### 24.3 Debug Bundle

Debug bundle 用于跨环境复现问题。

```text
debug-bundle/
  manifest.json
  agent_spec.json
  run_request.json
  run_result.json
  trace.json
  tool_calls.jsonl
  events.jsonl
  state_snapshot.json
  replay_config.json
```

`manifest.json` 应包含：

```json
{
  "bundle_version": "debug_bundle.v1",
  "runtime_version": "0.1.0",
  "agent_id": "knowledge_inbox_triage",
  "agent_version": "0.1.0",
  "created_at": "2026-06-28T09:12:31Z"
}
```

## 25. Prompt、模型与版本管理

Agent runtime 如果支持 LLM，需要把 prompt 和模型选择纳入版本化协议。

每次 run 记录：

```text
agent_version
runtime_version
protocol_version
prompt_version
tool_schema_version
model
provider
config_profile
```

Prompt 应拆成层级：

```text
runtime base prompt
  + agent prompt
  + active module prompt blocks
  + tool instructions
  + run context appendix
```

Prompt manifest：

```yaml
id: knowledge_inbox_triage_prompt
version: 0.3.0
model_family: anthropic
files:
  - ./prompts/base.md
  - ./prompts/inbox_triage.md
tool_schema_version: 0.2.0
```

规则：

- prompt 变更必须升级 `prompt_version`。
- deterministic replay 使用原 run 记录的 prompt。
- eval 绑定 prompt version 和 tool schema version。
- TUI 应展示本次 run 使用的 prompt composition。

## 26. Eval 与回归测试

独立 agent runtime 需要内建 eval 能力，否则 prompt、tool、agent 变更不可控。

Eval case：

```yaml
id: inbox_triage_basic
agent_id: knowledge_inbox_triage
agent_version: 0.1.0
input: ./fixtures/inbox-basic.json
mode: deterministic
expect:
  status: completed
  proposals:
    min_count: 1
  tool_calls:
    - name: list_notes
    - name: save_inbox_triage
```

CLI：

```bash
agent eval ./evals/inbox_triage.yaml
agent eval ./evals --update-golden
agent eval ./evals --profile ci
```

Eval 应支持：

- fixture-based input
- expected status
- expected proposal
- expected tool call sequence
- golden trace
- scoring hook
- deterministic LLM mock
- regression threshold
- update golden

CI 至少运行：

- schema validation
- fixture validation
- deterministic eval
- Rust unit tests
- contract compatibility tests

## 27. Observability

Trace 文件适合调试，但后端运行还需要 metrics 和 structured logs。

建议基于 Rust `tracing`，后续接 OpenTelemetry。

核心指标：

- run count
- success / skipped / failed count
- run latency
- schedule delay
- tool call count
- tool call latency
- LLM token usage
- retry count
- timeout count
- proposal created / approved / denied / applied count
- replay count

Span 层级：

```text
agent.run
  agent.schedule_decision
  agent.load_state
  agent.llm.round
  agent.tool.call
  agent.proposal.create
  agent.save_state
```

日志要求：

- 所有日志带 `run_id`、`agent_id`、`agent_version`。
- tool call 带 `tool_call_id`。
- proposal 操作带 `proposal_id`。
- 后端部署可导出 OpenTelemetry spans。

## 28. 部署拓扑

Runtime 应支持多种部署方式。

### 28.1 Embedded Library

后端服务直接链接 Rust crate。

```text
backend service
  -> agent-runtime crate
  -> app repositories / tools / LLM
```

适合生产后端。

### 28.2 CLI

本地调试、fixture run、replay、eval。

```text
developer terminal
  -> agent CLI / TUI
  -> file store / mock tools / local provider
```

### 28.3 Worker

由 cron 或 queue 触发。

```text
cron / queue
  -> worker
  -> AgentRunner.tick / run_once
```

### 28.4 Daemon

本机常驻 agent service，供多个应用或 CLI 连接。

```text
agentd
  -> local socket / HTTP
  -> AgentRunner
```

### 28.5 Mobile Embedded

Flutter 通过 FFI 调用 Rust runtime。

```text
Flutter
  -> Dart adapter
  -> FRB / FFI
  -> agent-runtime-rs
```

### 28.6 Remote Runtime

Agent runtime 作为独立 HTTP/gRPC 服务。

```text
app backend
  -> remote agent runtime
  -> tools / store / LLM
```

MVP 优先支持 embedded library 和 CLI/TUI。Worker 是后端自然延伸。Daemon、mobile embedded、remote runtime 后续再做。

## 29. 配置与 Profile

需要标准配置系统，支持本地、CI、生产等不同 profile。

推荐文件：

```text
agent-runtime.toml
agents.yaml
tools.yaml
profiles/
  local-dev.toml
  ci.toml
  production.toml
```

`agent-runtime.toml`：

```toml
[runtime]
profile = "local-dev"
trace_dir = "./traces"
store = "file"

[llm]
provider = "mock"
model = "mock-model"

[eval]
golden_dir = "./evals/golden"
```

`agents.yaml`：

```yaml
agents:
  - ./agents/execution_review.agent.yaml
  - ./agents/inbox_triage.agent.yaml
```

配置优先级：

```text
defaults
  < config file
  < profile file
  < environment variables
  < CLI flags
```

CLI 示例：

```bash
agent run inbox_triage --profile local-dev
agent eval ./evals --profile ci
agent tui --profile local-dev
```

## 30. 兼容性与治理

独立 runtime 一旦被多个应用使用，需要明确兼容性规则。

版本对象：

```text
runtime_version
protocol_version
schema_version
agent_version
prompt_version
tool_schema_version
manifest_version
```

治理规则：

- runtime 使用 semantic versioning。
- protocol 使用 `agent.v1` / `agent.v2`。
- schema 只做 additive change，breaking change 升 major。
- deprecated 字段至少保留一个 major version。
- fixtures 必须覆盖旧版本读取。
- 每次 release 生成 changelog。
- adapter 维护 compatibility matrix。

Compatibility matrix 示例：

```text
agent-runtime 0.1.x:
  protocol: agent.v1
  schema: 0.1.x
  dart adapter: 0.1.x
  ts sdk: 0.1.x
```

CI gate：

- schema compatibility check
- fixture validation
- Rust round-trip
- Dart DTO round-trip
- TypeScript DTO round-trip
- deterministic eval
- CLI smoke test

## 31. 借鉴 OpenCode / Codex 的设计

OpenCode 和 Codex 都不是单一 CLI，而是围绕 agent runtime 构建多入口、多协议、多调试形态。Rust agent runtime 应吸收其中经过验证的设计，但保持自身的业务无关边界。

### 31.1 Server-first Runtime

Runtime 不应该只暴露命令行。应提供 headless server，CLI、TUI、SDK、IDE、后端 worker 都通过同一套 runtime API 交互。

推荐命令：

```bash
agent serve
agent serve --stdio
agent serve --host 127.0.0.1 --port 8765
```

推荐传输：

```text
stdio JSONL:
  本地 CLI/TUI、外部进程集成、编辑器插件。

HTTP + OpenAPI:
  后端服务、SDK、Web UI、远程调试。

WebSocket:
  TUI/Web/IDE 实时订阅 run events、trace stream、approval prompts。

Unix socket:
  本机 daemon 模式。
```

架构关系：

```text
agent tui
agent run
agent sdk
agent web
backend worker
    |
    v
agent serve
    |
    v
AgentRunner / Registry / Store / ToolRegistry / TraceSink
```

TUI 和 CLI 不应该复制 runner 逻辑，只是 runtime server 的客户端。

### 31.2 API Schema 与 SDK 生成

Server API 必须 schema-first。

建议：

- HTTP API 使用 OpenAPI 3.1。
- 本地 stdio/WebSocket 使用 JSON-RPC 2.0 风格 envelope 或 JSONL command envelope。
- TypeScript / Dart SDK 从 OpenAPI 或 JSON Schema 生成。
- Rust server 侧仍使用 `serde` + 边界校验。

JSON-RPC 风格消息：

```json
{
  "jsonrpc": "2.0",
  "id": "req_01HY...",
  "method": "agent.run",
  "params": {
    "agent_id": "knowledge_inbox_triage",
    "input": {}
  }
}
```

事件流：

```json
{
  "type": "agent.run.event",
  "run_id": "run_01HY...",
  "event": {
    "kind": "tool_call_started",
    "tool_call_id": "tool_01HY..."
  }
}
```

### 31.3 TUI 作为 Server Client

TUI 应支持连接本地或远程 runtime：

```bash
agent tui
agent tui --connect http://127.0.0.1:8765
agent run inbox_triage --attach http://127.0.0.1:8765
```

好处：

- 复用常驻 runtime，减少外部 tool / MCP / indexer 冷启动。
- 多个客户端可以观察同一个 run。
- Web UI、TUI、IDE 看到同一份 session/trace。
- 后端 worker 的运行也可以被 attach 观察。

### 31.4 Session / Thread / Run / Step 模型

为了支持 fork、resume、replay 和多客户端调试，需要比单个 `run_id` 更完整的数据模型。

推荐层级：

```text
Session:
  一组相关任务或调试上下文。

Thread:
  Session 内的一条分支，可从历史 thread fork。

Run:
  一次 agent 执行。

Step:
  一次模型轮次、tool call、proposal、state update 或 approval。
```

基本命令：

```bash
agent session list
agent session show <session-id>
agent session fork <session-id>
agent run <agent-id> --session <session-id>
agent replay <run-id> --fork
```

Fork 应复制上下文引用和 replay config，但生成新的 thread id。这样可以用同一个问题对比不同 prompt、model、tool output 或 agent version。

### 31.5 Primary Agent 与 Subagent

借鉴 OpenCode 和 Codex 的 agent 分层，runtime 应区分 primary agent 与 subagent。

```yaml
id: code_search
name: Code Search
mode: subagent
hidden: true
model: fast
max_steps: 20
```

模式：

```text
primary:
  用户可直接选择和交互，保留主任务上下文。

subagent:
  专门做检索、验证、日志分析、总结等局部任务。

all:
  既可直接运行，也可被其他 agent 调用。
```

Subagent 的主要价值：

- 避免主上下文被长日志、检索结果、工具噪声污染。
- 让复杂任务拆成可观测的小任务。
- 让 TUI 展示子任务树。
- 让 eval 能分别评估主 agent 和子 agent。

Trace 中应记录：

```text
parent_run_id
subagent_run_id
subagent_id
input_summary
output_summary
```

### 31.6 Commands / Workflow 模板

借鉴 OpenCode slash commands，runtime 应支持文件化命令。命令不是 agent 本身，而是可复用 workflow prompt。

目录：

```text
.agent-runtime/
  commands/
    triage.md
    weekly-review.md
    repair.md
```

示例：

```markdown
---
description: Run inbox triage against a fixture
agent: knowledge_inbox_triage
model: fast
---

Run triage for $ARGUMENTS and summarize proposals.
```

CLI：

```bash
agent cmd triage ./fixtures/inbox-small.json
agent tui
# TUI 中显示 /triage
```

命令用途：

- 把常用 workflow 版本化。
- 让团队共享调试入口。
- 让一次成功的 replay 沉淀为可重复命令。
- 作为 eval case 的前置模板。

### 31.7 Hooks 与事件扩展点

不需要在 MVP 实现完整插件系统，但应先稳定 hook event schema。

推荐事件：

```text
SessionStart
SessionStop
RunStart
RunStop
BeforeAgentStep
AfterAgentStep
SubagentStart
SubagentStop
BeforeToolCall
AfterToolCall
BeforeProposalCreate
AfterProposalDecision
BeforeStateSave
AfterStateSave
BeforeCompact
AfterCompact
```

Hook 形态：

```text
native Rust hook:
  Rust trait，适合 embedded runtime。

process hook:
  通过 stdin/stdout JSON 调用外部脚本。

server hook:
  HTTP callback，适合远程集成。
```

Hook 输入输出必须 schema 化。即使暂不实现，也要让 trace event 和 server API 预留这些事件名，避免后续破坏协议。

### 31.8 MCP 与 LSP 作为能力来源

ToolRegistry 应支持多种 tool source。

```text
BuiltinToolSource:
  Rust 内置 tool。

ProcessToolSource:
  外部进程 tool。

McpToolSource:
  MCP server 暴露的 tools/resources/prompts。

HttpToolSource:
  HTTP tool endpoint。

LspSource:
  代码场景下的 symbol、diagnostics、references、definition 能力。
```

配置示例：

```yaml
tools:
  mcp:
    filesystem:
      command: npx
      args: ["-y", "@modelcontextprotocol/server-filesystem", "."]
  lsp:
    rust:
      command: rust-analyzer
      extensions: ["rs"]
```

工具启用应支持两级：

```text
global tools:
  runtime 可用的工具全集。

per-agent tools:
  某个 agent 实际可见的工具子集。
```

### 31.9 Record、Replay 与 Eval 互相转换

借鉴 Codex 的 record/replay 思路，一次成功的交互式运行应该可以沉淀成可复用资产。

转换路径：

```text
TUI run
  -> trace
  -> debug bundle
  -> deterministic replay
  -> eval case
  -> command template
```

CLI：

```bash
agent record --agent inbox_triage
agent replay traces/run_123.json --mode deterministic
agent eval create --from-run run_123 --out evals/inbox_triage_basic.yaml
agent cmd create --from-run run_123 --out .agent-runtime/commands/triage.md
```

这样 agent 改进循环可以变成：

```text
observe trace
  -> identify failure
  -> repair prompt/tool/agent
  -> rerun eval
  -> update golden when intentional
```

### 31.10 AGENTS.md / Project Instructions 分层

Codex 的项目说明文件模式值得借鉴。Runtime 可以支持项目级 instructions，并按照目录层级覆盖。

建议文件：

```text
AGENTS.md
.agent-runtime/instructions.md
features/knowledge/AGENTS.md
```

加载规则：

```text
global instructions
  < project AGENTS.md
  < nearest directory AGENTS.md
  < agent manifest instructions
  < command frontmatter/body
  < run request instructions
```

每次 run 应记录实际使用的 instruction stack，方便 replay 和 debug。

### 31.11 可借鉴设计的落地优先级

优先落地：

1. `agent serve` headless runtime。
2. TUI/CLI 作为 server client。
3. Session / Thread / Run / Step 数据模型。
4. Primary / Subagent 模式。
5. Markdown commands。
6. Hook event schema。
7. MCP tool source。
8. OpenAPI / JSON-RPC schema generation。
9. Replay -> Eval / Command 生成。
10. Project instructions 分层。

这些能力能让 runtime 从“可执行库”演进为“可独立运行、可调试、可集成、可长期演进的 agent platform”。
