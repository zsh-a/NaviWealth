//! Real provider SSE over loopback through the NSH UI and SQLite host tools.
//! No external model, search service, or model-side fake host is involved.
mod common;

use common::*;
use std::{
    collections::VecDeque,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::JoinHandle,
};

enum Reply {
    Tool(&'static str, &'static str, Value),
    Text(&'static str),
    /// Keep the model request outstanding while the user presses Stop.
    Wait,
}

struct Provider {
    base: String,
    requests: Arc<Mutex<Vec<Value>>>,
    stopped: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Provider {
    fn new(replies: Vec<Reply>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let base = format!("http://{}/v1", listener.local_addr().unwrap());
        let requests = Arc::new(Mutex::new(Vec::new()));
        let seen = requests.clone();
        let stopped = Arc::new(AtomicBool::new(false));
        let shutdown = stopped.clone();
        let worker = std::thread::spawn(move || {
            let mut replies: VecDeque<_> = replies.into();
            let mut held = Vec::new();
            while !shutdown.load(Ordering::SeqCst) {
                let (mut stream, _) = match listener.accept() {
                    Ok(stream) => stream,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(2));
                        continue;
                    }
                    Err(error) => panic!("fixture accept failed: {error}"),
                };
                stream
                    .set_read_timeout(Some(Duration::from_secs(3)))
                    .unwrap();
                let request = read_request(&mut stream);
                seen.lock().unwrap().push(request);
                let reply = replies.pop_front().expect("no unexpected model requests");
                if matches!(reply, Reply::Wait) {
                    // Keep accepting so an unexpected restart request is
                    // observable even while the previous reply is held open.
                    held.push(stream);
                    continue;
                }
                let body = sse(reply);
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                // Cancellation may close the socket between reading and reply.
                let _ = stream.write_all(response.as_bytes());
            }
        });
        Self {
            base,
            requests,
            stopped,
            worker: Some(worker),
        }
    }

    fn account(&self) -> Vec<(String, String)> {
        let fingerprint = json!(["openai", self.base, "assistant-fixture"]).to_string();
        vec![
            ("settings.v1".into(), json!({"account": {
                "provider":"open_ai_compatible", "base_url":self.base, "model":"assistant-fixture"
            }}).to_string()),
            ("secret.model-key.v1".into(), "synthetic-owner-key".into()),
            ("assistant.consent.v1".into(), json!([fingerprint]).to_string()),
        ]
    }

    fn requests(&self) -> Vec<Value> {
        self.requests.lock().unwrap().clone()
    }
}

impl Drop for Provider {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::SeqCst);
        if let Some(worker) = self.worker.take() {
            worker.join().expect("provider fixture did not panic");
        }
    }
}

fn read_request(stream: &mut TcpStream) -> Value {
    let mut bytes = Vec::new();
    let mut buffer = [0; 4096];
    loop {
        let count = stream.read(&mut buffer).unwrap();
        assert_ne!(count, 0, "complete HTTP request");
        bytes.extend_from_slice(&buffer[..count]);
        assert!(bytes.len() < 1_000_000);
        if let Some(end) = bytes.windows(4).position(|part| part == b"\r\n\r\n") {
            let headers = String::from_utf8_lossy(&bytes[..end]);
            assert!(headers.starts_with("POST /v1/chat/completions HTTP/1.1"));
            let length = headers
                .lines()
                .find_map(|line| {
                    let (key, value) = line.split_once(':')?;
                    key.eq_ignore_ascii_case("content-length")
                        .then(|| value.trim().parse::<usize>().unwrap())
                })
                .expect("JSON content length");
            if bytes.len() >= end + 4 + length {
                return serde_json::from_slice(&bytes[end + 4..end + 4 + length]).unwrap();
            }
        }
    }
}

fn sse(reply: Reply) -> String {
    let (delta, finish) = match reply {
        Reply::Tool(id, name, args) => (
            json!({"role":"assistant","tool_calls":[{
                "index":0,"id":id,"type":"function","function":{"name":name,"arguments":args.to_string()}
            }]}),
            "tool_calls",
        ),
        Reply::Text(text) => (json!({"role":"assistant","content":text}), "stop"),
        Reply::Wait => unreachable!(),
    };
    let chunk = |delta: Value, reason: Option<&str>| {
        json!({
            "id":"response-fixture","object":"chat.completion.chunk","model":"assistant-fixture",
            "choices":[{"index":0,"delta":delta,"finish_reason":reason}]
        })
    };
    format!(
        "data: {}\n\ndata: {}\n\ndata: [DONE]\n\n",
        chunk(delta, None),
        chunk(json!({}), Some(finish))
    )
}

fn records(dir: &Path, table: &str) -> Vec<Value> {
    let connection = rusqlite::Connection::open(database_in(dir)).unwrap();
    let mut query = connection
        .prepare(&format!("SELECT body FROM {table} ORDER BY id"))
        .unwrap();
    query
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .map(|body| serde_json::from_str(&body.unwrap()).unwrap())
        .collect()
}

fn settle() {
    // The engine and Tokio workers use real clocks on their own threads. Give
    // them a quiet interval to catch unexpected restart requests; wait_until
    // only rechecks its predicate on UI frames and a quiescent UI has none.
    std::thread::sleep(Duration::from_millis(100));
}

fn send(app: &mut Headless, text: &str) -> Result<(), String> {
    app.type_text("label:Message Assistant", text)?;
    app.press("label:Send message")
}

#[test]
fn confirmed_memory_is_recalled_by_a_new_conversation_after_restart() -> Result<(), String> {
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-save",
            "propose_memory",
            json!({"text":"Prefer vegetarian lunches."}),
        ),
        Reply::Text("Please review the memory suggestion."),
        Reply::Tool(
            "call-recall",
            "memory_search",
            json!({"query":"vegetarian"}),
        ),
        Reply::Text("Your saved preference is vegetarian lunches."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Remember that I prefer vegetarian lunches.")?;
    app.wait_for("Please review the memory suggestion.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert!(records(dir.path(), "assistant_memories").is_empty());
    let sessions = records(dir.path(), "assistant_sessions");
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0]["pending"].as_array().unwrap().len(), 1);
    assert_eq!(
        provider.requests().len(),
        2,
        "tool loop continued through real HTTP"
    );
    app.press("text:Save memory")?;
    app.wait_for("Proposal confirmed")?;
    let memories = records(dir.path(), "assistant_memories");
    assert_eq!(memories.len(), 1);
    assert_eq!(memories[0]["text"], "Prefer vegetarian lunches.");
    assert_eq!(memories[0]["source_session"], sessions[0]["id"]);
    let kept = records(dir.path(), "assistant_sessions");
    assert!(kept[0]["pending"].as_array().unwrap().is_empty());
    assert_eq!(kept[0]["action_outcomes"][0]["status"], "confirmed");
    assert!(!kept[0].to_string().contains("synthetic-owner-key"));
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    app.wait_for("Please review the memory suggestion.")?;
    settle();
    assert_eq!(
        provider.requests().len(),
        2,
        "restart does not replay completed work"
    );
    app.press("label:New conversation")?;
    send(&mut app, "What lunch preference did I save?")?;
    app.wait_for("Your saved preference is vegetarian lunches.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let requests = provider.requests();
    assert_eq!(requests.len(), 4);
    let tool_result = requests[3]["messages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|message| message["role"] == "tool")
        .expect("memory tool result");
    let content: Value = serde_json::from_str(tool_result["content"].as_str().unwrap()).unwrap();
    assert_eq!(content["memories"][0]["text"], "Prefer vegetarian lunches.");
    assert_eq!(records(dir.path(), "assistant_sessions").len(), 2);
    Ok(())
}

#[test]
fn cancelling_after_a_proposal_preserves_one_unapproved_action_across_restart() -> Result<(), String>
{
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-before-stop",
            "propose_memory",
            json!({"text":"Walk for short trips."}),
        ),
        Reply::Wait,
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Remember to walk for short trips.")?;
    app.wait_until("provider continuation", GONE, |_| {
        provider.requests().len() == 2
    })?;
    app.press("text:Stop")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let before = records(dir.path(), "assistant_sessions");
    assert_eq!(before[0]["status"], "interrupted");
    assert_eq!(before[0]["pending"].as_array().unwrap().len(), 1);
    assert!(records(dir.path(), "assistant_memories").is_empty());
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    app.wait_for("Walk for short trips.")?;
    settle();
    assert_eq!(provider.requests().len(), 2);
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["pending"],
        before[0]["pending"]
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    app.press("text:Save memory")?;
    app.wait_for("Proposal confirmed")?;
    assert_eq!(records(dir.path(), "assistant_memories").len(), 1);
    assert_eq!(
        provider.requests().len(),
        2,
        "confirmation itself makes no model call"
    );
    Ok(())
}

#[test]
fn a_record_tool_only_opens_an_unsent_capture_after_confirmation() -> Result<(), String> {
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-record",
            "propose_record",
            json!({"text":"Lunch cost 20 CNY, paid in cash."}),
        ),
        Reply::Text("Review the proposed record."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Record lunch for 20 CNY paid in cash.")?;
    app.wait_for("Review the proposed record.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert!(records(dir.path(), "capture_drafts").is_empty());
    app.press("text:Open record draft")?;
    settle();
    let drafts = records(dir.path(), "capture_drafts");
    assert_eq!(drafts.len(), 1);
    assert!(
        drafts[0]
            .to_string()
            .contains("Lunch cost 20 CNY, paid in cash.")
    );
    let connection = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM finance_transactions", [], |row| row
                .get::<_, i64>(
                0
            ))
            .unwrap(),
        0
    );
    assert_eq!(
        provider.requests().len(),
        2,
        "opening capture does not send recognition"
    );
    Ok(())
}
