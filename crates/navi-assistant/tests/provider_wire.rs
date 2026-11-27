//! Real local HTTP fixtures: exercise the selected pi-rust provider rather
//! than a mocked host function, including account base-path normalization.
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{Arc, mpsc},
    time::Duration,
};

use futures::FutureExt;
use navi_assistant::{CancellationToken, Config, Event, Limits, Provider, run};
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
        assert_eq!(result.unwrap_err(), "assistant_provider");
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
