//! Real local HTTP fixtures: exercise the selected pi-rust provider rather
//! than a mocked host function, including account base-path normalization.
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{Arc, mpsc},
    time::Duration,
};

use base64::{Engine, engine::general_purpose::STANDARD};
use futures::FutureExt;
use navi_assistant::{
    CancellationToken, Config, Event, ImageInput, Limits, Provider, run, run_multimodal,
};
use serde_json::{Value, json};

fn server(status: &str, extra_headers: &str, body: &str) -> (String, mpsc::Receiver<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n{extra_headers}\r\n{body}",
        body.len()
    );
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut request = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let count = stream.read(&mut buffer).unwrap();
            if count == 0 {
                break;
            }
            request.extend_from_slice(&buffer[..count]);
            assert!(request.len() < 1_000_000);
            if let Some(end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..end]);
                let length = headers
                    .lines()
                    .find_map(|line| {
                        let (key, value) = line.split_once(':')?;
                        key.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().unwrap())
                    })
                    .unwrap_or(0);
                if request.len() >= end + 4 + length {
                    break;
                }
            }
        }
        let _ = tx.send(String::from_utf8(request).unwrap());
        stream.write_all(response.as_bytes()).unwrap();
    });
    (format!("http://{address}/gateway/v1"), rx)
}

fn event(kind: &str, body: Value) -> String {
    format!("event: {kind}\ndata: {body}\n\n")
}

fn reply(provider: Provider) -> String {
    match provider {
        Provider::OpenAiCompatible => format!("data: {}\n\ndata: {}\n\ndata: [DONE]\n\n",
            json!({"id":"reply-1","object":"chat.completion.chunk","model":"owner-model","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}),
            json!({"id":"reply-1","object":"chat.completion.chunk","model":"owner-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}})),
        Provider::Anthropic => [
            event("message_start", json!({"type":"message_start","message":{"id":"reply-1","type":"message","role":"assistant","model":"owner-model","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":0}}})),
            event("content_block_start", json!({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}})),
            event("content_block_delta", json!({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}})),
            event("content_block_stop", json!({"type":"content_block_stop","index":0})),
            event("message_delta", json!({"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}})),
            event("message_stop", json!({"type":"message_stop"})),
        ].join(""),
        Provider::OpenAiResponses => [
            event("response.created", json!({"type":"response.created","response":{"id":"reply-1","model":"owner-model","status":"in_progress","output":[]}})),
            event("response.output_item.added", json!({"type":"response.output_item.added","output_index":0,"item":{"id":"msg_1","type":"message","role":"assistant","content":[]}})),
            event("response.output_text.delta", json!({"type":"response.output_text.delta","output_index":0,"content_index":0,"item_id":"msg_1","delta":"Hello"})),
            event("response.completed", json!({"type":"response.completed","response":{"id":"reply-1","model":"owner-model","status":"completed","output":[{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello","annotations":[]}]}],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}})),
        ].join(""),
    }
}

fn config(provider: Provider, base_url: String) -> Config {
    Config {
        context_summary: None,
        provider,
        base_url,
        api_key: "owner-key".into(),
        model: "owner-model".into(),
        system_prompt: "Help".into(),
        limits: Limits::default(),
    }
}

#[tokio::test]
async fn all_protocols_use_owner_endpoint_and_stream_a_reply() {
    for (provider, suffix, header) in [
        (Provider::Anthropic, "messages", "x-api-key: owner-key"),
        (
            Provider::OpenAiCompatible,
            "chat/completions",
            "authorization: Bearer owner-key",
        ),
        (
            Provider::OpenAiResponses,
            "responses",
            "authorization: Bearer owner-key",
        ),
    ] {
        let (base, request) = server("200 OK", "", &reply(provider));
        let result = run(
            config(provider, base),
            vec![],
            "Hi".into(),
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(result.text, "Hello", "{provider:?}");
        let request = request.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(
            request.starts_with(&format!("POST /gateway/v1/{suffix} HTTP/1.1")),
            "{request}"
        );
        assert!(
            request
                .to_ascii_lowercase()
                .contains(&header.to_ascii_lowercase())
        );
        let (_, body) = request.split_once("\r\n\r\n").unwrap();
        let body: Value = serde_json::from_str(body).unwrap();
        assert_eq!(body["model"], "owner-model");
        if provider == Provider::OpenAiResponses {
            assert_eq!(body["store"], false);
        }
        assert!(
            !serde_json::to_string(&result.history)
                .unwrap()
                .contains("owner-key")
        );
    }
}

#[tokio::test]
async fn redirect_and_provider_error_bodies_do_not_escape_the_boundary() {
    for (status, headers) in [
        ("302 Found", "Location: http://127.0.0.1:1/stolen\r\n"),
        ("401 Unauthorized", ""),
    ] {
        let (base, _) = server(status, headers, "secret-owner-key-response-body");
        let observed = Arc::new(std::sync::Mutex::new(Vec::<Event>::new()));
        let copy = observed.clone();
        let result = run(
            config(Provider::OpenAiCompatible, base),
            vec![],
            "Hi".into(),
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(move |event| copy.lock().unwrap().push(event)),
            CancellationToken::new(),
        )
        .await;
        assert_eq!(
            result.unwrap_err(),
            if status.starts_with("401") {
                "assistant_authentication"
            } else {
                "assistant_http_client"
            }
        );
        assert!(!format!("{:?}", observed.lock().unwrap()).contains("secret-owner-key"));
    }
}

#[tokio::test]
async fn keyless_profiles_send_no_bearer_secret() {
    for provider in [Provider::OpenAiCompatible, Provider::OpenAiResponses] {
        let (base, request) = server("200 OK", "", &reply(provider));
        let mut configuration = config(provider, base);
        configuration.api_key.clear();
        let result = run(
            configuration,
            vec![],
            "Hi".into(),
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(result.text, "Hello");
        let request = request.recv_timeout(Duration::from_secs(2)).unwrap();
        let headers = request.split_once("\r\n\r\n").unwrap().0;
        let auth = headers.lines().find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("authorization")
                .then_some(value.trim())
        });
        assert_eq!(
            auth,
            if provider == Provider::OpenAiResponses {
                Some("")
            } else {
                None
            }
        );
        assert!(!headers.to_ascii_lowercase().contains("x-api-key:"));
        assert!(!headers.to_ascii_lowercase().contains("bearer"));
    }
}

#[tokio::test]
async fn image_only_turn_uses_native_wire_blocks_but_checkpoints_keep_no_image_bytes() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        let (base, request) = server("200 OK", "", &reply(provider));
        // Exceeds the text-context budget, but fits the independent image budget.
        let bytes = vec![0xAB; 128 * 1024];
        let encoded = STANDARD.encode(&bytes);
        let observed = Arc::new(std::sync::Mutex::new(Vec::<Event>::new()));
        let copy = observed.clone();
        let result = run_multimodal(
            config(provider, base),
            vec![],
            String::new(),
            vec![ImageInput {
                mime_type: "image/png".into(),
                data: bytes,
            }],
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(move |event| copy.lock().unwrap().push(event)),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(result.text, "Hello");
        let request = request.recv_timeout(Duration::from_secs(2)).unwrap();
        let body: Value = serde_json::from_str(request.split_once("\r\n\r\n").unwrap().1).unwrap();
        match provider {
            Provider::Anthropic => {
                let image = &body["messages"][0]["content"][0];
                assert_eq!(image["type"], "image");
                assert_eq!(image["source"]["media_type"], "image/png");
                assert_eq!(image["source"]["data"], encoded);
            }
            Provider::OpenAiCompatible => {
                let image = &body["messages"][1]["content"][0];
                assert_eq!(image["type"], "image_url");
                assert_eq!(
                    image["image_url"]["url"],
                    format!("data:image/png;base64,{encoded}")
                );
            }
            Provider::OpenAiResponses => {
                let input = body["input"].as_array().unwrap();
                let user = input.iter().find(|item| item["role"] == "user").unwrap();
                assert_eq!(user["content"][0]["type"], "input_image");
                assert_eq!(
                    user["content"][0]["image_url"],
                    format!("data:image/png;base64,{encoded}")
                );
            }
        }
        assert!(serde_json::to_vec(&result.history).unwrap().len() < 4096);
        for event in observed.lock().unwrap().iter() {
            if let Event::Checkpoint(history) = event {
                let text = serde_json::to_string(history).unwrap();
                assert!(!text.contains(&encoded));
                assert!(text.contains("omitted from saved model history"));
            }
        }
        let (base, request) = server("200 OK", "", &reply(provider));
        run_multimodal(
            config(provider, base),
            result.history,
            "Continue".into(),
            vec![],
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        let request = request.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(request.contains("Do not claim to inspect it"));
        assert!(!request.contains("data:image"));
        assert!(!request.contains(&encoded));
    }
}

#[tokio::test]
async fn malformed_or_excessive_images_are_rejected_before_network_io() {
    let small = ImageInput {
        mime_type: "image/jpeg".into(),
        data: vec![1],
    };
    for images in [
        vec![small.clone(); 5],
        vec![ImageInput {
            data: vec![1; 2 * 1024 * 1024 + 1],
            ..small.clone()
        }],
        vec![ImageInput {
            mime_type: "image/svg+xml".into(),
            ..small.clone()
        }],
        vec![ImageInput {
            data: vec![],
            ..small.clone()
        }],
    ] {
        let result = run_multimodal(
            config(Provider::OpenAiCompatible, "http://127.0.0.1:1".into()),
            vec![],
            "Inspect".into(),
            images,
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            CancellationToken::new(),
        )
        .await;
        assert_eq!(result.unwrap_err(), "assistant_image_limit");
    }
    let cancel = CancellationToken::new();
    cancel.cancel();
    let result = run_multimodal(
        config(Provider::OpenAiCompatible, "http://127.0.0.1:1".into()),
        vec![],
        String::new(),
        vec![small],
        vec![],
        Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
        Arc::new(|_| {}),
        cancel,
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_cancelled");
}

#[tokio::test]
async fn http_diagnostics_are_specific_and_never_persist_upstream_bodies() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        for (status, body, expected) in [
            (
                "401 Unauthorized",
                "secret-owner-key",
                "assistant_authentication",
            ),
            ("403 Forbidden", "secret-owner-key", "assistant_permission"),
            (
                "429 Too Many Requests",
                r#"{"error":{"code":"insufficient_quota","message":"secret-owner-key"}}"#,
                "assistant_quota",
            ),
            (
                "429 Too Many Requests",
                "secret-owner-key",
                "assistant_rate_limit",
            ),
            (
                "400 Bad Request",
                r#"{"error":{"message":"This model does not support image inputs secret-owner-key"}}"#,
                "assistant_image_unsupported",
            ),
            (
                "503 Unavailable",
                "secret-owner-key",
                "assistant_http_server",
            ),
        ] {
            let (base, _) = server(status, "", body);
            let observed = Arc::new(std::sync::Mutex::new(Vec::<Event>::new()));
            let copy = observed.clone();
            let result = run_multimodal(
                config(provider, base),
                vec![],
                "Inspect".into(),
                vec![],
                vec![],
                Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
                Arc::new(move |event| copy.lock().unwrap().push(event)),
                CancellationToken::new(),
            )
            .await;
            assert_eq!(result.unwrap_err(), expected, "{provider:?} {status}");
            let events = format!("{:?}", observed.lock().unwrap());
            assert!(!events.contains("secret-owner-key"));
            assert!(events.contains(expected));
        }
    }
}

#[tokio::test]
async fn empty_truncated_and_interrupted_responses_are_distinct() {
    let good = reply(Provider::OpenAiCompatible);
    for (body, expected) in [
        (good.replace("Hello", ""), "assistant_empty_response"),
        (
            good.replace("\"finish_reason\":\"stop\"", "\"finish_reason\":\"length\""),
            "assistant_output_truncated",
        ),
        (
            good.split("\n\n").next().unwrap().to_owned() + "\n\n",
            "assistant_stream_incomplete",
        ),
    ] {
        let (base, _) = server("200 OK", "", &body);
        let result = run(
            config(Provider::OpenAiCompatible, base),
            vec![],
            "Hi".into(),
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            CancellationToken::new(),
        )
        .await;
        assert_eq!(result.unwrap_err(), expected);
    }
}

#[tokio::test]
async fn cancelling_a_socket_without_response_headers_finishes_promptly() {
    for provider in [
        Provider::Anthropic,
        Provider::OpenAiCompatible,
        Provider::OpenAiResponses,
    ] {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (received_tx, received_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut bytes = [0; 4096];
            assert!(socket.read(&mut bytes).unwrap() > 0);
            received_tx.send(()).unwrap();
            let _ = release_rx.recv_timeout(Duration::from_secs(5));
        });
        let cancel = CancellationToken::new();
        let worker_cancel = cancel.clone();
        let task = tokio::spawn(run_multimodal(
            config(provider, format!("http://{address}/v1")),
            vec![],
            "Hi".into(),
            vec![],
            vec![],
            Arc::new(|_, _| async { Ok(json!({})) }.boxed()),
            Arc::new(|_| {}),
            worker_cancel,
        ));
        tokio::task::spawn_blocking(move || {
            received_rx.recv_timeout(Duration::from_secs(5)).unwrap()
        })
        .await
        .unwrap();
        cancel.cancel();
        let result = tokio::time::timeout(Duration::from_secs(2), task)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(result.unwrap_err(), "assistant_cancelled");
        release_tx.send(()).unwrap();
        server.join().unwrap();
    }
}
