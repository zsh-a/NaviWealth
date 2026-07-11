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
    let step = agent_runtime_upstream::EffectStepLoop::start_step(&catalog, request, &agent_id)
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
    let step = agent_runtime_upstream::EffectStepLoop::continue_step(
        &catalog,
        previous_step,
        effect_response,
        &agent_id,
    )
    .map_err(runtime_error)?;
    Ok(serde_json::to_string(&step)?)
}

pub(super) fn runtime_input_from_llm_response(response: &LlmResponse) -> Result<Value> {
    if let Some(effects) = response.metadata.get("effects") {
        let effects = effects
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("LLM metadata effects must be an array"))?;
        if !effects.is_empty() {
            return Ok(json!({
                "effects": effects,
                "llm_response": response,
            }));
        }
    }
    Ok(json!({
        "content": response.content,
        "llm_response": response,
    }))
}

fn runtime_error(error: agent_core::AgentError) -> anyhow::Error {
    anyhow::anyhow!(error.record.message)
}
