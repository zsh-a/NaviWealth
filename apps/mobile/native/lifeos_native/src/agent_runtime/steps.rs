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
    let step = agent_runtime_upstream::RunLoop::start_step(&catalog, request, &agent_id)
        .map_err(runtime_error)?;
    Ok(serde_json::to_string(&step)?)
}

pub(super) fn agent_runtime_continue_run_step(
    catalog_json: String,
    previous_step_json: String,
    effect_response_json: String,
    agent_id: String,
) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    contracts::require_catalog_contract(&catalog)?;
    let previous_step: Value = serde_json::from_str(&previous_step_json)?;
    let effect_response: Value = serde_json::from_str(&effect_response_json)?;
    let step = agent_runtime_upstream::RunLoop::continue_step(
        &catalog,
        previous_step,
        effect_response,
        &agent_id,
    )
    .map_err(runtime_error)?;
    Ok(serde_json::to_string(&step)?)
}

pub(super) fn runtime_input_from_llm_response(response: &LlmResponse) -> Result<Value> {
    if let Some(tool_plan) = response
        .metadata
        .get("effects")
        .or_else(|| response.metadata.get("tool_plan"))
        .or_else(|| response.metadata.get("tool_calls"))
    {
        let plan = tool_plan
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("LLM metadata tool plan must be an array"))?;
        if !plan.is_empty() {
            return Ok(json!({
                "effects": plan,
                "tool_plan": plan,
                "llm_response": response,
            }));
        }
    }
    if let Some(subagent_call) = response.metadata.get("subagent_call") {
        return Ok(json!({
            "subagent_call": subagent_call,
            "llm_response": response,
        }));
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

fn runtime_error(error: agent_core::AgentError) -> anyhow::Error {
    anyhow::anyhow!(error.record.message)
}
