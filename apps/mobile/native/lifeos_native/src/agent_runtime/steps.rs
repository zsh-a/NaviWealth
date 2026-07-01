use super::contracts::*;
use super::*;

pub(super) fn agent_runtime_start_run_step(
    catalog_json: String,
    request_json: String,
    agent_id: String,
) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    contracts::require_catalog_contract(&catalog)?;
    let mut request: RunRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_run_request_contract(&mut request)?;
    let agent = catalog
        .agents
        .iter()
        .find(|agent| agent.id == agent_id)
        .ok_or_else(|| anyhow::anyhow!("agent '{agent_id}' is not present in the catalog"))?;
    let run_id = request.run_id.clone().unwrap_or_else(RunId::new_v7);

    let mut response = match parse_initial_tool_request(&request.input)? {
        Some(tool_request) => {
            let continuation = tool_request.continuation();
            build_tool_call_requested_step(
                &catalog,
                &agent.id,
                &agent.version,
                serde_json::to_value(&run_id)?,
                tool_request.first,
                continuation,
            )?
        }
        None => {
            json!({
                "protocol_version": protocol_version(),
                "run_id": run_id,
                "agent_id": agent.id,
                "agent_version": agent.version,
                "step_index": 0,
                "status": "completed",
                "output": request.input,
            })
        }
    };
    attach_runtime_metadata(&mut response);
    Ok(serde_json::to_string(&response)?)
}

pub(super) fn agent_runtime_continue_run_step(
    catalog_json: String,
    previous_step_json: String,
    tool_response_json: String,
    agent_id: String,
) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    contracts::require_catalog_contract(&catalog)?;
    let previous_step: Value = serde_json::from_str(&previous_step_json)?;
    let tool_response: Value = serde_json::from_str(&tool_response_json)?;
    let agent = catalog
        .agents
        .iter()
        .find(|agent| agent.id == agent_id)
        .ok_or_else(|| anyhow::anyhow!("agent '{agent_id}' is not present in the catalog"))?;
    if previous_step.get("status").and_then(Value::as_str) != Some("tool_call_requested") {
        anyhow::bail!("previous step status must be 'tool_call_requested'");
    }
    require_previous_step_protocol_version(&previous_step)?;
    require_previous_step_agent(&previous_step, &agent.id, &agent.version)?;
    let run_id = require_previous_step_run_id(&previous_step)?;
    let previous_step_index = require_previous_step_index(&previous_step)?;
    let tool_call = previous_step
        .get("tool_call")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("previous step is missing tool_call"))?;
    require_previous_tool_call_id(&tool_call)?;
    require_previous_tool_call_catalog_tool(&catalog, &agent.id, &tool_call)?;
    require_previous_step_runtime_metadata(&previous_step, &run_id, previous_step_index)?;
    require_tool_response_envelope(&tool_response)?;
    require_matching_tool_response_id(&tool_call, &tool_response)?;
    let previous_continuation =
        RuntimeContinuation::from_step(&previous_step, &catalog, &agent.id)?;
    if let Some(continuation) = &previous_continuation {
        continuation.require_next_step_index(previous_step_index)?;
    }
    let mut tool_results = previous_continuation
        .as_ref()
        .map(|continuation| continuation.tool_results.clone())
        .unwrap_or_default();
    let tool_terminal_status = tool_response_terminal_status(&tool_response);
    if tool_terminal_status != Some("closed_early") {
        tool_results.push(ToolResultRecord::new(
            tool_call.clone(),
            tool_response.clone(),
        ));
    }

    let next_step_index = previous_step_index + 1;

    let mut response = match tool_terminal_status {
        Some(status) => {
            let error = tool_response_error_payload(&tool_response).unwrap_or(Value::Null);
            let tool_results = ToolResultRecord::to_values(&tool_results);
            json!({
            "protocol_version": protocol_version(),
            "run_id": run_id,
            "agent_id": agent.id,
            "agent_version": agent.version,
            "step_index": next_step_index,
            "status": status,
            "tool_call": tool_call,
            "tool_response": tool_response,
            "tool_results": tool_results,
            "error": error,
            })
        }
        None => {
            match next_tool_request_from_continuation(previous_continuation, tool_results.clone())?
            {
                Some(next) => {
                    let continuation = next.continuation();
                    build_tool_call_requested_step(
                        &catalog,
                        &agent.id,
                        &agent.version,
                        run_id,
                        next.first,
                        continuation,
                    )?
                }
                None => {
                    let tool_result_count = tool_results.len();
                    let tool_results = ToolResultRecord::to_values(&tool_results);
                    json!({
                    "protocol_version": protocol_version(),
                    "run_id": run_id,
                    "agent_id": agent.id,
                    "agent_version": agent.version,
                    "step_index": next_step_index,
                    "status": "completed",
                    "output": {
                        "mode": if tool_result_count > 1 {
                            "frb_tool_loop"
                        } else {
                            "frb_tool_step"
                        },
                        "tool_call": tool_call,
                        "tool_result": tool_response.get("result").cloned().unwrap_or(Value::Null),
                        "tool_response": tool_response,
                        "tool_results": tool_results,
                    }
                    })
                }
            }
        }
    };
    attach_runtime_metadata(&mut response);
    Ok(serde_json::to_string(&response)?)
}

fn require_previous_step_agent(
    previous_step: &Value,
    agent_id: &str,
    agent_version: &str,
) -> Result<()> {
    let previous_agent_id = previous_step
        .get("agent_id")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("previous step is missing agent_id"))?;
    if previous_agent_id != agent_id {
        anyhow::bail!(
            "previous step agent_id '{previous_agent_id}' does not match requested agent '{agent_id}'"
        );
    }
    let previous_agent_version = previous_step
        .get("agent_version")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step agent_version must be a non-empty string"))?;
    if previous_agent_version != agent_version {
        anyhow::bail!(
            "previous step agent_version '{previous_agent_version}' does not match catalog agent version '{agent_version}'"
        );
    }
    Ok(())
}

fn require_previous_step_protocol_version(previous_step: &Value) -> Result<()> {
    let previous_protocol_version = previous_step
        .get("protocol_version")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            anyhow::anyhow!("previous step protocol_version must be a non-empty string")
        })?;
    let expected = protocol_version();
    if previous_protocol_version != expected {
        anyhow::bail!(
            "previous step protocol_version '{previous_protocol_version}' does not match runtime protocol_version '{expected}'"
        );
    }
    Ok(())
}

fn require_previous_step_run_id(previous_step: &Value) -> Result<Value> {
    let run_id = previous_step
        .get("run_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step run_id must be a non-empty string"))?;
    Ok(Value::String(run_id.to_owned()))
}

fn require_previous_step_index(previous_step: &Value) -> Result<u64> {
    previous_step
        .get("step_index")
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow::anyhow!("previous step_index must be a non-negative integer"))
}

fn require_previous_tool_call_catalog_tool(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    tool_call: &Value,
) -> Result<()> {
    let name = tool_call
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step tool_call.name is required"))?;
    if catalog.tools.iter().any(|tool| tool.name == name) {
        require_tool_call_input_object(tool_call, "previous step tool_call")?;
        return Ok(());
    }
    anyhow::bail!("tool '{name}' requested by agent '{agent_id}' is not present in the catalog");
}

fn require_previous_tool_call_id(tool_call: &Value) -> Result<()> {
    tool_call
        .get("tool_call_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            anyhow::anyhow!("previous step tool_call.tool_call_id must be a non-empty string")
        })?;
    Ok(())
}

fn require_previous_step_runtime_metadata(
    previous_step: &Value,
    run_id: &Value,
    step_index: u64,
) -> Result<()> {
    if let Some(run_state) = previous_step.get("run_state") {
        require_previous_step_run_state(previous_step, run_state, step_index)
            .map_err(|error| anyhow::anyhow!("previous step run_state: {error}"))?;
    }
    if let Some(trace_event) = previous_step.get("trace_event") {
        require_previous_step_trace_event(previous_step, trace_event, run_id, step_index)
            .map_err(|error| anyhow::anyhow!("previous step trace_event: {error}"))?;
    }
    Ok(())
}

fn require_previous_step_run_state(
    previous_step: &Value,
    run_state: &Value,
    step_index: u64,
) -> Result<()> {
    let run_state = run_state
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("previous step run_state must be an object"))?;
    require_step_status(run_state, "status")?;
    require_matching_string(
        run_state,
        "status",
        previous_step
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    match run_state.get("step_index").and_then(Value::as_u64) {
        Some(value) if value == step_index => {}
        _ => anyhow::bail!("previous step run_state.step_index must match step_index"),
    }
    let continuation_counts = RuntimeContinuation::counts_from_step(previous_step);
    let expected_remaining_tool_count = continuation_counts.remaining_tool_count as u64;
    match run_state
        .get("remaining_tool_count")
        .and_then(Value::as_u64)
    {
        Some(value) if value == expected_remaining_tool_count => {}
        _ => anyhow::bail!(
            "previous step run_state.remaining_tool_count must match continuation.tool_plan"
        ),
    }
    let expected_tool_result_count = continuation_counts.tool_result_count as u64;
    match run_state.get("tool_result_count").and_then(Value::as_u64) {
        Some(value) if value == expected_tool_result_count => {}
        _ => anyhow::bail!(
            "previous step run_state.tool_result_count must match continuation.tool_results"
        ),
    }
    require_terminal_reason(run_state, "terminal_reason")?;
    require_terminal_reason_matches_status(run_state)?;
    Ok(())
}

fn require_previous_step_trace_event(
    previous_step: &Value,
    trace_event: &Value,
    run_id: &Value,
    step_index: u64,
) -> Result<()> {
    let trace_event = trace_event
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("previous step trace_event must be an object"))?;
    require_matching_string(trace_event, "kind", "agent_runtime_step")?;
    require_matching_string(trace_event, "run_id", run_id.as_str().unwrap_or_default())?;
    require_matching_string(
        trace_event,
        "agent_id",
        previous_step
            .get("agent_id")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    require_matching_string(
        trace_event,
        "status",
        previous_step
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    match trace_event.get("step_index").and_then(Value::as_u64) {
        Some(value) if value == step_index => {}
        _ => anyhow::bail!("previous step trace_event.step_index must match step_index"),
    }
    if let Some(run_state) = previous_step.get("run_state") {
        match trace_event.get("run_state") {
            Some(value) if value == run_state => {}
            _ => anyhow::bail!("previous step trace_event.run_state must match run_state"),
        }
    }
    let expected_tool_name = previous_step
        .get("tool_call")
        .and_then(|tool_call| tool_call.get("name"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    require_matching_nullable_string(trace_event, "tool_name", expected_tool_name)?;
    Ok(())
}

fn require_matching_tool_response_id(tool_call: &Value, tool_response: &Value) -> Result<()> {
    let Some(expected_id) = tool_call.get("tool_call_id").and_then(Value::as_str) else {
        return Ok(());
    };
    let Some(response_id) = tool_response.get("id") else {
        return Ok(());
    };
    match response_id.as_str() {
        Some(value) if value == expected_id => Ok(()),
        Some(value) => anyhow::bail!(
            "tool response id '{value}' does not match requested tool_call_id '{expected_id}'"
        ),
        None => anyhow::bail!("tool response id must be a string when present"),
    }
}

fn require_tool_response_envelope(tool_response: &Value) -> Result<()> {
    let Some(object) = tool_response.as_object() else {
        anyhow::bail!("tool response must be an object");
    };
    if let Some(jsonrpc) = object.get("jsonrpc") {
        match jsonrpc.as_str() {
            Some("2.0") => {}
            Some(_) => anyhow::bail!("tool response jsonrpc must be '2.0'"),
            None => anyhow::bail!("tool response jsonrpc must be a string"),
        }
        if !object.contains_key("id") {
            anyhow::bail!("tool response id is required when jsonrpc is present");
        }
        match (object.contains_key("result"), object.contains_key("error")) {
            (true, false) | (false, true) => {}
            (true, true) => anyhow::bail!("tool response cannot contain both result and error"),
            (false, false) => anyhow::bail!("tool response must contain result or error"),
        }
        if let Some(error) = object.get("error") {
            let error = error
                .as_object()
                .ok_or_else(|| anyhow::anyhow!("tool response error must be an object"))?;
            if error.get("code").and_then(Value::as_i64).is_none() {
                anyhow::bail!("tool response error.code must be an integer");
            }
            if error.get("message").and_then(Value::as_str).is_none() {
                anyhow::bail!("tool response error.message must be a string");
            }
        }
    }
    if !object.contains_key("jsonrpc")
        && object.contains_key("result")
        && object.contains_key("error")
    {
        anyhow::bail!("tool response cannot contain both result and error");
    }
    Ok(())
}

fn tool_response_terminal_status(tool_response: &Value) -> Option<&'static str> {
    let code = tool_response_error_code(tool_response);
    match code.as_deref() {
        Some("tool_call_budget_exhausted") => Some("closed_early"),
        Some("policy_denied") => Some("policy_denied"),
        Some("user_cancel" | "user_cancelled" | "cancelled") => Some("cancelled"),
        Some("tool_timeout" | "timeout" | "timed_out") => Some("timed_out"),
        Some(_) => Some("failed"),
        None if tool_response_error_payload(tool_response).is_some() => Some("failed"),
        None => None,
    }
}

fn tool_response_error_code(tool_response: &Value) -> Option<String> {
    tool_response
        .get("error")
        .and_then(|error| error.get("code"))
        .and_then(Value::as_str)
        .or_else(|| tool_response.get("code").and_then(Value::as_str))
        .or_else(|| {
            tool_response
                .get("result")
                .and_then(|result| result.get("error"))
                .and_then(|error| error.get("code"))
                .and_then(Value::as_str)
        })
        .or_else(|| {
            tool_response
                .get("result")
                .and_then(|result| result.get("code"))
                .and_then(Value::as_str)
        })
        .map(str::to_owned)
}

fn tool_response_error_payload(tool_response: &Value) -> Option<Value> {
    if let Some(error) = tool_response.get("error") {
        return Some(error.clone());
    }
    let result = tool_response.get("result")?;
    if let Some(error) = result.get("error") {
        if error.is_object() {
            return Some(error.clone());
        }
        let mut object = Map::new();
        if let Some(code) = result.get("code").and_then(Value::as_str) {
            object.insert("code".to_owned(), Value::String(code.to_owned()));
        }
        object.insert("message".to_owned(), error.clone());
        return Some(Value::Object(object));
    }
    if let Some(code) = result.get("code").and_then(Value::as_str) {
        return Some(json!({ "code": code }));
    }
    None
}

#[derive(Debug, Clone)]
struct ToolResultRecord {
    tool_call: Value,
    tool_response: Value,
}

impl ToolResultRecord {
    fn new(tool_call: Value, tool_response: Value) -> Self {
        Self {
            tool_call,
            tool_response,
        }
    }

    fn from_value(
        value: &Value,
        label: &str,
        catalog: &AgentRuntimeCatalog,
        agent_id: &str,
    ) -> Result<Self> {
        let object = value
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("{label} must be an object"))?;
        let tool_call = object
            .get("tool_call")
            .ok_or_else(|| anyhow::anyhow!("{label}.tool_call is required"))?;
        require_previous_tool_call_catalog_tool(catalog, agent_id, tool_call)?;
        let tool_response = object
            .get("tool_response")
            .ok_or_else(|| anyhow::anyhow!("{label}.tool_response is required"))?;
        require_tool_response_envelope(tool_response)
            .map_err(|error| anyhow::anyhow!("{label}.tool_response: {error}"))?;
        require_matching_tool_response_id(tool_call, tool_response)
            .map_err(|error| anyhow::anyhow!("{label}.tool_response: {error}"))?;
        Ok(Self::new(tool_call.clone(), tool_response.clone()))
    }

    fn to_value(&self) -> Value {
        json!({
            "tool_call": self.tool_call,
            "tool_response": self.tool_response,
        })
    }

    fn to_values(records: &[Self]) -> Vec<Value> {
        records.iter().map(Self::to_value).collect()
    }
}

#[derive(Debug, Clone, Copy, Default)]
struct RuntimeContinuationCounts {
    remaining_tool_count: usize,
    tool_result_count: usize,
}

#[derive(Debug, Clone)]
struct RuntimeContinuation {
    tool_plan: Vec<Value>,
    tool_results: Vec<ToolResultRecord>,
    llm_response: Option<Value>,
    next_step_index: u64,
}

impl RuntimeContinuation {
    fn from_tool_request_state(state: &ToolRequestState) -> Option<Self> {
        if state.remaining.is_empty()
            && state.tool_results.is_empty()
            && state.llm_response.is_none()
            && state.step_index == 0
        {
            return None;
        }
        Some(Self {
            tool_plan: state.remaining.clone(),
            tool_results: state.tool_results.clone(),
            llm_response: state.llm_response.clone(),
            next_step_index: state.step_index + 1,
        })
    }

    fn from_step(
        previous_step: &Value,
        catalog: &AgentRuntimeCatalog,
        agent_id: &str,
    ) -> Result<Option<Self>> {
        let Some(value) = previous_step.get("continuation") else {
            return Ok(None);
        };
        let object = value
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("continuation must be an object"))?;
        let tool_plan = match object.get("tool_plan") {
            Some(value) => value
                .as_array()
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("continuation.tool_plan must be an array"))?,
            None => Vec::new(),
        };
        let tool_results = match object.get("tool_results") {
            Some(value) => Self::tool_results_from_value(value, catalog, agent_id)?,
            None => Vec::new(),
        };
        let next_step_index = object.get("next_step_index").ok_or_else(|| {
            anyhow::anyhow!(
                "continuation.next_step_index must be present when continuation is present"
            )
        })?;
        let next_step_index = next_step_index.as_u64().ok_or_else(|| {
            anyhow::anyhow!("continuation.next_step_index must be a non-negative integer")
        })?;
        Ok(Some(Self {
            tool_plan,
            tool_results,
            llm_response: object.get("llm_response").cloned(),
            next_step_index,
        }))
    }

    fn counts_from_step(step: &Value) -> RuntimeContinuationCounts {
        let Some(continuation) = step.get("continuation").and_then(Value::as_object) else {
            return RuntimeContinuationCounts::default();
        };
        RuntimeContinuationCounts {
            remaining_tool_count: continuation
                .get("tool_plan")
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0),
            tool_result_count: continuation
                .get("tool_results")
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0),
        }
    }

    fn tool_results_from_value(
        value: &Value,
        catalog: &AgentRuntimeCatalog,
        agent_id: &str,
    ) -> Result<Vec<ToolResultRecord>> {
        let results = value
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("continuation.tool_results must be an array"))?;
        results
            .iter()
            .enumerate()
            .map(|(index, result)| {
                ToolResultRecord::from_value(
                    result,
                    &format!("continuation.tool_results[{index}]"),
                    catalog,
                    agent_id,
                )
            })
            .collect()
    }

    fn validate_tool_plan(&self, catalog: &AgentRuntimeCatalog, agent_id: &str) -> Result<()> {
        for (index, tool_call) in self.tool_plan.iter().enumerate() {
            require_previous_tool_call_catalog_tool(catalog, agent_id, tool_call)
                .map_err(|error| anyhow::anyhow!("continuation.tool_plan[{index}]: {error}"))?;
        }
        Ok(())
    }

    fn require_next_step_index(&self, previous_step_index: u64) -> Result<()> {
        let expected = previous_step_index + 1;
        if self.next_step_index != expected {
            anyhow::bail!(
                "continuation.next_step_index {} must equal previous step_index + 1 ({expected})",
                self.next_step_index
            );
        }
        Ok(())
    }

    fn requested_step_index(&self) -> u64 {
        self.next_step_index.saturating_sub(1)
    }

    fn to_value(&self) -> Value {
        let mut object = Map::new();
        object.insert("tool_plan".to_owned(), Value::Array(self.tool_plan.clone()));
        object.insert(
            "tool_results".to_owned(),
            Value::Array(ToolResultRecord::to_values(&self.tool_results)),
        );
        if let Some(llm_response) = &self.llm_response {
            object.insert("llm_response".to_owned(), llm_response.clone());
        }
        object.insert(
            "next_step_index".to_owned(),
            Value::Number(serde_json::Number::from(self.next_step_index)),
        );
        Value::Object(object)
    }
}

#[derive(Debug)]
struct ToolRequestState {
    first: contracts::RequestedToolCall,
    remaining: Vec<Value>,
    tool_results: Vec<ToolResultRecord>,
    llm_response: Option<Value>,
    step_index: u64,
}

impl ToolRequestState {
    fn continuation(&self) -> Option<RuntimeContinuation> {
        RuntimeContinuation::from_tool_request_state(self)
    }
}

fn parse_initial_tool_request(input: &Value) -> Result<Option<ToolRequestState>> {
    if let Some(tool_plan) = input.get("tool_plan") {
        let plan = tool_plan
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("tool_plan must be an array"))?;
        if plan.is_empty() {
            return Ok(None);
        }
        let first = contracts::parse_requested_tool_call(&plan[0], "tool_plan[0]")?;
        return Ok(Some(ToolRequestState {
            first,
            remaining: plan[1..].to_vec(),
            tool_results: Vec::new(),
            llm_response: input.get("llm_response").cloned(),
            step_index: 0,
        }));
    }

    let Some(tool_call) = input.get("tool_call") else {
        return Ok(None);
    };
    Ok(Some(ToolRequestState {
        first: contracts::parse_requested_tool_call(tool_call, "tool_call")?,
        remaining: Vec::new(),
        tool_results: Vec::new(),
        llm_response: input.get("llm_response").cloned(),
        step_index: 0,
    }))
}

fn next_tool_request_from_continuation(
    continuation: Option<RuntimeContinuation>,
    tool_results: Vec<ToolResultRecord>,
) -> Result<Option<ToolRequestState>> {
    let Some(continuation) = continuation else {
        return Ok(None);
    };
    if continuation.tool_plan.is_empty() {
        return Ok(None);
    }
    let first = contracts::parse_requested_tool_call(
        &continuation.tool_plan[0],
        "continuation.tool_plan[0]",
    )?;
    Ok(Some(ToolRequestState {
        first,
        remaining: continuation.tool_plan[1..].to_vec(),
        tool_results,
        llm_response: continuation.llm_response,
        step_index: continuation.next_step_index,
    }))
}

fn build_tool_call_requested_step(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    agent_version: &str,
    run_id: Value,
    tool_call: contracts::RequestedToolCall,
    continuation: Option<RuntimeContinuation>,
) -> Result<Value> {
    if let Some(continuation) = &continuation {
        continuation.validate_tool_plan(catalog, agent_id)?;
    }
    let tool = catalog
        .tools
        .iter()
        .find(|tool| tool.name == tool_call.name)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "tool '{}' requested by agent '{}' is not present in the catalog",
                tool_call.name,
                agent_id
            )
        })?;
    let mut step = json!({
        "protocol_version": protocol_version(),
        "run_id": run_id,
        "agent_id": agent_id,
        "agent_version": agent_version,
        "step_index": continuation
            .as_ref()
            .map(RuntimeContinuation::requested_step_index)
            .unwrap_or(0),
        "status": "tool_call_requested",
        "tool_call": {
            "tool_call_id": ToolCallId::new_v7(),
            "name": tool.name,
            "input": tool_call.input,
            "risk": tool.risk,
            "metadata": tool.metadata,
        }
    });
    if let Some(continuation) = continuation {
        step.as_object_mut()
            .expect("step is an object")
            .insert("continuation".to_owned(), continuation.to_value());
    }
    attach_runtime_metadata(&mut step);
    Ok(step)
}

fn attach_runtime_metadata(step: &mut Value) {
    attach_run_state(step);
    attach_trace_event(step);
}

fn attach_run_state(step: &mut Value) {
    let Some(object) = step.as_object_mut() else {
        return;
    };
    let continuation = object.get("continuation");
    let remaining_tool_count = continuation
        .and_then(|value| value.get("tool_plan"))
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    let continuation_result_count = continuation
        .and_then(|value| value.get("tool_results"))
        .and_then(Value::as_array)
        .map(Vec::len);
    let output_result_count = object
        .get("output")
        .and_then(|value| value.get("tool_results"))
        .and_then(Value::as_array)
        .map(Vec::len);
    let root_result_count = object
        .get("tool_results")
        .and_then(Value::as_array)
        .map(Vec::len);
    let tool_result_count = continuation_result_count
        .or(output_result_count)
        .or(root_result_count)
        .unwrap_or(0);
    let status = object.get("status").cloned().unwrap_or(Value::Null);
    let state = json!({
        "status": status,
        "step_index": object.get("step_index").cloned().unwrap_or(Value::Null),
        "remaining_tool_count": remaining_tool_count,
        "tool_result_count": tool_result_count,
        "terminal_reason": terminal_reason_for_status(object.get("status").and_then(Value::as_str)),
    });
    object.insert("run_state".to_owned(), state);
}

fn terminal_reason_for_status(status: Option<&str>) -> Value {
    match status {
        Some("completed") => Value::String("done".to_owned()),
        Some("failed") => Value::String("stream_error".to_owned()),
        Some("cancelled") => Value::String("user_cancel".to_owned()),
        Some("policy_denied") => Value::String("policy_denied".to_owned()),
        Some("closed_early") | Some("timed_out") => Value::String("closed_early".to_owned()),
        _ => Value::Null,
    }
}

fn attach_trace_event(step: &mut Value) {
    let Some(object) = step.as_object_mut() else {
        return;
    };
    let event = json!({
        "kind": "agent_runtime_step",
        "run_id": object.get("run_id").cloned().unwrap_or(Value::Null),
        "agent_id": object.get("agent_id").cloned().unwrap_or(Value::Null),
        "status": object.get("status").cloned().unwrap_or(Value::Null),
        "step_index": object.get("step_index").cloned().unwrap_or(Value::Null),
        "run_state": object.get("run_state").cloned().unwrap_or(Value::Null),
        "tool_name": object
            .get("tool_call")
            .and_then(|tool_call| tool_call.get("name"))
            .or_else(|| {
                object
                    .get("output")
                    .and_then(|output| output.get("tool_call"))
                    .and_then(|tool_call| tool_call.get("name"))
            })
            .cloned()
            .unwrap_or(Value::Null),
    });
    object.insert("trace_event".to_owned(), event);
}

pub(super) fn runtime_input_from_llm_response(response: &LlmResponse) -> Result<Value> {
    if let Some(tool_plan) = response
        .metadata
        .get("tool_plan")
        .or_else(|| response.metadata.get("tool_calls"))
    {
        let plan = tool_plan
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("LLM metadata tool plan must be an array"))?;
        if !plan.is_empty() {
            return Ok(json!({
                "tool_plan": plan,
                "llm_response": response,
            }));
        }
    }
    if let Some(tool_call) = response.metadata.get("tool_call") {
        return Ok(json!({
            "tool_call": tool_call,
            "llm_response": response,
        }));
    }
    Ok(json!({
        "content": response.content,
        "llm_response": response,
    }))
}
