//! Recognition migration contracts exercised through the real pi providers.
use navi_assistant::{
    CancellationToken, Config, Limits, Provider,
    recognition::{self, LlmFinishReason, LlmRequest, LlmResponse},
};
use serde_json::{Value, json};
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::mpsc,
    time::Duration,
};

fn server(bodies: Vec<String>) -> (String, mpsc::Receiver<Value>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let (send, receive) = mpsc::channel();
    std::thread::spawn(move || {
        for body in bodies {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut bytes = Vec::new();
            let mut buffer = [0; 4096];
            loop {
                let count = stream.read(&mut buffer).unwrap();
                assert!(count > 0);
                bytes.extend_from_slice(&buffer[..count]);
                assert!(bytes.len() < 1_000_000);
                if let Some(end) = bytes.windows(4).position(|v| v == b"\r\n\r\n") {
                    let headers = String::from_utf8_lossy(&bytes[..end]);
                    let length = headers
                        .lines()
                        .find_map(|line| {
                            let (name, value) = line.split_once(':')?;
                            name.eq_ignore_ascii_case("content-length")
                                .then(|| value.trim().parse::<usize>().unwrap())
                        })
                        .unwrap_or_default();
                    if bytes.len() >= end + 4 + length {
                        send.send(
                            serde_json::from_slice(&bytes[end + 4..end + 4 + length]).unwrap(),
                        )
                        .unwrap();
                        break;
                    }
                }
            }
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    (format!("http://{address}/v1"), receive)
}
fn event(kind: &str, value: Value) -> String {
    format!("event: {kind}\ndata: {value}\n\n")
}
fn response(provider: Provider, calls: Vec<(&str, &str, Value)>, signed: bool) -> String {
    match provider {
        Provider::Anthropic => {
            let mut events = vec![event(
                "message_start",
                json!({"type":"message_start","message":{"id":"message-1","type":"message","role":"assistant","model":"owner-model","content":[],"stop_reason":null,"usage":{"input_tokens":12,"output_tokens":0}}}),
            )];
            let mut blocks = Vec::new();
            if signed {
                blocks.extend([json!({"type":"thinking","thinking":"Private reasoning","signature":"signed-opaque"}),json!({"type":"redacted_thinking","data":"redacted-opaque"})]);
            }
            blocks.extend(calls.into_iter().map(
                |(id, name, input)| json!({"type":"tool_use","id":id,"name":name,"input":input}),
            ));
            for (index, mut block) in blocks.into_iter().enumerate() {
                let arguments = (block["type"] == "tool_use").then(|| block["input"].to_string());
                if arguments.is_some() {
                    block["input"] = json!({});
                }
                events.push(event(
                    "content_block_start",
                    json!({"type":"content_block_start","index":index,"content_block":block}),
                ));
                if let Some(arguments) = arguments {
                    events.push(event("content_block_delta",json!({"type":"content_block_delta","index":index,"delta":{"type":"input_json_delta","partial_json":arguments}})));
                }
                events.push(event(
                    "content_block_stop",
                    json!({"type":"content_block_stop","index":index}),
                ));
            }
            events.push(event("message_delta",json!({"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":5}})));
            events.push(event("message_stop", json!({"type":"message_stop"})));
            events.join("")
        }
        Provider::OpenAiCompatible => {
            let calls=calls.into_iter().enumerate().map(|(index,(id,name,input))|json!({"index":index,"id":id,"type":"function","function":{"name":name,"arguments":input.to_string()}})).collect::<Vec<_>>();
            format!(
                "data: {}\n\ndata: {}\n\ndata: [DONE]\n\n",
                json!({"model":"owner-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":calls}}]}),
                json!({"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":5,"total_tokens":17}})
            )
        }
        Provider::OpenAiResponses => {
            let mut output = Vec::new();
            if signed {
                output.extend([json!({"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"encrypted-opaque"}),json!({"type":"message","id":"msg_1","role":"assistant","phase":"commentary","status":"completed","content":[{"type":"output_text","text":"Clarification","annotations":[]}]})]);
            }
            output.extend(calls.into_iter().map(|(id,name,input)|json!({"type":"function_call","id":format!("fc_{id}"),"call_id":id,"name":name,"arguments":input.to_string(),"status":"completed"})));
            event(
                "response.completed",
                json!({"type":"response.completed","response":{"id":"resp_1","model":"owner-model","status":"completed","output":output,"usage":{"input_tokens":12,"output_tokens":5,"total_tokens":17}}}),
            )
        }
    }
}
fn config(provider: Provider, base_url: String) -> Config {
    Config {
        provider,
        base_url,
        api_key: "owner-key".into(),
        model: "owner-model".into(),
        system_prompt: String::new(),
        limits: Limits {
            timeout: Duration::from_secs(5),
            ..Limits::default()
        },
        context_summary: None,
    }
}
fn request() -> LlmRequest {
    serde_json::from_value(json!({"protocol_version":"agent.v1","provider":"owner","model":"owner-model","messages":[{"role":"user","content":[{"type":"text","text":"Estimate"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]}],"max_output_tokens":1000,"tools":[{"name":"ask_user","description":"Ask owner","input_schema":{"type":"object","additionalProperties":false,"required":["question"],"properties":{"question":{"type":"string"}}}}],"response_format":{"type":"json_schema","name":"estimate","schema":{"type":"object","additionalProperties":false,"required":["value"],"properties":{"value":{"type":"integer"}}},"strict":true}})).unwrap()
}
async fn call(config: &Config, request: LlmRequest) -> Result<LlmResponse, recognition::LlmError> {
    recognition::complete(config, request, CancellationToken::new(), |_| {}).await
}
fn continue_after(request: &mut LlmRequest, response: &LlmResponse) {
    let id = response.metadata["anthropic_content"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["type"] == "tool_use")
        .unwrap()["id"]
        .clone();
    request.messages.push(serde_json::from_value(json!({"role":"assistant","content":response.metadata["anthropic_content"],"metadata":{"responses_output":response.metadata["responses_output"]}})).unwrap());
    request.messages.push(serde_json::from_value(json!({"role":"user","content":[{"type":"tool_result","tool_use_id":id,"content":"Owner answered"}]})).unwrap());
}

#[tokio::test]
async fn image_and_structured_result_reach_all_three_provider_wires() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        let (base, wire) = server(vec![response(
            provider,
            vec![("call_result_1", "emit_result", json!({"value":7}))],
            false,
        )]);
        let result = call(&config(provider, base), request()).await.unwrap();
        assert_eq!(result.object, Some(json!({"value":7})), "{provider:?}");
        assert_eq!(result.finish_reason, LlmFinishReason::Stop);
        let wire = wire.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(
            wire.to_string().contains("iVBORw0KGgo="),
            "image omitted: {wire}"
        );
        let tool = wire["tools"]
            .as_array()
            .unwrap()
            .iter()
            .find(|tool| tool["name"] == "emit_result" || tool["function"]["name"] == "emit_result")
            .unwrap();
        let schema = match provider {
            Provider::Anthropic => &tool["input_schema"],
            Provider::OpenAiCompatible => &tool["function"]["parameters"],
            Provider::OpenAiResponses => &tool["parameters"],
        };
        assert_eq!(schema["properties"]["value"]["type"], "integer");
        assert_eq!(schema["additionalProperties"], false);
        if provider == Provider::OpenAiResponses {
            assert_eq!(wire["store"], false);
        }
    }
}

#[tokio::test]
async fn native_ask_user_replay_preserves_signatures_and_call_identity() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        let (base, wires) = server(vec![
            response(
                provider,
                vec![("call_ask_1", "ask_user", json!({"question":"How much?"}))],
                true,
            ),
            response(
                provider,
                vec![("call_result_1", "emit_result", json!({"value":7}))],
                false,
            ),
        ]);
        let config = config(provider, base);
        let mut request = request();
        let first = call(&config, request.clone()).await.unwrap();
        assert_eq!(first.finish_reason, LlmFinishReason::ToolCall);
        continue_after(&mut request, &first);
        assert_eq!(
            call(&config, request).await.unwrap().object,
            Some(json!({"value":7}))
        );
        let _ = wires.recv_timeout(Duration::from_secs(2)).unwrap();
        let wire = wires.recv_timeout(Duration::from_secs(2)).unwrap();
        match provider {
            Provider::Anthropic => {
                let blocks = wire["messages"][1]["content"].as_array().unwrap();
                assert!(
                    blocks
                        .iter()
                        .any(|b| b["type"] == "thinking" && b["signature"] == "signed-opaque")
                );
                assert!(blocks.iter().any(|b|b["type"]=="redacted_thinking" && b["data"]=="redacted-opaque"));
                assert_eq!(
                    wire["messages"][2]["content"][0]["tool_use_id"],
                    "call_ask_1"
                );
            }
            Provider::OpenAiCompatible => assert!(
                wire["messages"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|m| m["role"] == "tool" && m["tool_call_id"] == "call_ask_1"),
                "{wire}"
            ),
            Provider::OpenAiResponses => {
                let input = wire["input"].as_array().unwrap();
                assert!(
                    input.iter().any(|i| i["type"] == "reasoning"
                        && i["encrypted_content"] == "encrypted-opaque")
                );
                assert!(input.iter().any(|i| i["type"] == "message"
                    && i["id"] == "msg_1"
                    && i["phase"] == "commentary"));
                assert!(input.iter().any(|i| i["type"] == "function_call"
                    && i["id"] == "fc_call_ask_1"
                    && i["call_id"] == "call_ask_1"));
                assert!(input.iter().any(|i| i["type"] == "function_call_output"
                    && i["call_id"] == "call_ask_1"
                    && i["output"].to_string().contains("Owner answered")));
            }
        }
    }
}

#[tokio::test]
async fn legacy_responses_output_replays_phase_reasoning_and_owner_answer() {
    let provider = Provider::OpenAiResponses;
    let (base, wire) = server(vec![response(
        provider,
        vec![("call_result_1", "emit_result", json!({"value":7}))],
        false,
    )]);
    let mut request = request();
    request.messages.extend(serde_json::from_value::<Vec<_>>(json!([
        {"role":"assistant","content":[{"type":"tool_use","id":"call_old","name":"ask_user","input":{"question":"How much?"}}],"metadata":{"responses_output":[
            {"type":"reasoning","id":"rs_old","summary":[],"encrypted_content":"old-encrypted"},
            {"type":"message","id":"msg_old","role":"assistant","phase":"commentary","status":"completed","content":[{"type":"output_text","text":"Question","annotations":[]}]},
            {"type":"function_call","id":"fc_old","call_id":"call_old","name":"ask_user","arguments":"{\"question\":\"How much?\"}","status":"completed"}]}},
        {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_old","content":"Half"}]}])).unwrap());
    call(&config(provider, base), request).await.unwrap();
    let wire = wire.recv_timeout(Duration::from_secs(2)).unwrap();
    let input = wire["input"].as_array().unwrap();
    assert!(
        input
            .iter()
            .any(|i| i["id"] == "rs_old" && i["encrypted_content"] == "old-encrypted")
    );
    assert!(
        input
            .iter()
            .any(|i| i["id"] == "msg_old" && i["phase"] == "commentary")
    );
    assert!(input.iter().any(|i| i["type"] == "function_call_output"
        && i["call_id"] == "call_old"
        && i["output"].to_string().contains("Half")));
}

#[tokio::test]
async fn ambiguous_or_unknown_tool_calls_never_produce_a_draft() {
    for calls in [
        vec![
            ("one", "emit_result", json!({"value":1})),
            ("two", "ask_user", json!({"question":"Why?"})),
        ],
        vec![
            ("one", "emit_result", json!({"value":1})),
            ("two", "emit_result", json!({"value":2})),
        ],
        vec![("one", "write_records", json!({"value":1}))],
    ] {
        let (base, _wire) = server(vec![response(Provider::Anthropic, calls, false)]);
        assert!(
            call(&config(Provider::Anthropic, base), request())
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn restored_native_metadata_must_agree_with_owner_question() {
    let provider = Provider::Anthropic;
    let (base, _wire) = server(vec![response(
        provider,
        vec![("call_ask_1", "ask_user", json!({"question":"How much?"}))],
        true,
    )]);
    let config = config(provider, base);
    let mut request = request();
    let mut first = call(&config, request.clone()).await.unwrap();
    let blocks = first.metadata["anthropic_content"].as_array_mut().unwrap();
    blocks.iter_mut().find(|b| b["type"] == "tool_use").unwrap()["input"]["question"] =
        json!("Different question");
    continue_after(&mut request, &first);
    let error = call(&config, request).await.unwrap_err();
    assert_eq!(error.record.code, "recognition_invalid_history");
}

#[tokio::test]
async fn final_result_tool_is_acknowledged_before_owner_correction() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        let (base, wires) = server(vec![
            response(
                provider,
                vec![("call_result_1", "emit_result", json!({"value":7}))],
                false,
            ),
            response(
                provider,
                vec![("call_result_2", "emit_result", json!({"value":8}))],
                false,
            ),
        ]);
        let config = config(provider, base);
        let mut request = request();
        let first = call(&config, request.clone()).await.unwrap();
        request.messages.extend(serde_json::from_value::<Vec<_>>(json!([
            {"role":"assistant","content":first.content,"metadata":{"responses_output":first.metadata["responses_output"]}},
            {"role":"user","content":"Actually eight"}])).unwrap());
        assert_eq!(
            call(&config, request).await.unwrap().object,
            Some(json!({"value":8}))
        );
        let _ = wires.recv_timeout(Duration::from_secs(2)).unwrap();
        let wire = wires.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(
            wire.to_string()
                .contains("Draft presented for owner review; no records were written.")
        );
        assert!(!wire.to_string().contains("No result provided"));
    }
}

#[tokio::test]
async fn provider_truncation_refusal_and_oversized_output_fail_closed() {
    for (provider, from, to) in [
        (
            Provider::Anthropic,
            "\"stop_reason\":\"tool_use\"",
            "\"stop_reason\":\"max_tokens\"",
        ),
        (
            Provider::Anthropic,
            "\"stop_reason\":\"tool_use\"",
            "\"stop_reason\":\"refusal\"",
        ),
        (
            Provider::OpenAiCompatible,
            "\"finish_reason\":\"tool_calls\"",
            "\"finish_reason\":\"length\"",
        ),
        (
            Provider::OpenAiResponses,
            "\"status\":\"completed\"",
            "\"status\":\"incomplete\"",
        ),
    ] {
        let body = response(
            provider,
            vec![("call_result_1", "emit_result", json!({"value":7}))],
            false,
        )
        .replace(from, to);
        let (base, _wire) = server(vec![body]);
        assert!(
            call(&config(provider, base), request()).await.is_err(),
            "{provider:?} {to}"
        );
    }
    let body = format!(
        "data: {}\n\ndata: {}\n\ndata: [DONE]\n\n",
        json!({"choices":[{"index":0,"delta":{"content":"x".repeat(100_001)}}]}),
        json!({"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]})
    );
    let (base, _wire) = server(vec![body]);
    let error = call(&config(Provider::OpenAiCompatible, base), request())
        .await
        .unwrap_err();
    assert_eq!(error.record.code, "recognition_output_limit");
}

#[tokio::test]
async fn cancellation_after_partial_output_closes_the_provider_connection() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}/v1", listener.local_addr().unwrap());
    let (closed_send, closed_receive) = mpsc::channel();
    std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let mut bytes = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let count = socket.read(&mut buffer).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&buffer[..count]);
            if let Some(end) = bytes.windows(4).position(|v| v == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&bytes[..end]);
                let length = headers
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().unwrap())
                    })
                    .unwrap_or_default();
                if bytes.len() >= end + 4 + length {
                    break;
                }
            }
        }
        let delta = json!({"choices":[{"index":0,"delta":{"content":"x".repeat(8192)}}]});
        write!(socket,"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\ndata: {delta}\n\n").unwrap();
        socket.flush().unwrap();
        let closed = match socket.read(&mut [0; 1]) {
            Ok(0) => true,
            Err(error) => matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionReset
                    | std::io::ErrorKind::ConnectionAborted
                    | std::io::ErrorKind::BrokenPipe
            ),
            _ => false,
        };
        closed_send.send(closed).unwrap();
    });
    let cancel = CancellationToken::new();
    let trigger = cancel.clone();
    let error = recognition::complete(
        &config(Provider::OpenAiCompatible, base),
        request(),
        cancel,
        move |_| trigger.cancel(),
    )
    .await
    .unwrap_err();
    assert_eq!(error.record.code, "recognition_cancelled");
    assert!(
        tokio::task::spawn_blocking(move || closed_receive
            .recv_timeout(Duration::from_secs(4))
            .unwrap())
        .await
        .unwrap()
    );
}

#[tokio::test]
async fn responses_noncanonical_ids_fail_closed_in_new_and_restored_calls() {
    let provider = Provider::OpenAiResponses;
    let (base, _wire) = server(vec![response(
        provider,
        vec![("custom-id", "ask_user", json!({"question":"How much?"}))],
        false,
    )]);
    assert!(call(&config(provider, base), request()).await.is_err());
    let mut request = request();
    request.messages.extend(serde_json::from_value::<Vec<_>>(json!([
        {"role":"assistant","content":[{"type":"tool_use","id":"custom-id","name":"ask_user","input":{"question":"How much?"}}],"metadata":{"responses_output":[
            {"type":"function_call","id":"fc_custom","call_id":"custom-id","name":"ask_user","arguments":"{\"question\":\"How much?\"}","status":"completed"}]}},
        {"role":"user","content":[{"type":"tool_result","tool_use_id":"custom-id","content":"Half"}]}])).unwrap());
    let error = call(&config(provider, "http://127.0.0.1:1/v1".into()), request)
        .await
        .unwrap_err();
    assert_eq!(error.record.code, "recognition_invalid_history");
}
