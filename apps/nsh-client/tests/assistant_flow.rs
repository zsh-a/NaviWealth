//! Real provider SSE over loopback through the NSH UI and SQLite host tools.
//! No external model, search service, or model-side fake host is involved.
mod common;

use common::*;
use std::{
    collections::VecDeque,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Condvar, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::JoinHandle,
};

enum Reply {
    Tool(&'static str, &'static str, Value),
    Text(&'static str),
    Revise(Value),
    ReviseAndRead(Value),
    Batch(Vec<(&'static str, &'static str, Value)>),
    /// Keep the model request outstanding while the user presses Stop.
    Wait,
}

struct Provider {
    base: String,
    requests: Arc<Mutex<Vec<Value>>>,
    received: Arc<Condvar>,
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
        let received = Arc::new(Condvar::new());
        let notify = received.clone();
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
                seen.lock().unwrap().push(request.clone());
                notify.notify_all();
                let reply = replies.pop_front().expect("no unexpected model requests");
                if matches!(reply, Reply::Wait) {
                    // Keep accepting so an unexpected restart request is
                    // observable even while the previous reply is held open.
                    held.push(stream);
                    continue;
                }
                let batch = matches!(&reply, Reply::ReviseAndRead(_));
                let reply = match reply {
                    Reply::Revise(proposal) | Reply::ReviseAndRead(proposal) => {
                        let system = request["messages"][0]["content"].as_str().unwrap();
                        let context = system
                            .lines()
                            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
                            .find(|value| value.get("pending_record_drafts").is_some())
                            .unwrap();
                        let args = json!({"capture_id":context["pending_record_drafts"][0]["capture_id"],"proposal":proposal});
                        if batch {
                            Reply::Batch(vec![
                                ("call-revise", "revise_record", args),
                                ("call-read", "read_records", json!({"kind":"weights"})),
                            ])
                        } else {
                            Reply::Tool("call-revise", "revise_record", args)
                        }
                    }
                    other => other,
                };
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
            received,
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
            ("assistant.consent.v2".into(), json!([fingerprint]).to_string()),
        ]
    }

    fn requests(&self) -> Vec<Value> {
        self.requests.lock().unwrap().clone()
    }

    fn wait_for_requests(&self, count: usize) -> Result<(), String> {
        // HTTP arrival does not schedule a UI frame. Wait on the fixture's own
        // notification so a held response can reliably be stopped by the UI.
        let (requests, _) = self
            .received
            .wait_timeout_while(self.requests.lock().unwrap(), GONE, |seen| {
                seen.len() < count
            })
            .unwrap();
        if requests.len() == count {
            Ok(())
        } else {
            Err(format!(
                "Expected {count} model requests, received {}",
                requests.len()
            ))
        }
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
        Reply::Batch(calls) => (
            json!({"role":"assistant","tool_calls":calls.into_iter().enumerate().map(|(index,(id,name,args))|json!({"index":index,"id":id,"type":"function","function":{"name":name,"arguments":args.to_string()}})).collect::<Vec<_>>()}),
            "tool_calls",
        ),
        Reply::Wait | Reply::Revise(_) | Reply::ReviseAndRead(_) => unreachable!(),
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
    app.type_text("label:Message", text)?;
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
    app.press("label:Conversation")?;
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
    app.wait_for("Memory saved")?;
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
    app.press("label:Conversation")?;
    app.wait_for("Please review the memory suggestion.")?;
    settle();
    assert_eq!(
        provider.requests().len(),
        2,
        "restart does not replay completed work"
    );
    app.press("text:New conversation")?;
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
    app.press("label:Conversation")?;
    send(&mut app, "Remember to walk for short trips.")?;
    provider.wait_for_requests(2)?;
    app.press("text:Stop")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let before = records(dir.path(), "assistant_sessions");
    assert_eq!(before[0]["status"], "interrupted");
    assert_eq!(before[0]["pending"].as_array().unwrap().len(), 1);
    assert!(records(dir.path(), "assistant_memories").is_empty());
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
    app.wait_for("Walk for short trips.")?;
    settle();
    assert_eq!(provider.requests().len(), 2);
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["pending"],
        before[0]["pending"]
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    app.press("text:Save memory")?;
    app.wait_for("Memory saved")?;
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
    app.press("label:Conversation")?;
    app.press("text:Open record draft")?;
    settle();
    assert!(records(dir.path(), "capture_drafts").is_empty());
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["composer"],
        "Lunch cost 20 CNY, paid in cash."
    );
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
                "text":"Lunch cost 35 CNY and I ate beef noodles with rice.","records":[money,meal]
            }),
        ),
        Reply::Text("This draft is still pending; we can keep talking."),
        Reply::Text("The meal and payment were saved."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("label:Assets")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Create account")?;
    app.wait_for("Account added")?;
    app.press("label:Conversation")?;
    send(
        &mut app,
        "Record lunch 35 CNY and the noodles and rice I ate.",
    )?;
    app.wait_for("Review before saving")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(
        provider.requests().len(),
        1,
        "record card ends this model turn"
    );
    let draft = records(dir.path(), "capture_drafts")[0].clone();
    assert!(stored_meals(dir.path()).is_empty());
    send(&mut app, "Can we keep talking while I check this?")?;
    app.wait_for("This draft is still pending; we can keep talking.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(records(dir.path(), "capture_drafts")[0], draft);
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
    app.wait_for("Which account was used?")?;
    assert_eq!(provider.requests().len(), 2, "restart does not replay work");
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    app.press("label:Account, Choose account")?;
    app.press("label:Cash, Bank account · CNY")?;
    app.wait_for("label:Account, Cash")?;
    app.press("Edit amount")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "35.05")?;
    app.press("Done")?;
    // The business write and conversation receipt must roll back together.
    db.execute_batch("CREATE TRIGGER reject_confirmation BEFORE UPDATE ON assistant_sessions BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("text:Confirm and save")?;
    settle();
    assert!(stored_meals(dir.path()).is_empty());
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    assert_eq!(records(dir.path(), "capture_drafts").len(), 1);
    db.execute_batch("DROP TRIGGER reject_confirmation")
        .unwrap();
    app.press("text:Confirm and save")?;
    app.wait_for("Saved 2 records")?;
    let saved = navi_finance::repository::transactions(&db).unwrap();
    assert_eq!(saved.len(), 1);
    assert_eq!(
        saved[0].amount_in(&navi_finance::account::Account::parse("资产:Cash").unwrap()),
        -3505
    );
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert!(records(dir.path(), "capture_drafts").is_empty());
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["record_actions"][0]["status"],
        "saved"
    );
    send(&mut app, "Did I save these records?")?;
    app.wait_for("The meal and payment were saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert!(
        provider.requests()[2]["messages"][0]["content"]
            .as_str()
            .unwrap()
            .contains("record_actions")
    );
    app.press("text:Undo")?;
    app.wait_for("Save undone")?;
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    assert!(stored_meals(dir.path()).is_empty());
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["record_actions"][0]["status"],
        "undone"
    );
    assert_eq!(
        provider.requests().len(),
        3,
        "review, edit, save and Undo make no model request"
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
    app.press("label:Conversation")?;
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
    for index in 0..12 {
        let mut user = pair[0].clone();
        user["content"] = json!(format!(
            "Earlier turn {index}: travel choice is a red bicycle. {}",
            "past details ".repeat(700)
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
    app.press("label:Conversation")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries: Vec<_> = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries.clone(), None);
    app.press("label:Conversation")?;
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
    app.press("label:Conversation")?;
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
        Reply::Text("Earlier travel plans kept intact."),
        Reply::Text("Continued after your explicit retry."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    app.press("label:Conversation")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries: Vec<_> = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries.clone(), None);
    app.press("label:Conversation")?;
    send(&mut app, "Continue our travel plan.")?;
    app.wait_for("Summarizing earlier conversation…")?;
    provider.wait_for_requests(2)?;
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
    app.press("label:Conversation")?;
    settle();
    assert_eq!(provider.requests().len(), 2);
    assert_eq!(
        records(dir.path(), "assistant_sessions")[0]["status"],
        "interrupted"
    );
    assert!(records(dir.path(), "assistant_memories").is_empty());
    app.press("text:Retry")?;
    app.wait_for("Continued after your explicit retry.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let retried = records(dir.path(), "assistant_sessions").remove(0);
    assert_eq!(
        &retried["history"].as_array().unwrap()[..original.len()],
        original.as_slice(),
        "summary cancellation did not append a user turn, so retry must not truncate the last completed turn"
    );
    assert_eq!(provider.requests().len(), 4);
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
    app.press("label:Conversation")?;
    send(&mut app, "Start a conversation about travel.")?;
    app.wait_for("Initial conversation saved.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let original = seed_long_history(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
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

#[test]
fn image_questions_restart_revision_and_receipt_share_one_conversation() -> Result<(), String> {
    let mut meal = meal_record();
    meal.as_object_mut().unwrap().remove("evidence");
    meal["meal"]["source_image"] = json!(1);
    let mut revised = meal.clone();
    revised["meal"]["foods"][0]["name"] = json!("Half portion noodles");
    let provider = Provider::new(vec![
        Reply::Tool(
            "call-question",
            "ask_user",
            json!({"questions":[{
                "id":"portion","text":"Did you eat the whole portion?","reason":"This changes the estimated amount.","required":true,
                "options":[{"id":"half","label":"Half the portion","description":"About half was eaten"},{"id":"all","label":"All of it","description":"The whole meal"}]
            }]}),
        ),
        Reply::Tool(
            "call-photo",
            "propose_record",
            json!({"text":"Meal estimated from your photo.","records":[meal]}),
        ),
        Reply::Revise(json!({"text":"Updated the portion in your draft.","records":[revised]})),
        Reply::Text("You can continue this conversation after saving."),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), provider.account(), None);
    picks_a_photo(&mut app);
    app.press("label:Conversation")?;
    app.press("label:Attach or add manually")?;
    app.press("text:Add photos")?;
    app.wait_for("label:Remove photo")?;
    app.press("label:Send message")?;
    app.wait_for("Did you eat the whole portion?")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(provider.requests().len(), 1);
    app.press("label:Half the portion")?;
    let before = records(dir.path(), "assistant_sessions")[0].clone();
    assert_eq!(
        before["pending"][0]["kind"]["answers"][0]["option_id"],
        "half"
    );
    assert!(
        !before["history"].to_string().contains("base64"),
        "provider history must not persist encoded images"
    );
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
    app.wait_for("Did you eat the whole portion?")?;
    app.press("text:Continue")?;
    app.wait_for("Review before saving")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(provider.requests().len(), 2);
    let second = provider.requests()[1].clone();
    assert!(
        second["messages"]
            .as_array()
            .unwrap()
            .iter()
            .any(|message| message["role"] == "user"
                && message["content"].to_string().contains("image_url"))
    );
    assert!(second["messages"].to_string().contains("Half the portion"));
    let first_draft = records(dir.path(), "capture_drafts")[0].clone();
    assert!(
        !first_draft["transcript"][0]["Owner"]["images"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    send(
        &mut app,
        "Actually the noodles were half a portion; correct that card.",
    )?;
    app.wait_for("Half portion noodles")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let updated = records(dir.path(), "capture_drafts");
    assert_eq!(updated.len(), 1);
    assert_eq!(updated[0]["id"], first_draft["id"]);
    app.press("text:Confirm and save")?;
    app.wait_for("Saved 1 record")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    send(&mut app, "Thanks, can we continue?")?;
    app.wait_for("You can continue this conversation after saving.")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(records(dir.path(), "assistant_sessions").len(), 1);
    assert_eq!(provider.requests().len(), 4);
    assert!(
        !provider.requests()[3]["messages"]
            .to_string()
            .contains("image_url"),
        "automatically carried images do not turn every future message into another image upload"
    );
    Ok(())
}

#[test]
fn image_only_interruption_retries_one_user_turn_and_creates_one_card() -> Result<(), String> {
    let mut meal = meal_record();
    meal.as_object_mut().unwrap().remove("evidence");
    meal["meal"]["source_image"] = json!(1);
    let provider = Provider::new(vec![
        Reply::Wait,
        Reply::Tool(
            "call-retry",
            "propose_record",
            json!({"text":"Your meal draft is ready.","records":[meal]}),
        ),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), provider.account(), None);
    picks_a_photo(&mut app);
    app.press("label:Conversation")?;
    app.press("label:Attach or add manually")?;
    app.press("text:Add photos")?;
    app.wait_for("label:Remove photo")?;
    app.press("label:Send message")?;
    provider.wait_for_requests(1)?;
    app.press("text:Stop")?;
    app.wait_for_gone("text:Stop", GONE)?;
    app.press("text:Retry")?;
    app.wait_for("Review before saving")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let requests = provider.requests();
    assert_eq!(requests.len(), 2);
    let users = |request: &Value| {
        request["messages"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|m| m["role"] == "user")
            .cloned()
            .collect::<Vec<_>>()
    };
    assert_eq!(
        users(&requests[0]),
        users(&requests[1]),
        "retry preserves the exact photo turn without duplicating it"
    );
    assert_eq!(records(dir.path(), "capture_drafts").len(), 1);
    assert!(stored_meals(dir.path()).is_empty());
    let session = records(dir.path(), "assistant_sessions").remove(0);
    assert_eq!(
        session["messages"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|m| m["role"] == "user")
            .count(),
        1
    );
    app.press("text:Confirm and save")?;
    app.wait_for("Saved 1 record")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn retry_after_applied_revision_does_not_apply_a_relative_correction_twice() -> Result<(), String> {
    let proposal = |kg: f64| json!({"text":"Weight draft updated.","records":[{"kind":"weight","day":today().to_string(),"weight_kg":kg,"money":null,"meal":null,"slot":null,"trade":null,"balance":null,"price":null,"note":null}]});
    let provider = Provider::new(vec![
        Reply::Tool("call-create", "propose_record", proposal(80.0)),
        Reply::ReviseAndRead(proposal(40.0)),
        Reply::Wait,
        Reply::Revise(proposal(20.0)),
    ]);
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), provider.account(), None);
    app.press("label:Conversation")?;
    send(&mut app, "Record weight 80 kg")?;
    app.wait_for("Review before saving")?;
    app.wait_for_gone("text:Stop", GONE)?;
    send(&mut app, "Actually halve that number")?;
    provider.wait_for_requests(3)?;
    app.press("text:Stop")?;
    app.wait_for_gone("text:Stop", GONE)?;
    let applied = records(dir.path(), "capture_drafts")[0].clone();
    assert_eq!(applied["records"][0]["Weight"]["kg"], 40.0);
    app.press("text:Retry")?;
    app.wait_for_gone("text:Stop", GONE)?;
    assert_eq!(
        records(dir.path(), "capture_drafts"),
        vec![applied],
        "same owner message must never halve the draft a second time"
    );
    assert_eq!(provider.requests().len(), 4);
    Ok(())
}
