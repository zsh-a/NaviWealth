use super::llm_provider::llm_error_to_anyhow;
use super::*;

pub(super) fn profile_turn_run_metadata(run_metadata_json: &str) -> Result<Value> {
    if run_metadata_json.trim().is_empty() {
        return Ok(json!({}));
    }
    let metadata = serde_json::from_str::<Value>(run_metadata_json)?;
    if metadata.is_null() {
        return Ok(json!({}));
    }
    if !metadata.is_object() {
        anyhow::bail!("run metadata must be a JSON object");
    }
    Ok(metadata)
}

pub(super) async fn complete_profile_llm_response(mut request: LlmRequest) -> Result<LlmResponse> {
    contracts::normalize_llm_request_contract(&mut request)?;
    let mut response = profile_llm_provider(&request)?
        .complete(request)
        .await
        .map_err(llm_error_to_anyhow)?;
    contracts::normalize_llm_response_contract(&mut response)?;
    Ok(response)
}

pub(super) async fn stream_llm_response(
    sink: StreamSink<String>,
    provider: Box<dyn LlmProvider>,
    request: LlmRequest,
) -> Result<()> {
    let mut stream = provider
        .stream(request)
        .await
        .map_err(llm_error_to_anyhow)?;
    while let Some(event) = stream.next().await {
        match event {
            Ok(mut event) => {
                contracts::normalize_llm_event_contract(&mut event)?;
                let _ = sink.add(serde_json::to_string(&event)?);
            }
            Err(error) => {
                let record = error.record;
                let _ = sink.add(serde_json::to_string(&json!({
                    "kind": "error",
                    "content": null,
                    "metadata": {
                        "code": record.code,
                        "message": record.message,
                        "retryable": record.retryable,
                        "details": record.details,
                    }
                }))?);
                break;
            }
        }
    }
    Ok(())
}
