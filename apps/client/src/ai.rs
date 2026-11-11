//! Device AI runtime embedding. The user owns the key: the `LlmProfile`
//! is stored on device and requests go straight to the provider.
//!
//! Tool surface (phase 4):
//! - Read-only tools for every enabled domain (finance is always on;
//!   knowledge/execution/health follow the settings switches).
//! - Write tools never touch the database. Their call returns a
//!   pending-write descriptor carrying an agent-core approval
//!   [`InteractionEnvelope`]; the chat screen renders a confirmation card
//!   and only an explicit user approval runs the actual write through the
//!   domain repositories (with outbox), via [`execute_pending_write`].

use std::str::FromStr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use agent_chat::{ChatTurnEventKind, ChatTurnRequest, ChatTurnRunner};
use agent_core::run::RunScope;
use agent_core::{
    AgentError, AgentStateStore, InteractionEnvelope, InteractionId, InteractionMode,
    InteractionResume, InteractionResumeKind, InteractionSubject, RunId, ToolContext, ToolError,
    ToolRegistry, ToolReplayPolicy, ToolRisk, ToolSpec,
};
use agent_llm::{
    AnthropicProvider, LlmEvent, LlmEventKind, LlmMessage, LlmProvider, LlmResponse, LlmRole,
    MockLlmProvider, OpenAiCompatibleProvider,
};
use agent_runtime::BasicAgentServices;
use agent_store::InMemoryStateStore;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const PROTOCOL_VERSION: &str = agent_core::PROTOCOL_VERSION;

/// User-owned on-device model profile.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LlmProfile {
    /// `anthropic` | `openai` | `mock`
    pub provider: String,
    /// API base URL (empty → provider default).
    pub base_url: String,
    pub model: String,
    pub api_key: String,
}

impl LlmProfile {
    pub fn is_complete(&self) -> bool {
        match self.provider.as_str() {
            "anthropic" | "openai" => !self.model.is_empty() && !self.api_key.is_empty(),
            "mock" => true,
            _ => false,
        }
    }
}

// ---- Read-only tools ----

pub const TOOL_ACCOUNT_BALANCES: &str = "finance_account_balances";
pub const TOOL_RECENT_ENTRIES: &str = "finance_recent_entries";
pub const TOOL_NOTE_SEARCH: &str = "knowledge_note_search";
pub const TOOL_OPEN_ACTIONS: &str = "execution_open_actions";
pub const TOOL_RECENT_METRICS: &str = "health_recent_metrics";

// ---- Write tools (pending confirmation, never executed in-call) ----

pub const TOOL_RECORD_EXPENSE: &str = "finance_record_expense";
pub const TOOL_CREATE_NOTE: &str = "knowledge_create_note";
pub const TOOL_ADD_ACTION: &str = "execution_add_action";

/// The domain a tool belongs to (`None` for unknown tools).
pub fn tool_domain(name: &str) -> Option<&'static str> {
    match name {
        TOOL_ACCOUNT_BALANCES | TOOL_RECENT_ENTRIES | TOOL_RECORD_EXPENSE => Some("finance"),
        TOOL_NOTE_SEARCH | TOOL_CREATE_NOTE => Some("knowledge"),
        TOOL_OPEN_ACTIONS | TOOL_ADD_ACTION => Some("execution"),
        TOOL_RECENT_METRICS => Some("health"),
        _ => None,
    }
}

fn spec(
    domain: &'static str,
    name: &str,
    description: &str,
    input_schema: Value,
    risk: ToolRisk,
) -> ToolSpec {
    let write = risk != ToolRisk::ReadOnly;
    ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
        input_schema,
        output_schema: None,
        risk,
        replay_policy: if write {
            // Writes must not be replayed blindly; the host re-runs them
            // only through an explicit user approval.
            ToolReplayPolicy::AtMostOnce
        } else {
            ToolReplayPolicy::SafeRetry
        },
        metadata: json!({
            "domain": domain,
            "write": write,
        }),
    }
}

/// The finance read-only tool specs (finance is always on).
pub fn finance_tool_specs() -> Vec<ToolSpec> {
    vec![
        spec(
            "finance",
            TOOL_ACCOUNT_BALANCES,
            "列出所有启用的账户及其当前余额（金额为十进制字符串）。",
            json!({
                "type": "object",
                "properties": {},
                "additionalProperties": false
            }),
            ToolRisk::ReadOnly,
        ),
        spec(
            "finance",
            TOOL_RECENT_ENTRIES,
            "按时间倒序返回最近的记账分录（账户名 + 金额），可用 limit 限制条数（默认 10，最大 50）。",
            json!({
                "type": "object",
                "properties": {
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50 }
                },
                "additionalProperties": false
            }),
            ToolRisk::ReadOnly,
        ),
    ]
}

/// The write tool specs. Each call only produces a pending write that the
/// user must approve in the UI before the host commits it.
pub fn write_tool_specs() -> Vec<ToolSpec> {
    vec![
        spec(
            "finance",
            TOOL_RECORD_EXPENSE,
            "记一笔支出。调用不会直接写入任何数据：系统会先在界面上弹出确认卡片，用户批准后才落库。参数：date（yyyy-mm-dd）、amount（正数十进制字符串）、category_key（支出分类键，如 dining）、from_account（付款账户 id 或名称）、payee?（对方）、note?（备注）。",
            json!({
                "type": "object",
                "properties": {
                    "date": { "type": "string", "description": "yyyy-mm-dd" },
                    "amount": { "type": "string", "description": "正数十进制字符串，如 12.50" },
                    "category_key": { "type": "string", "description": "支出分类键，如 dining/groceries/transport" },
                    "from_account": { "type": "string", "description": "付款账户 id 或名称" },
                    "payee": { "type": "string" },
                    "note": { "type": "string" }
                },
                "required": ["date", "amount", "category_key", "from_account"],
                "additionalProperties": false
            }),
            ToolRisk::High,
        ),
        spec(
            "knowledge",
            TOOL_CREATE_NOTE,
            "新建一篇笔记。调用不会直接写入任何数据：系统会先在界面上弹出确认卡片，用户批准后才落库。参数：title、content、source?（来源，如链接或书名）。",
            json!({
                "type": "object",
                "properties": {
                    "title": { "type": "string" },
                    "content": { "type": "string" },
                    "source": { "type": "string" }
                },
                "required": ["title", "content"],
                "additionalProperties": false
            }),
            ToolRisk::High,
        ),
        spec(
            "execution",
            TOOL_ADD_ACTION,
            "在指定计划下新增一个动作。调用不会直接写入任何数据：系统会先在界面上弹出确认卡片，用户批准后才落库。参数：plan（计划 id 或标题）、title、due?（yyyy-mm-dd）。",
            json!({
                "type": "object",
                "properties": {
                    "plan": { "type": "string", "description": "计划 id 或标题" },
                    "title": { "type": "string" },
                    "due": { "type": "string", "description": "yyyy-mm-dd，可选" }
                },
                "required": ["plan", "title"],
                "additionalProperties": false
            }),
            ToolRisk::High,
        ),
    ]
}

/// The read-only tool specs of the optional domains (only their specs are
/// listed here; finance reads live in [`finance_tool_specs`]).
fn optional_domain_read_specs() -> Vec<ToolSpec> {
    vec![
        spec(
            "knowledge",
            TOOL_NOTE_SEARCH,
            "按关键词搜索笔记（标题与内容，不区分大小写），返回标题与内容摘要。参数：query（必填）、limit（可选，默认 10，最大 50）。",
            json!({
                "type": "object",
                "properties": {
                    "query": { "type": "string" },
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50 }
                },
                "required": ["query"],
                "additionalProperties": false
            }),
            ToolRisk::ReadOnly,
        ),
        spec(
            "execution",
            TOOL_OPEN_ACTIONS,
            "列出每个计划下尚未完成的动作（进行中/受阻会标注）。无参数。",
            json!({
                "type": "object",
                "properties": {},
                "additionalProperties": false
            }),
            ToolRisk::ReadOnly,
        ),
        spec(
            "health",
            TOOL_RECENT_METRICS,
            "按时间倒序返回最近的健康指标（步数/睡眠/体重），可用 kind 过滤、limit 限制条数（默认 20，最大 50）。",
            json!({
                "type": "object",
                "properties": {
                    "kind": { "type": "string", "enum": ["steps", "sleep", "weight"] },
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50 }
                },
                "additionalProperties": false
            }),
            ToolRisk::ReadOnly,
        ),
    ]
}

/// The tool catalog for the given enabled domain keys: finance always on,
/// each optional domain only when its switch is on (writes follow the same
/// gating as reads).
pub fn tool_specs_for(enabled_domains: &[&str]) -> Vec<ToolSpec> {
    let mut specs = finance_tool_specs();
    specs.push(write_tool_specs()[0].clone());
    if enabled_domains.contains(&"knowledge") {
        specs.push(optional_domain_read_specs()[0].clone());
        specs.push(write_tool_specs()[1].clone());
    }
    if enabled_domains.contains(&"execution") {
        specs.push(optional_domain_read_specs()[1].clone());
        specs.push(write_tool_specs()[2].clone());
    }
    if enabled_domains.contains(&"health") {
        specs.push(optional_domain_read_specs()[2].clone());
    }
    specs
}

// ---- Pending writes ----

/// A write a model requested but the user has not approved yet. The
/// approval envelope follows agent-core semantics (identity, payload,
/// lifecycle); the host renders it and only commits on an explicit
/// approval.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PendingWrite {
    /// agent-core approval envelope (kind=Approval, resume=ChatTurn). The
    /// host tracks the decision state itself; the envelope carries
    /// identity and payload.
    pub envelope: InteractionEnvelope,
    pub tool_name: String,
    /// Owning domain key (`finance`/`knowledge`/`execution`).
    pub domain: String,
    /// The primary sync table the write would land in.
    pub table: String,
    /// Raw tool input.
    pub params: Value,
    /// Human-readable summary shown on the confirmation card.
    pub summary: String,
}

fn pending_write(
    tool_name: &str,
    domain: &str,
    table: &str,
    params: Value,
    summary: String,
) -> PendingWrite {
    let interaction_id = InteractionId::new_v7();
    let mut envelope = InteractionEnvelope::approval(
        "确认 AI 写入",
        summary.clone(),
        InteractionSubject {
            kind: "pending_write".to_owned(),
            id: interaction_id.0.clone(),
            metadata: json!({ "tool": tool_name, "domain": domain, "table": table }),
        },
        InteractionMode::OneTap,
    );
    envelope.payload = params.clone();
    envelope.resume = InteractionResume {
        kind: InteractionResumeKind::ChatTurn,
        token: None,
    };
    PendingWrite {
        envelope,
        tool_name: tool_name.to_owned(),
        domain: domain.to_owned(),
        table: table.to_owned(),
        params,
        summary,
    }
}

/// Extract the pending write from a write-tool call output (the chat pump
/// forwards it to the engine thread when the turn stream ends).
pub fn pending_write_from_output(output: &Value) -> Option<PendingWrite> {
    if output.get("pending_confirmation").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    serde_json::from_value(output.get("write").cloned().unwrap_or(Value::Null)).ok()
}

/// The write-tool output: a pending confirmation, never a side effect.
fn pending_output(write: &PendingWrite) -> Value {
    json!({
        "pending_confirmation": true,
        "write": write,
        "message": "已生成写入请求，等待用户在界面上确认；在用户批准前不会写入任何数据。确认结果将在下一轮对话中告知。",
    })
}

// ---- Parameter helpers ----

fn string_param(input: &Value, key: &str) -> Result<String, ToolError> {
    match input.get(key) {
        Some(Value::String(s)) if !s.trim().is_empty() => Ok(s.trim().to_owned()),
        _ => Err(ToolError::from_agent_error(AgentError::validation(
            format!("参数 {key} 必须为非空字符串"),
        ))),
    }
}

fn optional_string_param(input: &Value, key: &str) -> Result<Option<String>, ToolError> {
    match input.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if !s.trim().is_empty() => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(ToolError::from_agent_error(AgentError::validation(
            format!("参数 {key} 必须为字符串"),
        ))),
    }
}

fn limit_param(input: &Value, default: i64) -> Result<i64, ToolError> {
    match input.get("limit") {
        None | Some(Value::Null) => Ok(default),
        Some(value) => {
            let n = value.as_i64().ok_or_else(|| {
                ToolError::from_agent_error(AgentError::validation("limit 必须为整数"))
            })?;
            if !(1..=50).contains(&n) {
                return Err(ToolError::from_agent_error(AgentError::validation(
                    "limit 必须在 1 到 50 之间",
                )));
            }
            Ok(n)
        }
    }
}

fn parse_amount(text: &str) -> Result<Decimal, ToolError> {
    let amount = Decimal::from_str(text.trim()).map_err(|_| {
        ToolError::from_agent_error(AgentError::validation(
            "amount 必须为十进制字符串，如 12.50",
        ))
    })?;
    if amount <= Decimal::ZERO {
        return Err(ToolError::from_agent_error(AgentError::validation(
            "amount 必须为正数",
        )));
    }
    Ok(amount)
}

fn parse_date(text: &str) -> Result<i64, ToolError> {
    crate::ui::date_to_secs(text).ok_or_else(|| {
        ToolError::from_agent_error(AgentError::validation("日期格式应为 yyyy-mm-dd"))
    })
}

// ---- Domain tools ----

/// Domain tools the chat loop may call. Reads go through the same DB
/// worker as the UI; writes produce pending confirmations only.
pub struct DomainTools {
    services: Arc<crate::state::Services>,
}

impl DomainTools {
    pub fn new(services: Arc<crate::state::Services>) -> Self {
        Self { services }
    }

    /// The pure gate: is `name` callable given the enabled domains?
    fn gate(&self, name: &str) -> Result<&'static str, ToolError> {
        let Some(domain) = tool_domain(name) else {
            return Err(ToolError::policy_denied(
                format!(
                    "tool {name:?} is not registered; writes need user confirmation and are not executed by the model"
                ),
                json!({ "tool": name }),
            ));
        };
        // Finance is always on; the opt-in domains follow their switches.
        if domain != "finance" && !self.services.domain_enabled(domain) {
            return Err(ToolError::policy_denied(
                format!("领域 {domain} 未启用，工具不可用"),
                json!({ "tool": name, "domain": domain }),
            ));
        }
        Ok(domain)
    }

    async fn read_account_balances(&self) -> Result<Value, ToolError> {
        let lines = self.services.account_balance_lines().await.map_err(|e| {
            ToolError::from_agent_error(AgentError::internal(format!("balances read failed: {e}")))
        })?;
        Ok(json!({ "accounts": lines }))
    }

    async fn read_recent_entries(&self, input: &Value) -> Result<Value, ToolError> {
        let limit = limit_param(input, 10)?;
        let lines = self.services.recent_entry_lines(limit).await.map_err(|e| {
            ToolError::from_agent_error(AgentError::internal(format!("entries read failed: {e}")))
        })?;
        Ok(json!({ "entries": lines }))
    }

    async fn read_note_search(&self, input: &Value) -> Result<Value, ToolError> {
        let query = string_param(input, "query")?;
        let limit = limit_param(input, 10)?;
        let lines = self
            .services
            .note_search_lines(&query, limit)
            .await
            .map_err(|e| {
                ToolError::from_agent_error(AgentError::internal(format!(
                    "note search failed: {e}"
                )))
            })?;
        Ok(json!({ "notes": lines }))
    }

    async fn read_open_actions(&self) -> Result<Value, ToolError> {
        let lines = self.services.open_action_lines().await.map_err(|e| {
            ToolError::from_agent_error(AgentError::internal(format!("actions read failed: {e}")))
        })?;
        Ok(json!({ "plans": lines }))
    }

    async fn read_recent_metrics(&self, input: &Value) -> Result<Value, ToolError> {
        let limit = limit_param(input, 20)?;
        let kind = match input.get("kind") {
            None | Some(Value::Null) => None,
            Some(Value::String(kind)) => {
                let kind =
                    naviwealth_health::models::MetricKind::parse(kind.trim()).ok_or_else(|| {
                        ToolError::from_agent_error(AgentError::validation(
                            "kind 必须为 steps/sleep/weight",
                        ))
                    })?;
                Some(kind)
            }
            Some(_) => {
                return Err(ToolError::from_agent_error(AgentError::validation(
                    "kind 必须为字符串",
                )));
            }
        };
        let lines = self
            .services
            .recent_metric_lines(limit, kind)
            .await
            .map_err(|e| {
                ToolError::from_agent_error(AgentError::internal(format!(
                    "metrics read failed: {e}"
                )))
            })?;
        Ok(json!({ "metrics": lines }))
    }

    /// `finance_record_expense`: validate, describe, return a pending
    /// write. No database access beyond the account/category lookups.
    async fn request_expense(&self, input: &Value) -> Result<Value, ToolError> {
        let date_text = string_param(input, "date")?;
        let amount_text = string_param(input, "amount")?;
        let category_key = string_param(input, "category_key")?;
        let from_account = string_param(input, "from_account")?;
        let payee = optional_string_param(input, "payee")?;
        let note = optional_string_param(input, "note")?;
        parse_date(&date_text)?;
        let amount = parse_amount(&amount_text)?;

        let (expense_account_id, category_label) = self
            .services
            .expense_category_by_key(&category_key)
            .await
            .map_err(internal_tool_error)?
            .ok_or_else(|| {
                ToolError::from_agent_error(AgentError::validation(format!(
                    "支出分类不存在：{category_key}"
                )))
            })?;
        let account = self
            .services
            .account_by_id_or_name(&from_account)
            .await
            .map_err(internal_tool_error)?
            .ok_or_else(|| {
                ToolError::from_agent_error(AgentError::validation(format!(
                    "找不到付款账户：{from_account}"
                )))
            })?;

        let mut summary = format!(
            "记一笔支出：{} {}（{}，账户 {}，分类 {}）",
            amount, account.currency, date_text, account.name, category_label
        );
        if let Some(payee) = &payee {
            summary.push_str(&format!("，对方 {payee}"));
        }
        if let Some(note) = &note {
            summary.push_str(&format!("，备注 {note}"));
        }
        let write = pending_write(
            TOOL_RECORD_EXPENSE,
            "finance",
            "fin:journal_entries",
            input.clone(),
            summary,
        );
        let _ = expense_account_id; // re-resolved at execution time
        Ok(pending_output(&write))
    }

    /// `knowledge_create_note`.
    async fn request_note(&self, input: &Value) -> Result<Value, ToolError> {
        let title = string_param(input, "title")?;
        let content = string_param(input, "content")?;
        let source = optional_string_param(input, "source")?;
        let _ = &source; // carried via input.clone(); validated above
        let chars = content.chars().count();
        let summary = format!("新建笔记：《{title}》（内容 {chars} 字）");
        let write = pending_write(
            TOOL_CREATE_NOTE,
            "knowledge",
            "know:notes",
            input.clone(),
            summary,
        );
        Ok(pending_output(&write))
    }

    /// `execution_add_action`.
    async fn request_action(&self, input: &Value) -> Result<Value, ToolError> {
        let plan_value = string_param(input, "plan")?;
        let title = string_param(input, "title")?;
        let due_text = optional_string_param(input, "due")?;
        if let Some(due) = &due_text {
            parse_date(due)?;
        }
        let plan = self
            .services
            .plan_by_id_or_title(&plan_value)
            .await
            .map_err(internal_tool_error)?
            .ok_or_else(|| {
                ToolError::from_agent_error(AgentError::validation(format!(
                    "找不到计划：{plan_value}"
                )))
            })?;
        let mut summary = format!("在计划《{}》下新增动作：{title}", plan.title);
        if let Some(due) = &due_text {
            summary.push_str(&format!("（截止 {due}）"));
        }
        let write = pending_write(
            TOOL_ADD_ACTION,
            "execution",
            "exec:actions",
            input.clone(),
            summary,
        );
        Ok(pending_output(&write))
    }
}

fn internal_tool_error(e: String) -> ToolError {
    ToolError::from_agent_error(AgentError::internal(e))
}

#[async_trait::async_trait]
impl ToolRegistry for DomainTools {
    async fn list_tools(&self) -> Result<Vec<ToolSpec>, ToolError> {
        Ok(tool_specs_for(&self.services.enabled_domain_keys()))
    }

    async fn call(&self, name: &str, input: Value, _ctx: ToolContext) -> Result<Value, ToolError> {
        self.gate(name)?;
        match name {
            TOOL_ACCOUNT_BALANCES => self.read_account_balances().await,
            TOOL_RECENT_ENTRIES => self.read_recent_entries(&input).await,
            TOOL_NOTE_SEARCH => self.read_note_search(&input).await,
            TOOL_OPEN_ACTIONS => self.read_open_actions().await,
            TOOL_RECENT_METRICS => self.read_recent_metrics(&input).await,
            TOOL_RECORD_EXPENSE => self.request_expense(&input).await,
            TOOL_CREATE_NOTE => self.request_note(&input).await,
            TOOL_ADD_ACTION => self.request_action(&input).await,
            other => Err(ToolError::policy_denied(
                format!("tool {other:?} is not registered"),
                json!({ "tool": other }),
            )),
        }
    }
}

/// Execute an approved pending write through the domain repositories
/// (builder + repo, outbox committed in the same transaction). Returns a
/// human-readable result line for the next turn's system note.
pub async fn execute_pending_write(
    services: &Arc<crate::state::Services>,
    write: &PendingWrite,
) -> Result<String, String> {
    match write.tool_name.as_str() {
        TOOL_RECORD_EXPENSE => {
            let date_text = param_string(&write.params, "date")?;
            let amount =
                parse_amount(&param_string(&write.params, "amount")?).map_err(|e| e.to_string())?;
            let category_key = param_string(&write.params, "category_key")?;
            let from_account = param_string(&write.params, "from_account")?;
            let payee = opt_param(&write.params, "payee")?;
            let note = opt_param(&write.params, "note")?;
            let date_secs = crate::ui::date_to_secs(&date_text)
                .ok_or_else(|| "日期格式应为 yyyy-mm-dd".to_owned())?;
            let (expense_account_id, category_label) = services
                .expense_category_by_key(&category_key)
                .await?
                .ok_or_else(|| format!("支出分类已不存在：{category_key}"))?;
            let account = services
                .account_by_id_or_name(&from_account)
                .await?
                .ok_or_else(|| format!("付款账户已不存在：{from_account}"))?;
            let currency = account.currency.clone();
            let account_name = account.name.clone();
            services
                .create_expense(
                    date_secs,
                    amount,
                    expense_account_id,
                    account.id,
                    payee,
                    note,
                )
                .await?;
            Ok(format!(
                "已写入支出 {amount} {currency}（{category_label}，{account_name}）"
            ))
        }
        TOOL_CREATE_NOTE => {
            let title = param_string(&write.params, "title")?;
            let content = param_string(&write.params, "content")?;
            let source = opt_param(&write.params, "source")?;
            services.create_note(title.clone(), content, source).await?;
            Ok(format!("已创建笔记《{title}》"))
        }
        TOOL_ADD_ACTION => {
            let plan_value = param_string(&write.params, "plan")?;
            let title = param_string(&write.params, "title")?;
            let due_text = opt_param(&write.params, "due")?;
            let due = match &due_text {
                Some(text) => Some(
                    crate::ui::date_to_secs(text)
                        .ok_or_else(|| "日期格式应为 yyyy-mm-dd".to_owned())?,
                ),
                None => None,
            };
            let plan = services
                .plan_by_id_or_title(&plan_value)
                .await?
                .ok_or_else(|| format!("计划已不存在：{plan_value}"))?;
            services
                .create_action(plan.id.clone(), title.clone(), due)
                .await?;
            Ok(format!("已在计划《{}》添加动作：{title}", plan.title))
        }
        other => Err(format!("未知写工具：{other}")),
    }
}

/// String parameter for the execution path (errors as strings).
fn param_string(params: &Value, key: &str) -> Result<String, String> {
    match params.get(key) {
        Some(Value::String(s)) if !s.trim().is_empty() => Ok(s.trim().to_owned()),
        _ => Err(format!("参数 {key} 缺失或无效")),
    }
}

fn opt_param(params: &Value, key: &str) -> Result<Option<String>, String> {
    match params.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if !s.trim().is_empty() => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("参数 {key} 无效")),
    }
}

// ---- Mock provider with scripted tool calls (headless test harness) ----

/// A scripted write request encoded in the user text. The markers are a
/// headless-test harness only: the mock provider turns them into a real
/// tool call round so the confirmation loop is exercised end to end.
pub fn scripted_tool_call_for(text: &str) -> Option<(&'static str, Value)> {
    let text = text.trim();
    let (marker, rest) = [
        (TOOL_RECORD_EXPENSE, "记一笔："),
        (TOOL_CREATE_NOTE, "记笔记："),
        (TOOL_ADD_ACTION, "加动作："),
    ]
    .into_iter()
    .find_map(|(tool, marker)| text.strip_prefix(marker).map(|rest| (tool, rest)))?;
    let fields: Vec<String> = rest.split('|').map(|f| f.trim().to_owned()).collect();
    match marker {
        TOOL_RECORD_EXPENSE if fields.len() >= 3 => {
            let mut input = json!({
                "date": crate::ui::ymd(lifeos::ids::now_secs()),
                "amount": fields[0],
                "category_key": fields[1],
                "from_account": fields[2],
            });
            if let Some(payee) = fields.get(3).filter(|f| !f.is_empty()) {
                input["payee"] = json!(payee);
            }
            if let Some(note) = fields.get(4).filter(|f| !f.is_empty()) {
                input["note"] = json!(note);
            }
            Some((TOOL_RECORD_EXPENSE, input))
        }
        TOOL_CREATE_NOTE if fields.len() >= 2 => {
            let mut input = json!({ "title": fields[0], "content": fields[1] });
            if let Some(source) = fields.get(2).filter(|f| !f.is_empty()) {
                input["source"] = json!(source);
            }
            Some((TOOL_CREATE_NOTE, input))
        }
        TOOL_ADD_ACTION if fields.len() >= 2 => {
            let mut input = json!({ "plan": fields[0], "title": fields[1] });
            if let Some(due) = fields.get(2).filter(|f| !f.is_empty()) {
                input["due"] = json!(due);
            }
            Some((TOOL_ADD_ACTION, input))
        }
        _ => None,
    }
}

fn last_user_text(request: &agent_llm::LlmRequest) -> Option<String> {
    request.messages.iter().rev().find_map(|message| {
        if message.role == LlmRole::User {
            message.content.as_str().map(str::to_owned)
        } else {
            None
        }
    })
}

/// The client-owned mock provider: identical replies to
/// [`MockLlmProvider`] for plain turns, but the first turn whose user
/// message carries a scripted marker streams one tool call round first.
struct ScriptedMockProvider {
    inner: MockLlmProvider,
    tool_call_used: AtomicBool,
}

impl ScriptedMockProvider {
    fn new(model: &str) -> Self {
        Self {
            inner: MockLlmProvider::new(
                "mock",
                model,
                "已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。",
            ),
            tool_call_used: AtomicBool::new(false),
        }
    }
}

#[async_trait::async_trait]
impl LlmProvider for ScriptedMockProvider {
    async fn complete(
        &self,
        request: agent_llm::LlmRequest,
    ) -> Result<LlmResponse, agent_llm::LlmError> {
        self.inner.complete(request).await
    }

    async fn stream(
        &self,
        request: agent_llm::LlmRequest,
    ) -> Result<agent_llm::LlmEventStream, agent_llm::LlmError> {
        let scripted = (!self.tool_call_used.swap(true, Ordering::SeqCst))
            .then(|| last_user_text(&request).and_then(|text| scripted_tool_call_for(&text)))
            .flatten();
        if let Some((name, input)) = scripted {
            let model = if request.model.is_empty() {
                "mock-model".to_owned()
            } else {
                request.model.clone()
            };
            let response = LlmResponse {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "mock".to_owned(),
                model,
                content: String::new(),
                finish_reason: agent_llm::LlmFinishReason::ToolCall,
                object: None,
                usage: None,
                metadata: json!({ "mock": true }),
            };
            let events = vec![
                Ok(LlmEvent {
                    kind: LlmEventKind::Started,
                    content: None,
                    response: None,
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({}),
                }),
                Ok(LlmEvent {
                    kind: LlmEventKind::ToolCallEnd,
                    content: None,
                    response: None,
                    tool_call_id: Some("mock-tool-call-1".to_owned()),
                    tool_name: Some(name.to_owned()),
                    partial_input_json: None,
                    tool_input: Some(input),
                    metadata: json!({}),
                }),
                Ok(LlmEvent {
                    kind: LlmEventKind::Finished,
                    content: None,
                    response: Some(response),
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({}),
                }),
            ];
            return Ok(Box::pin(futures::stream::iter(events)));
        }
        self.inner.stream(request).await
    }
}

// ---- Runner and requests ----

fn agent_services(services: Arc<crate::state::Services>) -> Arc<BasicAgentServices> {
    Arc::new(BasicAgentServices::new(
        "naviwealth",
        RunId::new_v7(),
        None,
        RunScope::Global,
        Arc::new(DomainTools::new(services)),
        Arc::new(InMemoryStateStore::default()) as Arc<dyn AgentStateStore>,
    ))
}

fn provider(profile: &LlmProfile) -> Result<Arc<dyn LlmProvider>, String> {
    Ok(match profile.provider.as_str() {
        "anthropic" => {
            let base_url = if profile.base_url.is_empty() {
                "https://api.anthropic.com".to_owned()
            } else {
                profile.base_url.clone()
            };
            Arc::new(
                AnthropicProvider::new("anthropic", base_url, &profile.api_key, "2023-06-01")
                    .map_err(|e| e.to_string())?,
            )
        }
        "openai" => {
            let base_url = if profile.base_url.is_empty() {
                "https://api.openai.com/v1".to_owned()
            } else {
                profile.base_url.clone()
            };
            Arc::new(
                OpenAiCompatibleProvider::new("openai", base_url, &profile.api_key)
                    .map_err(|e| e.to_string())?,
            )
        }
        "mock" => Arc::new(ScriptedMockProvider::new(if profile.model.is_empty() {
            "mock-model"
        } else {
            profile.model.as_str()
        })),
        other => return Err(format!("unknown provider: {other}")),
    })
}

/// Build the turn runner for a profile over the app services (the tool
/// registry reads through the same DB worker as the UI).
pub fn runner(
    services: &Arc<crate::state::Services>,
    profile: &LlmProfile,
) -> Result<ChatTurnRunner, String> {
    Ok(ChatTurnRunner::new(
        provider(profile)?,
        agent_services(services.clone()),
    ))
}

// ---- Multi-turn session ----

/// One historical chat message (role + plain-text content).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChatTurnMessage {
    /// `user` | `assistant`
    pub role: String,
    pub text: String,
}

/// The persisted last session (restored on app start; cleared by 清空会话).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ChatSession {
    pub messages: Vec<ChatTurnMessage>,
    /// Epoch seconds of the last save.
    pub updated_at: i64,
}

pub const CHAT_SESSION_KEY: &str = "ai.chat_session";
/// Messages kept in the prompt and in the persisted session.
pub const CHAT_HISTORY_LIMIT: usize = 40;

pub fn parse_session(raw: &str) -> ChatSession {
    serde_json::from_str(raw).unwrap_or_default()
}

fn session_json(session: &ChatSession) -> String {
    serde_json::to_string(session).unwrap_or_default()
}

/// Persist the session (kept small: only the newest messages survive).
/// Runs on the tokio runtime; call through `Services::runtime`.
pub async fn save_session(services: &Arc<crate::state::Services>, messages: Vec<ChatTurnMessage>) {
    let mut trimmed = messages;
    if trimmed.len() > CHAT_HISTORY_LIMIT {
        let drop = trimmed.len() - CHAT_HISTORY_LIMIT;
        trimmed.drain(0..drop);
    }
    let session = ChatSession {
        messages: trimmed,
        updated_at: lifeos::ids::now_secs(),
    };
    let raw = session_json(&session);
    services.settings_set(CHAT_SESSION_KEY, &raw).await;
}

/// Load the persisted session (empty when absent or corrupt).
pub async fn load_session(services: &Arc<crate::state::Services>) -> ChatSession {
    let raw = services.settings_get(CHAT_SESSION_KEY).await;
    raw.as_deref().map(parse_session).unwrap_or_default()
}

/// A multi-turn request: the optional system note (write-confirmation
/// outcomes), the full history, then the new user message. The tool
/// catalog follows the current domain switches.
pub fn turn_request(
    profile: &LlmProfile,
    history: &[ChatTurnMessage],
    system_note: Option<String>,
    user_text: String,
    tools: Vec<ToolSpec>,
) -> ChatTurnRequest {
    let mut messages = Vec::new();
    if let Some(note) = system_note {
        messages.push(LlmMessage {
            role: LlmRole::System,
            content: json!(note),
            name: None,
            metadata: json!({}),
        });
    }
    for message in history {
        let role = match message.role.as_str() {
            "assistant" => LlmRole::Assistant,
            _ => LlmRole::User,
        };
        messages.push(LlmMessage {
            role,
            content: json!(message.text),
            name: None,
            metadata: json!({}),
        });
    }
    messages.push(LlmMessage {
        role: LlmRole::User,
        content: json!(user_text),
        name: None,
        metadata: json!({}),
    });
    ChatTurnRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        turn_id: None,
        surface: Some("naviwealth-client".to_owned()),
        mode: None,
        session_id: None,
        thread_id: None,
        agent_id: None,
        provider: profile.provider.clone(),
        model: profile.model.clone(),
        messages,
        temperature: None,
        max_output_tokens: None,
        tools,
        context_blocks: Vec::new(),
        metadata: json!({}),
        context_policy: Default::default(),
        max_tool_rounds: 4,
        tool_execution: Default::default(),
    }
}

/// Is this event a content delta?
pub fn delta_text(event: &agent_chat::ChatTurnEvent) -> Option<&str> {
    if event.kind == ChatTurnEventKind::Delta {
        event.content.as_deref()
    } else {
        None
    }
}

/// Error text from an Error-kind event, if any.
pub fn error_text(event: &agent_chat::ChatTurnEvent) -> Option<String> {
    if event.kind == ChatTurnEventKind::Error {
        Some(
            event
                .content
                .clone()
                .unwrap_or_else(|| "unknown error".to_owned()),
        )
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state;

    fn tool_ctx() -> ToolContext {
        ToolContext {
            run_id: RunId::new_v7(),
            agent_id: "test".to_owned(),
            scope: RunScope::Global,
            user: None,
            metadata: json!({}),
        }
    }

    /// The test-mode services (in-memory DB, mock-friendly). The process
    /// global initializes once; `enable_test_mode` must win that race, so
    /// every test calls it before `shared()`.
    fn test_services() -> Arc<state::Services> {
        state::enable_test_mode();
        state::Services::shared()
    }

    #[test]
    fn finance_read_specs_are_read_only_with_schemas() {
        let specs = finance_tool_specs();
        assert_eq!(specs.len(), 2);
        assert!(specs.iter().all(|s| s.risk == ToolRisk::ReadOnly));
        assert!(specs.iter().all(|s| s.input_schema.is_object()));
        assert!(
            specs.iter().any(|s| s.name == TOOL_ACCOUNT_BALANCES
                && s.replay_policy == ToolReplayPolicy::SafeRetry)
        );
        assert!(specs.iter().any(|s| s.name == TOOL_RECENT_ENTRIES));
    }

    #[test]
    fn write_specs_are_high_risk_and_not_replayable() {
        for spec in write_tool_specs() {
            assert_eq!(spec.risk, ToolRisk::High, "{}", spec.name);
            assert_eq!(spec.replay_policy, ToolReplayPolicy::AtMostOnce);
            assert_eq!(spec.metadata["write"], json!(true));
            assert!(spec.input_schema.is_object());
            assert!(spec.input_schema["required"].is_array());
        }
    }

    #[test]
    fn specs_follow_domain_switches() {
        // Finance alone: two reads + the finance write; no optional tools.
        let finance_only = tool_specs_for(&[]);
        let names: Vec<&str> = finance_only.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&TOOL_ACCOUNT_BALANCES));
        assert!(names.contains(&TOOL_RECORD_EXPENSE));
        assert!(!names.contains(&TOOL_NOTE_SEARCH));
        assert!(!names.contains(&TOOL_CREATE_NOTE));
        assert!(!names.contains(&TOOL_OPEN_ACTIONS));
        assert!(!names.contains(&TOOL_RECENT_METRICS));

        // Everything enabled: every tool appears.
        let all = tool_specs_for(&["knowledge", "execution", "health"]);
        let names: Vec<&str> = all.iter().map(|s| s.name.as_str()).collect();
        for tool in [
            TOOL_NOTE_SEARCH,
            TOOL_CREATE_NOTE,
            TOOL_OPEN_ACTIONS,
            TOOL_ADD_ACTION,
            TOOL_RECENT_METRICS,
        ] {
            assert!(names.contains(&tool), "missing {tool}");
        }

        // A single switch adds exactly that domain's tools.
        let knowledge = tool_specs_for(&["knowledge"]);
        let names: Vec<&str> = knowledge.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&TOOL_NOTE_SEARCH));
        assert!(names.contains(&TOOL_CREATE_NOTE));
        assert!(!names.contains(&TOOL_ADD_ACTION));
        assert!(!names.contains(&TOOL_RECENT_METRICS));
    }

    #[test]
    fn pending_write_envelope_is_a_valid_chat_turn_approval() {
        let write = pending_write(
            TOOL_CREATE_NOTE,
            "knowledge",
            "know:notes",
            json!({ "title": "t", "content": "c" }),
            "新建笔记：《t》".to_owned(),
        );
        assert_eq!(write.envelope.kind, agent_core::InteractionKind::Approval);
        assert_eq!(write.envelope.resume.kind, InteractionResumeKind::ChatTurn);
        assert_eq!(
            write.envelope.payload,
            json!({ "title": "t", "content": "c" })
        );
        assert!(write.envelope.validate().is_ok());

        // The output round-trips through the pump extractor.
        let output = pending_output(&write);
        let parsed = pending_write_from_output(&output).expect("pending write parsed");
        assert_eq!(parsed, write);
        assert!(pending_write_from_output(&json!({"accounts": []})).is_none());
    }

    #[tokio::test]
    async fn balances_tool_lists_created_account() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "工具测试现金",
            "CNY",
        );
        services
            .create_account(new_account, Some(Decimal::from_str("250.5").unwrap()))
            .await
            .expect("account created");

        let registry = DomainTools::new(services);
        let out = registry
            .call(TOOL_ACCOUNT_BALANCES, json!({}), tool_ctx())
            .await
            .expect("tool call succeeds");
        let accounts = out["accounts"].as_array().expect("accounts array");
        let hit = accounts
            .iter()
            .filter_map(|v| v.as_str())
            .find(|line| line.contains("工具测试现金"))
            .expect("created account listed");
        assert!(hit.contains("250.5 CNY"), "balance line: {hit}");
    }

    #[tokio::test]
    async fn recent_entries_tool_returns_written_entry() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "工具测试现金二",
            "CNY",
        );
        let account = services
            .create_account(new_account, Some(Decimal::from(100)))
            .await
            .expect("account created");
        let categories = services
            .expense_categories()
            .await
            .expect("categories seeded");
        let expense_account_id = categories.first().expect("a category exists").0.clone();
        services
            .create_expense(
                lifeos::ids::now_secs(),
                Decimal::from_str("12.5").unwrap(),
                expense_account_id,
                account.id.clone(),
                Some("工具测试".to_owned()),
                None,
            )
            .await
            .expect("expense written");

        let registry = DomainTools::new(services.clone());
        let out = registry
            .call(TOOL_RECENT_ENTRIES, json!({ "limit": 5 }), tool_ctx())
            .await
            .expect("tool call succeeds");
        let entries = out["entries"].as_array().expect("entries array");
        assert!(
            entries
                .iter()
                .filter_map(|v| v.as_str())
                .any(|line| line.contains("工具测试现金二") && line.contains("12.5")),
            "entry line lists account and amount: {entries:?}"
        );

        // Out-of-range and non-integer limits are validation errors.
        assert!(
            registry
                .call(TOOL_RECENT_ENTRIES, json!({ "limit": 0 }), tool_ctx())
                .await
                .is_err()
        );
        assert!(
            registry
                .call(TOOL_RECENT_ENTRIES, json!({ "limit": "x" }), tool_ctx())
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn disabled_domain_tool_is_policy_denied() {
        // knowledge defaults to off in test mode and no other lib test
        // flips it, so the note search must be denied.
        let services = test_services();
        let registry = DomainTools::new(services.clone());
        let err = registry
            .call(TOOL_NOTE_SEARCH, json!({ "query": "x" }), tool_ctx())
            .await
            .expect_err("disabled domain is denied");
        assert!(err.to_string().contains("未启用"));

        // Unknown tools stay denied as well.
        let err = registry
            .call("finance_transfer_money", json!({}), tool_ctx())
            .await
            .expect_err("unregistered tool is denied");
        assert!(err.to_string().contains("not registered"));
    }

    #[tokio::test]
    async fn note_search_reads_seeded_notes() {
        let services = test_services();
        services
            .create_note(
                "复式记账入门".to_owned(),
                "每笔分录必须借贷平衡".to_owned(),
                None,
            )
            .await
            .expect("note created");

        // The read path (Services; the tool wraps this same call) finds
        // the note; the miss returns nothing.
        let lines = services
            .note_search_lines("复式", 10)
            .await
            .expect("search works");
        assert!(
            lines.iter().any(|l| l.contains("复式记账入门")),
            "lines: {lines:?}"
        );
        let miss = services.note_search_lines("不存在的词", 10).await.unwrap();
        assert!(miss.is_empty());
    }

    #[tokio::test]
    async fn open_actions_and_metrics_read_tools() {
        let services = test_services();
        let plan = services
            .create_plan(
                "工具测试计划".to_owned(),
                naviwealth_execution::models::PlanKind::Project,
                naviwealth_execution::models::PlanPeriod::Week,
            )
            .await
            .expect("plan created");
        services
            .create_action(plan.id.clone(), "完成调研".to_owned(), None)
            .await
            .expect("action created");
        let lines = services.open_action_lines().await.expect("actions read");
        assert!(
            lines
                .iter()
                .any(|l| l.contains("工具测试计划") && l.contains("完成调研")),
            "lines: {lines:?}"
        );

        services
            .record_metric(
                naviwealth_health::models::MetricKind::Steps,
                Decimal::from(8000),
            )
            .await
            .expect("metric recorded");
        let metrics = services
            .recent_metric_lines(10, None)
            .await
            .expect("metrics read");
        assert!(
            metrics
                .iter()
                .any(|l| l.contains("步数") && l.contains("8000")),
            "metrics: {metrics:?}"
        );
        let by_kind = services
            .recent_metric_lines(10, Some(naviwealth_health::models::MetricKind::Steps))
            .await
            .unwrap();
        assert_eq!(by_kind.len(), metrics.len());
    }

    #[tokio::test]
    async fn expense_write_tool_returns_pending_without_side_effect() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "写入测试现金",
            "CNY",
        );
        let account = services
            .create_account(new_account, Some(Decimal::from(500)))
            .await
            .expect("account created");
        let before = services.recent_entries(50).await.unwrap().len();

        let registry = DomainTools::new(services.clone());
        let out = registry
            .call(
                TOOL_RECORD_EXPENSE,
                json!({
                    "date": "2026-02-01",
                    "amount": "25.5",
                    "category_key": "dining",
                    "from_account": "写入测试现金",
                    "payee": "面馆",
                }),
                tool_ctx(),
            )
            .await
            .expect("write tool returns pending");
        assert_eq!(out["pending_confirmation"], json!(true));
        let write = pending_write_from_output(&out).expect("pending write");
        assert_eq!(write.tool_name, TOOL_RECORD_EXPENSE);
        assert_eq!(write.domain, "finance");
        assert!(
            write.summary.contains("25.5") && write.summary.contains("面馆"),
            "summary: {}",
            write.summary
        );

        // Nothing landed: no ledger line for this test's account (the
        // count itself is racy across parallel tests sharing the DB).
        let lines = services.recent_entry_lines(50).await.unwrap();
        assert!(
            !lines
                .iter()
                .any(|l| l.contains("写入测试现金") && l.contains("25.5")),
            "no write without user confirmation, lines: {lines:?}"
        );
        let _ = account;
        let _ = before;
    }

    #[tokio::test]
    async fn expense_write_tool_validates_params() {
        let services = test_services();
        let registry = DomainTools::new(services);
        for bad in [
            json!({ "date": "2026/02/01", "amount": "1", "category_key": "dining", "from_account": "x" }),
            json!({ "date": "2026-02-01", "amount": "abc", "category_key": "dining", "from_account": "x" }),
            json!({ "date": "2026-02-01", "amount": "-3", "category_key": "dining", "from_account": "x" }),
            json!({ "date": "2026-02-01", "amount": "1", "category_key": "no_such", "from_account": "x" }),
            json!({ "date": "2026-02-01", "amount": "1", "category_key": "dining" }),
        ] {
            let err = registry
                .call(TOOL_RECORD_EXPENSE, bad, tool_ctx())
                .await
                .expect_err("invalid params are rejected");
            assert!(err.to_string().contains("validation"), "{err}");
        }
    }

    #[tokio::test]
    async fn approved_expense_pending_write_lands_in_ledger() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "批准测试现金",
            "CNY",
        );
        services
            .create_account(new_account, Some(Decimal::from(500)))
            .await
            .expect("account created");
        let registry = DomainTools::new(services.clone());
        let out = registry
            .call(
                TOOL_RECORD_EXPENSE,
                json!({
                    "date": "2026-02-01",
                    "amount": "25.5",
                    "category_key": "dining",
                    "from_account": "批准测试现金",
                }),
                tool_ctx(),
            )
            .await
            .expect("pending write");
        let write = pending_write_from_output(&out).expect("pending write");

        // The user approves: the host executes through the repositories.
        let result = execute_pending_write(&services, &write)
            .await
            .expect("approved write lands");
        assert!(result.contains("25.5"), "result: {result}");
        let lines = services.recent_entry_lines(10).await.expect("entries read");
        assert!(
            lines
                .iter()
                .any(|l| l.contains("批准测试现金") && l.contains("25.5")),
            "ledger lines: {lines:?}"
        );
    }

    #[tokio::test]
    async fn approved_note_and_action_writes_land() {
        let services = test_services();
        let registry = DomainTools::new(services.clone());

        // Note pending write (through the registry method; the domain
        // switch gate is covered by its own test).
        let note_input = json!({ "title": "批准笔记", "content": "内容正文", "source": "测试" });
        let out = registry
            .request_note(&note_input)
            .await
            .expect("pending note");
        let note_write = pending_write_from_output(&out).expect("pending write");
        let result = execute_pending_write(&services, &note_write)
            .await
            .expect("note lands");
        assert!(result.contains("批准笔记"), "result: {result}");
        let notes = services.notes(10).await.unwrap();
        assert!(
            notes
                .iter()
                .any(|n| n.title == "批准笔记" && n.source.as_deref() == Some("测试")),
            "notes: {notes:?}"
        );

        // Action pending write with an optional due date.
        let plan = services
            .create_plan(
                "批准计划".to_owned(),
                naviwealth_execution::models::PlanKind::Project,
                naviwealth_execution::models::PlanPeriod::Week,
            )
            .await
            .expect("plan created");
        let plan_id = plan.id.clone();
        let action_input = json!({
            "plan": "批准计划",
            "title": "发出周报",
            "due": "2026-03-01",
        });
        let out = registry
            .request_action(&action_input)
            .await
            .expect("pending action");
        let action_write = pending_write_from_output(&out).expect("pending write");
        assert!(action_write.summary.contains("2026-03-01"));
        execute_pending_write(&services, &action_write)
            .await
            .expect("action lands");
        let (_, actions) = services
            .plans_with_actions()
            .await
            .unwrap()
            .into_iter()
            .find(|(plan, _)| plan.id == plan_id)
            .expect("plan still there");
        assert!(
            actions
                .iter()
                .any(|a| a.title == "发出周报" && a.due.is_some()),
            "actions: {actions:?}"
        );
    }

    #[test]
    fn scripted_markers_parse_into_tool_calls() {
        let (name, input) =
            scripted_tool_call_for("记一笔：12.5|dining|测试现金|面馆|").expect("expense script");
        assert_eq!(name, TOOL_RECORD_EXPENSE);
        assert_eq!(input["amount"], json!("12.5"));
        assert_eq!(input["category_key"], json!("dining"));
        assert_eq!(input["from_account"], json!("测试现金"));
        assert_eq!(input["payee"], json!("面馆"));
        assert!(input["date"].as_str().expect("today date").contains('-'));

        let (name, input) = scripted_tool_call_for("记笔记：标题|正文|来源").expect("note script");
        assert_eq!(name, TOOL_CREATE_NOTE);
        assert_eq!(input["title"], json!("标题"));
        assert_eq!(input["source"], json!("来源"));

        let (name, input) = scripted_tool_call_for("加动作：计划A|第一步").expect("action script");
        assert_eq!(name, TOOL_ADD_ACTION);
        assert_eq!(input["plan"], json!("计划A"));
        assert!(input.get("due").is_none());

        assert!(scripted_tool_call_for("你好").is_none());
        assert!(scripted_tool_call_for("记一笔：12.5").is_none());
    }

    #[test]
    fn turn_request_carries_history_and_system_note() {
        let profile = mock_profile();
        let history = vec![
            ChatTurnMessage {
                role: "user".into(),
                text: "上一问".into(),
            },
            ChatTurnMessage {
                role: "assistant".into(),
                text: "上一答".into(),
            },
        ];
        let request = turn_request(
            &profile,
            &history,
            Some("写入结果：已批准".to_owned()),
            "新问题".to_owned(),
            tool_specs_for(&[]),
        );
        assert_eq!(request.messages.len(), 4);
        assert_eq!(request.messages[0].role, LlmRole::System);
        assert_eq!(request.messages[0].content, json!("写入结果：已批准"));
        assert_eq!(request.messages[1].content, json!("上一问"));
        assert_eq!(request.messages[2].role, LlmRole::Assistant);
        assert_eq!(request.messages[3].content, json!("新问题"));
        assert!(request.tools.iter().any(|s| s.name == TOOL_RECORD_EXPENSE));

        // Session round-trips through its JSON form.
        let session = ChatSession {
            messages: history.clone(),
            updated_at: 1234,
        };
        let raw = session_json(&session);
        assert_eq!(parse_session(&raw), session);
        assert_eq!(parse_session("not json"), ChatSession::default());
    }

    fn mock_profile() -> LlmProfile {
        LlmProfile {
            provider: "mock".to_owned(),
            base_url: String::new(),
            model: "mock-model".to_owned(),
            api_key: String::new(),
        }
    }
}
