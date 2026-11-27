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
fn legacy_text_proposal_still_opens_as_an_unsent_draft_after_upgrade() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, storage) = start_in(Some(dir.path()), vec![], None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let legacy = json!({"id":"legacy-chat","title":"Lunch","created_at_ms":1,"updated_at_ms":2,
        "messages":[],"history":[],"status":"idle",
        "pending":[{"id":"legacy-proposal","kind":{"kind":"capture","text":"Lunch cost 20 CNY, paid in cash."}}]});
    db.execute(
        "INSERT INTO assistant_sessions(id,updated_at_ms,body) VALUES('legacy-chat',2,?1)",
        [legacy.to_string()],
    )
    .unwrap();
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("text:Assistant")?;
    app.press("text:Open record draft")?;
    settle();
    let drafts = records(dir.path(), "capture_drafts");
    assert_eq!(drafts.len(), 1);
    assert_eq!(drafts[0]["input"], "Lunch cost 20 CNY, paid in cash.");
    assert_eq!(drafts[0]["status"], "Editing");
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    Ok(())
}

#[test]
fn structured_records_survive_restart_then_edit_save_and_undo_without_recognition()
-> Result<(), String> {
    let mut money = money_record("35.00");
    money.as_object_mut().unwrap().remove("evidence");
    money["money"]["account"] = Value::Null;
    let mut meal = meal_record();
    meal.as_object_mut().unwrap().remove("evidence");
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-structured",
            "propose_record",
            json!({
                "text":"Lunch cost 35 CNY and I ate beef noodles with rice.",
                "records":[money,meal]
            }),
        ),
        Reply::Text("The records are ready to review."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("label:Assets")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Create account")?;
    app.wait_for("Account added")?;
    app.press("label:Today")?;
    app.press("text:Assistant")?;
    send(
        &mut app,
        "Record lunch 35 CNY and the noodles and rice I ate.",
    )?;
    app.wait_for("The records are ready to review.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let pending = records(dir.path(), "assistant_sessions")[0]["pending"].clone();
    assert_eq!(pending[0]["kind"]["kind"], "records");
    assert!(records(dir.path(), "capture_drafts").is_empty());
    assert!(stored_meals(dir.path()).is_empty());
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    app.wait_for("text:Review and edit")?;
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["pending"],
        pending
    );
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    // Opening a draft and consuming its proposal are one SQLite transaction.
    db.execute_batch("CREATE TRIGGER reject_confirmation BEFORE UPDATE ON assistant_sessions BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("text:Review and edit")?;
    settle();
    assert!(records(dir.path(), "capture_drafts").is_empty());
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["pending"],
        pending
    );
    db.execute_batch("DROP TRIGGER reject_confirmation")
        .unwrap();
    app.press("text:Review and edit")?;
    app.wait_for("Which account was used?")?;
    assert!(!app.shows("text:/^Confirm and save/"));
    assert_eq!(records(dir.path(), "capture_drafts").len(), 1);
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    app.press("label:Account, Choose account")?;
    app.press("label:Cash, Bank account · CNY")?;
    app.wait_for("label:Account, Cash")?;
    app.press("Edit amount")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "35.05")?;
    app.press("Done")?;
    app.wait_for("Confirm and save (2)")?;
    app.press("Confirm and save (2)")?;
    app.wait_for("Saved 2 records")?;
    let saved = navi_finance::repository::transactions(&db).unwrap();
    assert_eq!(saved.len(), 1);
    assert_eq!(
        saved[0].amount_in(&navi_finance::account::Account::parse("资产:Cash").unwrap()),
        -3505
    );
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert!(records(dir.path(), "capture_drafts").is_empty());
    app.press("Undo")?;
    app.wait_for("Save undone")?;
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    assert!(stored_meals(dir.path()).is_empty());
    assert_eq!(
        provider.requests().len(),
        2,
        "review, edit, save and Undo make no recognition request"
    );
    Ok(())
}

#[test]
fn aggregate_tools_continue_the_real_provider_loop_and_preserve_missing_data() -> Result<(), String>
{
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-finance",
            "summarize_finances",
            json!({"period":"month"}),
        ),
        Reply::Tool("call-health", "summarize_health", json!({"period":"week"})),
        Reply::Text("There are no logged observations for these periods."),
    ]);
    let (mut app, _) = start(provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Review my finances and health.")?;
    app.wait_for("There are no logged observations for these periods.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let requests = provider.requests();
    assert_eq!(requests.len(), 3);
    let tool_result = |id| -> Value {
        let message = requests[2]["messages"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["role"] == "tool" && m["tool_call_id"] == id)
            .unwrap();
        serde_json::from_str(message["content"].as_str().unwrap()).unwrap()
    };
    let finance = tool_result("call-finance");
    assert_eq!(finance["net_worth"]["status"], "no_records");
    assert_eq!(
        finance["currencies"][0]["spending"]["current_minor_units"],
        "0"
    );
    assert_eq!(
        finance["currencies"][0]["spending"]["comparison_available"],
        false
    );
    let health = tool_result("call-health");
    assert_eq!(health["current"]["nutrition"]["logged_days"], 0);
    assert!(health["current"]["nutrition"]["average_per_logged_day"].is_null());
    assert!(health["current"]["weight"]["trend_change_kg"].is_null());
    Ok(())
}

/// Grow a real provider-native transcript while the app is stopped. Display
/// messages stay short so this fixture measures context handling, not scrolling.
fn seed_long_history(dir: &Path) -> Vec<Value> {
    let mut session = records(dir, "assistant_sessions").remove(0);
    let pair = session["history"].as_array().unwrap().clone();
    assert_eq!(pair.len(), 2);
    let mut history = Vec::new();
    for index in 0..14 {
        let mut user = pair[0].clone();
        user["content"] = json!(format!(
            "Earlier turn {index}: travel choice is a red bicycle. {}",
            "past details ".repeat(800)
        ));
        history.push(user);
        history.push(pair[1].clone());
    }
    session["history"] = json!(history);
    session["context_summary"] = Value::Null;
    let db = rusqlite::Connection::open(database_in(dir)).unwrap();
    db.execute(
        "UPDATE assistant_sessions SET body=?1 WHERE id=?2",
        rusqlite::params![session.to_string(), session["id"].as_str().unwrap()],
    )
    .unwrap();
    history
}

#[test]
fn long_conversation_summary_survives_restart_without_replaying_or_resummarizing()
-> Result<(), String> {
    let provider = Provider::new(vec![
        Reply::Text("Initial conversation saved."),
        Reply::Text("The owner chose a red bicycle for travel. No record or memory was saved."),
        Reply::Text("We can continue using your earlier travel choice."),
        Reply::Text("Your earlier choice was a red bicycle."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries: Vec<_> = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries.clone(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Continue our travel plan.")?;
    app.wait_for("We can continue using your earlier travel choice.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let session = records(dir.path(), "assistant_sessions").remove(0);
    let summary = session["context_summary"].clone();
    assert!(summary["covered_messages"].as_u64().unwrap() > 0);
    assert!(summary["text"].as_str().unwrap().contains("red bicycle"));
    assert_eq!(
        &session["history"].as_array().unwrap()[..original.len()],
        original.as_slice()
    );
    assert!(session["pending"].as_array().unwrap().is_empty());
    assert!(records(dir.path(), "assistant_memories").is_empty());
    assert!(records(dir.path(), "capture_drafts").is_empty());
    let requests = provider.requests();
    assert_eq!(
        requests.len(),
        3,
        "one summary request followed by the actual answer"
    );
    assert!(
        requests[1]
            .get("tools")
            .is_none_or(|tools| tools.as_array().is_some_and(Vec::is_empty)),
        "summary calls cannot execute host tools"
    );
    assert!(requests[1]["messages"].to_string().contains("red bicycle"));
    assert!(requests[2]["messages"].as_array().unwrap().iter().any(|m| {
        m["role"] == "user"
            && m["content"]
                .to_string()
                .contains("No record or memory was saved")
    }));
    assert!(
        !requests[2]["messages"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["role"] == "system"
                && m["content"]
                    .to_string()
                    .contains("No record or memory was saved")),
        "summary text is not promoted to system instructions"
    );
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    settle();
    assert_eq!(
        provider.requests().len(),
        3,
        "startup neither summarizes nor replays tools"
    );
    send(&mut app, "What transport did I choose earlier?")?;
    app.wait_for("Your earlier choice was a red bicycle.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(
        provider.requests().len(),
        4,
        "saved summary is reused while recent context still fits"
    );
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["context_summary"],
        summary
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    Ok(())
}

#[test]
fn stopping_during_summary_does_not_publish_it_or_resume_it_after_restart() -> Result<(), String> {
    let provider = Provider::new(vec![
        Reply::Text("Initial conversation saved."),
        Reply::Wait,
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries: Vec<_> = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries.clone(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Continue our travel plan.")?;
    app.wait_for("Summarizing earlier conversation…")?;
    app.wait_until("summary request", GONE, |_| provider.requests().len() == 2)?;
    app.press("text:Stop")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let stopped = records(dir.path(), "assistant_sessions").remove(0);
    assert_eq!(stopped["status"], "interrupted");
    assert!(stopped["context_summary"].is_null());
    assert_eq!(
        &stopped["history"].as_array().unwrap()[..original.len()],
        original.as_slice()
    );
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    settle();
    assert_eq!(provider.requests().len(), 2);
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["status"],
        "interrupted"
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    Ok(())
}

#[test]
fn a_tool_call_in_a_summary_is_discarded_and_never_reaches_host_confirmation() -> Result<(), String>
{
    let provider = Provider::new(vec![
        Reply::Text("Initial conversation saved."),
        Reply::Tool(
            "forbidden-summary-tool",
            "propose_memory",
            json!({"text":"This must never become a proposal."}),
        ),
        Reply::Text("Continuing with the recent conversation."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("text:Assistant")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("text:Assistant")?;
    send(&mut app, "Continue our travel plan.")?;
    app.wait_for("Continuing with the recent conversation.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let kept = records(dir.path(), "assistant_sessions").remove(0);
    assert_eq!(kept["status"], "idle");
    assert!(kept["context_summary"].is_null());
    assert!(kept["pending"].as_array().unwrap().is_empty());
    assert!(!kept.to_string().contains("forbidden-summary-tool"));
    assert!(kept["messages"].as_array().unwrap().iter().any(|m| {
        m["text"]
            .as_str()
            .is_some_and(|text| text.contains("outside this request's context"))
    }));
    assert_eq!(
        &kept["history"].as_array().unwrap()[..original.len()],
        original.as_slice()
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    assert!(records(dir.path(), "capture_drafts").is_empty());
    assert_eq!(provider.requests().len(), 3);
    Ok(())
}
