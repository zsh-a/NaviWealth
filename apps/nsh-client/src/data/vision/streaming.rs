//! Deliver actual model output to the NSH owner. Only a provider terminal
//! event can produce a CaptureResponse; progress never touches storage.
use super::*;
use crate::domain::capture::{self, Draft, Record};
use futures::{StreamExt, channel::mpsc};
use std::sync::atomic::{AtomicBool, Ordering};

mod host;
static HOST_NETWORK: AtomicBool = AtomicBool::new(false);

/// Headless development seam. Requests still pass through the actual pi-rust
/// provider, with a loopback relay forwarding HTTP to the configured NSH host.
pub fn use_host_capture_transport() {
    HOST_NETWORK.store(true, Ordering::Relaxed);
}

fn network() -> Result<&'static tokio::runtime::Runtime, VisionFailure> {
    static NETWORK: OnceLock<Result<tokio::runtime::Runtime, VisionFailure>> = OnceLock::new();
    NETWORK
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(1)
                .enable_all()
                .build()
                .map_err(|_| VisionFailure::Offline("Model transport unavailable".into()))
        })
        .as_ref()
        .map_err(Clone::clone)
}

pub(super) enum Progress {
    Text(String),
    Http {
        request: nsh_core::platform::HttpRequest,
        reply: futures::channel::oneshot::Sender<Result<nsh_core::prelude::HttpResponse, ()>>,
    },
}

pub(super) async fn complete(
    account: ModelAccount,
    request: LlmRequest,
    timeout: Duration,
    mut on_text: impl FnMut(String),
) -> Result<runtime::LlmResponse, VisionFailure> {
    let mut config = configuration(&account, timeout);
    let use_host = HOST_NETWORK.load(Ordering::Relaxed);
    let (send, mut receive) = mpsc::unbounded();
    let worker = network()?.spawn(async move {
        let _relay = if use_host {
            Some(host::relay(&mut config, send.clone()).await?)
        } else {
            None
        };
        let cancel = navi_assistant::CancellationToken::new();
        let _cancel = cancel.clone().drop_guard();
        runtime::complete(&config, request, cancel, move |text| {
            let _ = send.unbounded_send(Progress::Text(text));
        })
        .await
        .map_err(llm_failure)
    });
    let _cancel = CancelOnDrop(worker.abort_handle());
    while let Some(progress) = receive.next().await {
        match progress {
            Progress::Text(text) => on_text(text),
            Progress::Http { request, reply } => {
                let response = match futures::future::select(
                    Box::pin(nsh_core::prelude::fetch(request)),
                    Box::pin(nsh_core::prelude::timer(timeout)),
                )
                .await
                {
                    futures::future::Either::Left((response, _)) => response.map_err(|_| ()),
                    futures::future::Either::Right(_) => return Err(VisionFailure::Timeout),
                };
                let _ = reply.send(response);
            }
        }
    }
    worker
        .await
        .map_err(|_| VisionFailure::Response(ResponseFailure::Worker))?
}

/// The future owns the model worker and cancels its request when the owner
/// leaves the draft or supersedes the pending recognition.
pub async fn recognize_record_stream(
    account: ModelAccount,
    draft: Draft,
    images: Vec<(String, Vec<u8>)>,
    lang: Lang,
    consent: Consent,
    context: serde_json::Value,
    mut on_preview: impl FnMut(Vec<Record>),
) -> Result<CaptureResponse, VisionFailure> {
    consent
        .check(&upload_target(&account))
        .map_err(|_| VisionFailure::Refused)?;
    let request = capture_request(&account, &draft, &images, lang, &context)?;
    let image_count = if draft.transcript.is_empty() {
        draft.staged_images().len()
    } else {
        draft.sent_images().len()
    };
    let format = request.response_schema.clone();
    let mut partial = RecordPrefix {
        image_count,
        ..RecordPrefix::default()
    };
    let response = complete(account, request, RECOGNIZE_TIMEOUT, |text| {
        partial.push(&text, &format, &mut on_preview);
    })
    .await?;
    capture_response(response, image_count)
}

pub(super) struct CancelOnDrop(tokio::task::AbortHandle);
impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

#[derive(Default)]
struct RecordPrefix {
    image_count: usize,
    text: String,
    depth: usize,
    quoted: bool,
    escaped: bool,
    shown: usize,
    unsupported: bool,
}

impl RecordPrefix {
    // At each complete direct child of the top-level records array, validate
    // the prefix as a standalone envelope. Braces in strings or nested food
    // objects never finish a record. Never repair a truncated final answer.
    fn push(
        &mut self,
        text: &str,
        format: &Option<serde_json::Value>,
        mut preview: impl FnMut(Vec<Record>),
    ) {
        if self.unsupported || self.text.len().saturating_add(text.len()) > 80_000 {
            self.unsupported = true;
            return;
        }
        let start = self.text.len();
        self.text.push_str(text);
        for (offset, byte) in text.bytes().enumerate() {
            if self.quoted {
                if self.escaped {
                    self.escaped = false;
                } else if byte == b'\\' {
                    self.escaped = true;
                } else if byte == b'"' {
                    self.quoted = false;
                }
                continue;
            }
            match byte {
                b'"' => self.quoted = true,
                b'[' | b'{' => self.depth += 1,
                b']' | b'}' => {
                    if self.depth == 0 {
                        self.unsupported = true;
                        return;
                    }
                    self.depth -= 1;
                    if byte == b'}' && self.depth == 2 && self.shown < 10 {
                        let prefix = format!("{}]}}", &self.text[..start + offset + 1]);
                        let Ok(mut envelope) = serde_json::from_str::<serde_json::Value>(&prefix)
                        else {
                            continue;
                        };
                        let Some(fields) = envelope.as_object_mut() else {
                            continue;
                        };
                        // The optional navigation destination may follow the array on the wire.
                        fields
                            .entry("destination")
                            .or_insert(serde_json::Value::Null);
                        let prefix = envelope.to_string();
                        if let Ok((records, _)) = capture::parse(&prefix)
                            && capture::valid_meal_image_numbers(&records, self.image_count)
                            && records.len() > self.shown
                            && runtime::structured_output_from_content(format, &prefix).is_ok()
                        {
                            self.shown = records.len();
                            preview(records);
                        }
                    }
                }
                _ => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::future::{Either, select};
    use std::{
        io::{BufRead, BufReader, Read, Write},
        net::TcpListener,
        sync::mpsc::sync_channel,
    };

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum End {
        Complete,
        Disconnect,
        Cancel,
    }

    // The server withholds the terminal response until the UI thread receives
    // record one. This catches buffered HTTP adapters and detached HTTP tasks.
    fn exchange(end: End, result_tool: bool) {
        let cancel = matches!(end, End::Cancel);
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut account = ModelAccount::new(Provider::OpenAiCompatible);
        account.base_url = format!("http://{}/v1", listener.local_addr().unwrap());
        account.model = "test-model".into();
        let (preview_tx, preview_rx) = sync_channel(1);
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut input = BufReader::new(&socket);
            let mut length = 0;
            for line in input.by_ref().lines() {
                let line = line.unwrap();
                if line.is_empty() {
                    break;
                }
                if let Some((name, count)) = line.split_once(':')
                    && name.eq_ignore_ascii_case("content-length")
                {
                    length = count.trim().parse().unwrap();
                }
            }
            let mut bytes = vec![0; length];
            input.read_exact(&mut bytes).unwrap();
            let wire: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(wire["stream"], true);
            assert_eq!(wire["tools"][0]["function"]["name"], "ask_user");
            let item = json!({"kind":"weight","day":"2026-11-21","weight_kg":74.2,"trade":null,"balance":null,
                "note":null,"price":null,"money":null,"meal":null,"slot":null,"evidence":[]});
            let prefix = format!("{{\"records\":[{item}");
            let delta = if result_tool {
                json!({"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"result-1","type":"function","function":{"name":"emit_result","arguments":prefix}}]}}]})
            } else {
                json!({"choices":[{"index":0,"delta":{"content":prefix}}]})
            };
            write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\ndata: {delta}\n\n").unwrap();
            socket.flush().unwrap();
            preview_rx
                .recv_timeout(Duration::from_secs(6))
                .expect("partial result while the response is still in flight");
            match end {
                End::Complete => {
                    let end = if result_tool {
                        json!({"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"] ,\"destination\":null}"}}]},"finish_reason":"tool_calls"}]})
                    } else {
                        json!({"choices":[{"index":0,"delta":{"content":"],\"destination\":null}"},"finish_reason":"stop"}]})
                    };
                    write!(socket, "data: {end}\n\ndata: [DONE]\n\n").unwrap();
                }
                End::Cancel => {
                    let read = socket.read(&mut [0]);
                    assert!(
                        matches!(read, Ok(0))
                            || read.is_err_and(
                                |error| error.kind() == std::io::ErrorKind::ConnectionReset
                            )
                    );
                }
                End::Disconnect => {}
            }
        });
        let mut draft = crate::data::capture::new();
        draft.input = "74.2 kg".into();
        let consent = Consent::approve(upload_target(&account), true).unwrap();
        let (cancel_tx, cancel_rx) = futures::channel::oneshot::channel();
        let mut cancel_tx = Some(cancel_tx);
        let seen = std::cell::Cell::new(0);
        let task = recognize_record_stream(
            account,
            draft,
            vec![],
            Lang::En,
            consent,
            json!({}),
            |record| {
                assert!(matches!(record.as_slice(), [Record::Weight { kg, .. }] if *kg == 74.2));
                seen.set(seen.get() + 1);
                preview_tx.send(()).unwrap();
                if cancel {
                    cancel_tx.take().unwrap().send(()).unwrap();
                }
            },
        );
        let result = futures::executor::block_on(select(Box::pin(task), cancel_rx));
        match result {
            Either::Left((Ok(CaptureResponse::Records { records, .. }), _))
                if end == End::Complete =>
            {
                assert_eq!(records.len(), 1)
            }
            Either::Left((Err(VisionFailure::Response(ResponseFailure::Stream)), _))
                if end == End::Disconnect => {}
            Either::Right((Ok(()), task)) if cancel => drop(task),
            _ => panic!("unexpected capture outcome"),
        }
        assert_eq!(seen.get(), 1);
        server.join().unwrap();
    }

    #[test]
    fn fragmented_json_previews_only_complete_schema_valid_records() {
        let format = Some(capture::result_schema());
        let first = json!({"kind":"note","day":"2026-11-21","weight_kg":null,
            "trade":null,"balance":null,"note":"转入 {旧} 账户 \"明天\"","price":null,
            "money":null,"meal":null,"slot":null,"evidence":[]});
        let mut second = first.clone();
        second["day"] = json!("2026-11-22");
        let payload = format!("{{\"destination\":null,\"records\":[{first},{second},");
        let mut sizes = Vec::new();
        let mut parser = RecordPrefix::default();
        for ch in payload.chars() {
            parser.push(&ch.to_string(), &format, |records| {
                sizes.push(records.len())
            });
        }
        assert_eq!(sizes, [1, 2]);
        second.as_object_mut().unwrap().remove("evidence");
        second["day"] = json!("2026-11-23");
        parser.push(&second.to_string(), &format, |records| {
            sizes.push(records.len())
        });
        assert_eq!(sizes, [1, 2]);
    }

    #[test]
    fn real_transport_previews_before_terminal_and_cancels_on_drop() {
        for end in [End::Complete, End::Disconnect, End::Cancel] {
            for result_tool in [false, true] {
                exchange(end, result_tool);
            }
        }
    }
}
