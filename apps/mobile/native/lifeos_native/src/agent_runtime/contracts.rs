use super::*;

#[derive(Debug, Serialize)]
pub(super) struct CatalogSummary {
    pub(super) protocol_version: String,
    pub(super) catalog_version: String,
    pub(super) generated_at: String,
    pub(super) active_domains: Vec<String>,
    pub(super) agent_count: usize,
    pub(super) tool_count: usize,
    pub(super) proposal_kind_count: usize,
    pub(super) prompt_block_count: usize,
}

fn chat_turn_to_llm_request(request: &ChatTurnRequest) -> LlmRequest {
    let mut metadata = request.metadata.clone();
    if metadata.is_null() {
        metadata = json!({});
    }
    if let Some(object) = metadata.as_object_mut() {
        object.insert("chat_turn".to_owned(), Value::Bool(true));
        if let Some(turn_id) = &request.turn_id {
            object.insert("turn_id".to_owned(), Value::String(turn_id.clone()));
        }
        if let Some(surface) = &request.surface {
            object.insert("surface".to_owned(), Value::String(surface.clone()));
        }
        if let Some(agent_id) = &request.agent_id {
            object.insert("agent_id".to_owned(), Value::String(agent_id.clone()));
        }
        if let Some(mode) = &request.mode {
            object.insert("mode".to_owned(), Value::String(mode.clone()));
        }
        if let Some(session_id) = &request.session_id {
            object.insert("session_id".to_owned(), Value::String(session_id.clone()));
        }
        if let Some(thread_id) = &request.thread_id {
            object.insert("thread_id".to_owned(), Value::String(thread_id.clone()));
        }
    }
    LlmRequest {
        protocol_version: request.protocol_version.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        messages: request.messages.clone(),
        temperature: request.temperature,
        max_output_tokens: request.max_output_tokens,
        tools: request.tools.clone(),
        response_format: None,
        metadata,
    }
}

pub(super) fn normalize_run_request_contract(request: &mut RunRequest) -> Result<()> {
    let expected = protocol_version();
    if request.protocol_version != expected {
        anyhow::bail!(
            "run request protocol_version '{}' does not match runtime protocol_version '{expected}'",
            request.protocol_version
        );
    }
    if request.input.is_null() {
        request.input = json!({});
    } else if !request.input.is_object() {
        anyhow::bail!("run request input must be a JSON object");
    }
    if request.metadata.is_null() {
        request.metadata = json!({});
    } else if !request.metadata.is_object() {
        anyhow::bail!("run request metadata must be a JSON object");
    }
    if let Some(user) = &mut request.user {
        if user.user_id.trim().is_empty() {
            anyhow::bail!("run request user.user_id must be a non-empty string");
        }
        if user.metadata.is_null() {
            user.metadata = json!({});
        } else if !user.metadata.is_object() {
            anyhow::bail!("run request user.metadata must be a JSON object");
        }
    }
    Ok(())
}

pub(super) fn require_catalog_contract(catalog: &AgentRuntimeCatalog) -> Result<()> {
    let expected_protocol = protocol_version();
    if catalog.protocol_version != expected_protocol {
        anyhow::bail!(
            "catalog protocol_version '{}' does not match runtime protocol_version '{expected_protocol}'",
            catalog.protocol_version
        );
    }
    let expected_catalog = catalog_version();
    if catalog.catalog_version != expected_catalog {
        anyhow::bail!(
            "catalog catalog_version '{}' does not match runtime catalog_version '{expected_catalog}'",
            catalog.catalog_version
        );
    }
    for (index, active_domain) in catalog.active_domains.iter().enumerate() {
        if active_domain.trim().is_empty() {
            anyhow::bail!("catalog.active_domains[{index}] must be a non-empty string");
        }
    }
    let mut agent_ids = HashSet::new();
    let mut tool_names = HashSet::new();
    let mut proposal_kinds = HashSet::new();
    let mut prompt_block_indexes = HashSet::new();
    for (index, tool) in catalog.tools.iter().enumerate() {
        require_tool_spec_contract(tool, &format!("catalog.tools[{index}]"))?;
        if !tool_names.insert(tool.name.as_str()) {
            anyhow::bail!("catalog.tools[{index}].name '{}' is duplicated", tool.name);
        }
    }
    for (index, agent) in catalog.agents.iter().enumerate() {
        require_agent_spec_contract(agent, &format!("catalog.agents[{index}]"))?;
        if !agent_ids.insert(agent.id.as_str()) {
            anyhow::bail!("catalog.agents[{index}].id '{}' is duplicated", agent.id);
        }
    }
    for (index, proposal_kind) in catalog.proposal_kinds.iter().enumerate() {
        require_proposal_kind_contract(proposal_kind, &format!("catalog.proposal_kinds[{index}]"))?;
        if !tool_names.contains(proposal_kind.tool_name.as_str()) {
            anyhow::bail!(
                "catalog.proposal_kinds[{index}].tool_name '{}' does not match any catalog tool",
                proposal_kind.tool_name
            );
        }
        if !proposal_kinds.insert(proposal_kind.kind.as_str()) {
            anyhow::bail!(
                "catalog.proposal_kinds[{index}].kind '{}' is duplicated",
                proposal_kind.kind
            );
        }
    }
    for (index, prompt_block) in catalog.prompt_blocks.iter().enumerate() {
        if !prompt_block_indexes.insert(prompt_block.index) {
            anyhow::bail!(
                "catalog.prompt_blocks[{index}].index {} is duplicated",
                prompt_block.index
            );
        }
    }
    Ok(())
}

pub(super) fn normalize_llm_request_contract(request: &mut LlmRequest) -> Result<()> {
    let expected = protocol_version();
    if request.protocol_version != expected {
        anyhow::bail!(
            "LLM request protocol_version '{}' does not match runtime protocol_version '{expected}'",
            request.protocol_version
        );
    }
    if request.provider.trim().is_empty() {
        anyhow::bail!("LLM request provider must be a non-empty string");
    }
    if request.model.trim().is_empty() {
        anyhow::bail!("LLM request model must be a non-empty string");
    }
    if request.messages.is_empty() {
        anyhow::bail!("LLM request messages must contain at least one message");
    }
    if matches!(request.temperature, Some(value) if value < 0.0) {
        anyhow::bail!("LLM request temperature must be greater than or equal to zero");
    }
    if matches!(request.max_output_tokens, Some(0)) {
        anyhow::bail!("LLM request max_output_tokens must be greater than zero");
    }
    for (index, message) in request.messages.iter_mut().enumerate() {
        if message.metadata.is_null() {
            message.metadata = json!({});
        } else if !message.metadata.is_object() {
            anyhow::bail!("LLM request messages[{index}].metadata must be a JSON object");
        }
    }
    if request.metadata.is_null() {
        request.metadata = json!({});
    } else if !request.metadata.is_object() {
        anyhow::bail!("LLM request metadata must be a JSON object");
    }
    for (index, tool) in request.tools.iter().enumerate() {
        require_tool_spec_contract(tool, &format!("LLM request tools[{index}]"))?;
    }
    Ok(())
}

pub(super) fn normalize_chat_turn_request_contract(request: &mut ChatTurnRequest) -> Result<()> {
    require_optional_non_empty(&request.turn_id, "Chat turn turn_id")?;
    require_optional_non_empty(&request.surface, "Chat turn surface")?;
    require_optional_non_empty(&request.session_id, "Chat turn session_id")?;
    require_optional_non_empty(&request.thread_id, "Chat turn thread_id")?;
    require_optional_non_empty(&request.agent_id, "Chat turn agent_id")?;
    require_optional_non_empty(&request.mode, "Chat turn mode")?;
    let mut llm_request = chat_turn_to_llm_request(request);
    normalize_llm_request_contract(&mut llm_request)?;
    request.protocol_version = llm_request.protocol_version;
    request.provider = llm_request.provider;
    request.model = llm_request.model;
    request.messages = llm_request.messages;
    request.temperature = llm_request.temperature;
    request.max_output_tokens = llm_request.max_output_tokens;
    request.tools = llm_request.tools;
    request.metadata = llm_request.metadata;
    Ok(())
}

fn require_optional_non_empty(value: &Option<String>, label: &str) -> Result<()> {
    if matches!(value.as_deref(), Some(value) if value.trim().is_empty()) {
        anyhow::bail!("{label} must be a non-empty string when present");
    }
    Ok(())
}

pub(super) fn normalize_llm_response_contract(response: &mut LlmResponse) -> Result<()> {
    let expected = protocol_version();
    if response.protocol_version != expected {
        anyhow::bail!(
            "LLM response protocol_version '{}' does not match runtime protocol_version '{expected}'",
            response.protocol_version
        );
    }
    if response.provider.trim().is_empty() {
        anyhow::bail!("LLM response provider must be a non-empty string");
    }
    if response.model.trim().is_empty() {
        anyhow::bail!("LLM response model must be a non-empty string");
    }
    if response.metadata.is_null() {
        response.metadata = json!({});
    } else if !response.metadata.is_object() {
        anyhow::bail!("LLM response metadata must be a JSON object");
    }
    normalize_llm_response_tool_metadata(&mut response.metadata)?;
    if let Some(usage) = &response.usage {
        let expected_total = usage
            .input_tokens
            .checked_add(usage.output_tokens)
            .ok_or_else(|| anyhow::anyhow!("LLM response usage total_tokens overflowed"))?;
        if usage.total_tokens != expected_total {
            anyhow::bail!(
                "LLM response usage.total_tokens must equal input_tokens + output_tokens"
            );
        }
    }
    Ok(())
}

fn normalize_llm_response_tool_metadata(metadata: &mut Value) -> Result<()> {
    let object = metadata
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("LLM response metadata must be a JSON object"))?;
    for key in ["tool_plan", "tool_calls"] {
        if let Some(tool_plan) = object.get_mut(key) {
            let plan = tool_plan
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("LLM response metadata.{key} must be an array"))?;
            let normalized = plan
                .iter()
                .enumerate()
                .map(|(index, value)| {
                    let requested = parse_requested_tool_call(
                        value,
                        &format!("LLM response metadata.{key}[{index}]"),
                    )?;
                    Ok(serde_json::to_value(requested)?)
                })
                .collect::<Result<Vec<_>>>()?;
            *tool_plan = Value::Array(normalized);
        }
    }
    if let Some(tool_call) = object.get_mut("tool_call") {
        let requested = parse_requested_tool_call(tool_call, "LLM response metadata.tool_call")?;
        *tool_call = serde_json::to_value(requested)?;
    }
    Ok(())
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub(super) struct RequestedToolCall {
    pub(super) name: String,
    #[serde(default)]
    pub(super) input: Value,
}

pub(super) fn parse_requested_tool_call(value: &Value, label: &str) -> Result<RequestedToolCall> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("{label} must be an object"))?;
    let name = object
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("{label}.name is required"))?
        .to_owned();
    let input = match object.get("input") {
        Some(input) if input.is_object() => input.clone(),
        Some(_) => anyhow::bail!("{label}.input must be an object"),
        None => json!({}),
    };
    Ok(RequestedToolCall { name, input })
}

pub(super) fn require_tool_call_input_object(tool_call: &Value, label: &str) -> Result<()> {
    if matches!(tool_call.get("input"), Some(input) if !input.is_object()) {
        anyhow::bail!("{label}.input must be an object");
    }
    Ok(())
}

pub(super) fn normalize_llm_event_contract(event: &mut LlmEvent) -> Result<()> {
    if event.metadata.is_null() {
        event.metadata = json!({});
    } else if !event.metadata.is_object() {
        anyhow::bail!("LLM stream event metadata must be a JSON object");
    }
    if let Some(response) = &mut event.response {
        normalize_llm_response_contract(response)?;
    }
    Ok(())
}

pub(super) fn require_tool_spec_contract(tool: &ToolSpec, label: &str) -> Result<()> {
    if tool.name.trim().is_empty() {
        anyhow::bail!("{label}.name must be a non-empty string");
    }
    if tool.description.trim().is_empty() {
        anyhow::bail!("{label}.description must be a non-empty string");
    }
    if !tool.input_schema.is_object() {
        anyhow::bail!("{label}.input_schema must be an object");
    }
    if matches!(tool.output_schema.as_ref(), Some(value) if !value.is_object()) {
        anyhow::bail!("{label}.output_schema must be an object when present");
    }
    Ok(())
}

fn require_agent_spec_contract(agent: &AgentSpec, label: &str) -> Result<()> {
    let expected = protocol_version();
    if agent.protocol_version != expected {
        anyhow::bail!(
            "{label}.protocol_version '{}' does not match runtime protocol_version '{expected}'",
            agent.protocol_version
        );
    }
    if agent.id.trim().is_empty() {
        anyhow::bail!("{label}.id must be a non-empty string");
    }
    if agent.name.trim().is_empty() {
        anyhow::bail!("{label}.name must be a non-empty string");
    }
    if agent.version.trim().is_empty() {
        anyhow::bail!("{label}.version must be a non-empty string");
    }
    require_schedule_spec_contract(&agent.schedule, &format!("{label}.schedule"))?;
    Ok(())
}

fn require_schedule_spec_contract(schedule: &ScheduleSpec, label: &str) -> Result<()> {
    match schedule {
        ScheduleSpec::Manual => {}
        ScheduleSpec::Interval {
            every_seconds,
            preferred_hour_local,
            jitter_seconds: _,
        } => {
            if *every_seconds == 0 {
                anyhow::bail!("{label}.every_seconds must be greater than zero");
            }
            if matches!(preferred_hour_local, Some(hour) if *hour > 23) {
                anyhow::bail!("{label}.preferred_hour_local must be between 0 and 23");
            }
        }
        ScheduleSpec::Cron {
            expression,
            timezone,
        } => {
            if expression.trim().is_empty() {
                anyhow::bail!("{label}.expression must be a non-empty string");
            }
            if timezone.trim().is_empty() {
                anyhow::bail!("{label}.timezone must be a non-empty string");
            }
        }
    }
    Ok(())
}

fn require_proposal_kind_contract(proposal_kind: &ProposalKindSpec, label: &str) -> Result<()> {
    if proposal_kind.kind.trim().is_empty() {
        anyhow::bail!("{label}.kind must be a non-empty string");
    }
    if proposal_kind.tool_name.trim().is_empty() {
        anyhow::bail!("{label}.tool_name must be a non-empty string");
    }
    Ok(())
}

pub(super) fn validate_agent_runtime_step_trace_events(trace: &AgentTrace) -> Result<()> {
    for event in &trace.events {
        if event.kind != "agent_runtime_step" {
            continue;
        }
        let payload = event
            .payload
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("agent_runtime_step payload must be an object"))?;
        require_matching_string(payload, "run_id", trace.run_id.0.as_str())?;
        require_matching_string(payload, "agent_id", &trace.agent_id)?;
        require_step_status(payload, "status")?;
        require_non_negative_integer(payload, "step_index")?;
        require_nullable_non_empty_string(payload, "tool_name")?;
        let run_state = payload
            .get("run_state")
            .and_then(Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("agent_runtime_step payload.run_state is required"))?;
        require_step_status(run_state, "status")?;
        require_matching_string(
            run_state,
            "status",
            payload
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or_default(),
        )?;
        require_nullable_non_negative_integer(run_state, "step_index")?;
        require_matching_nullable_integer(run_state, "step_index", payload, "step_index")?;
        require_non_negative_integer(run_state, "remaining_tool_count")?;
        require_non_negative_integer(run_state, "tool_result_count")?;
        require_terminal_reason(run_state, "terminal_reason")?;
        require_terminal_reason_matches_status(run_state)?;
    }
    Ok(())
}

fn require_non_empty_string(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_str) {
        Some(value) if !value.is_empty() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be a non-empty string"),
    }
}

pub(super) fn require_matching_string(
    object: &Map<String, Value>,
    field: &str,
    expected: &str,
) -> Result<()> {
    require_non_empty_string(object, field)?;
    match object.get(field).and_then(Value::as_str) {
        Some(value) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match trace {field}"),
    }
}

fn require_non_negative_integer(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_u64) {
        Some(_) => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be a non-negative integer"),
    }
}

fn require_nullable_non_negative_integer(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(value) if value.as_u64().is_some() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be null or a non-negative integer"),
    }
}

fn require_nullable_non_empty_string(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(Value::String(value)) if !value.is_empty() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be null or a non-empty string"),
    }
}

pub(super) fn require_matching_nullable_string(
    object: &Map<String, Value>,
    field: &str,
    expected: &str,
) -> Result<()> {
    if matches!(object.get(field), Some(Value::Null)) {
        return Ok(());
    }
    require_nullable_non_empty_string(object, field)?;
    match object.get(field).and_then(Value::as_str) {
        Some(value) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match expected {field}"),
    }
}

fn require_matching_nullable_integer(
    object: &Map<String, Value>,
    field: &str,
    expected_object: &Map<String, Value>,
    expected_field: &str,
) -> Result<()> {
    if matches!(object.get(field), Some(Value::Null)) {
        return Ok(());
    }
    let value = object.get(field).and_then(Value::as_u64);
    let expected = expected_object.get(expected_field).and_then(Value::as_u64);
    match (value, expected) {
        (Some(value), Some(expected)) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match payload {expected_field}"),
    }
}

pub(super) fn require_step_status(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_str) {
        Some(
            "tool_call_requested"
            | "completed"
            | "failed"
            | "cancelled"
            | "policy_denied"
            | "closed_early"
            | "timed_out",
        ) => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} is not a supported status"),
    }
}

pub(super) fn require_terminal_reason(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(Value::String(value))
            if matches!(
                value.as_str(),
                "done" | "stream_error" | "user_cancel" | "policy_denied" | "closed_early"
            ) =>
        {
            Ok(())
        }
        _ => anyhow::bail!("agent_runtime_step {field} is not a supported terminal reason"),
    }
}

pub(super) fn require_terminal_reason_matches_status(object: &Map<String, Value>) -> Result<()> {
    let expected = match object.get("status").and_then(Value::as_str) {
        Some("tool_call_requested") => None,
        Some("completed") => Some("done"),
        Some("failed") => Some("stream_error"),
        Some("cancelled") => Some("user_cancel"),
        Some("policy_denied") => Some("policy_denied"),
        Some("closed_early" | "timed_out") => Some("closed_early"),
        _ => return Ok(()),
    };

    match (expected, object.get("terminal_reason")) {
        (None, Some(Value::Null)) => Ok(()),
        (Some(expected), Some(Value::String(value))) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step terminal_reason must match run_state.status"),
    }
}
