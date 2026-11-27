//! Development HTTP relay: use the real provider codec with NSH's configured
//! headless network. It never decodes or manufactures model output.
use super::{CancelOnDrop, Progress, VisionFailure};
use futures::{channel::mpsc::UnboundedSender, channel::oneshot};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

pub(super) async fn relay(
    config: &mut navi_assistant::Config,
    send: UnboundedSender<Progress>,
) -> Result<CancelOnDrop, VisionFailure> {
    let failure = || VisionFailure::Offline("Host model transport unavailable".into());
    let base = url::Url::parse(&config.base_url).map_err(|_| failure())?;
    let origin = base[..url::Position::BeforePath].to_owned();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|_| failure())?;
    config.base_url = format!(
        "http://{}{}",
        listener.local_addr().map_err(|_| failure())?,
        base.path()
    );
    let task = tokio::spawn(async move {
        // Recognition performs exactly one request; no retry or redirects.
        let Ok((socket, _)) = listener.accept().await else {
            return;
        };
        let mut socket = BufReader::new(socket);
        let mut line = String::new();
        if socket.read_line(&mut line).await.is_err() {
            return;
        }
        let Some(path) = line.split_whitespace().nth(1) else {
            return;
        };
        if !path.starts_with('/') || path.starts_with("//") {
            return;
        }
        let mut request = nsh_core::platform::HttpRequest::new("POST", format!("{origin}{path}"));
        request.follow_redirects = false;
        let mut length = 0usize;
        let mut header_bytes = line.len();
        loop {
            line.clear();
            if socket.read_line(&mut line).await.is_err() {
                return;
            }
            header_bytes += line.len();
            if header_bytes > 32_768 || line.is_empty() {
                return;
            }
            if line == "\r\n" {
                break;
            }
            let Some((name, value)) = line.trim_end().split_once(':') else {
                return;
            };
            if name.eq_ignore_ascii_case("content-length") {
                let Ok(count) = value.trim().parse::<usize>() else {
                    return;
                };
                length = count;
            } else if !matches!(name.to_ascii_lowercase().as_str(), "host" | "connection") {
                request = request.header(name, value.trim());
            }
        }
        if length > 32 * 1024 * 1024 {
            return;
        }
        let mut body = vec![0; length];
        if socket.read_exact(&mut body).await.is_err() {
            return;
        }
        let (reply, receive) = oneshot::channel();
        if send
            .unbounded_send(Progress::Http {
                request: request.body(body),
                reply,
            })
            .is_err()
        {
            return;
        }
        let Ok(Ok(response)) = receive.await else {
            return;
        };
        let mut head = format!(
            "HTTP/1.1 {} Response\r\nConnection: close\r\nContent-Length: {}\r\n",
            response.status(),
            response.body.len()
        );
        for (name, value) in &response.head.headers {
            if !matches!(
                name.to_ascii_lowercase().as_str(),
                "content-length" | "connection" | "transfer-encoding"
            ) && !name.contains(['\r', '\n'])
                && !value.contains(['\r', '\n'])
            {
                head.push_str(&format!("{name}: {value}\r\n"));
            }
        }
        head.push_str("\r\n");
        if socket.write_all(head.as_bytes()).await.is_err() {
            return;
        }
        let _ = socket.write_all(&response.body).await;
        let _ = socket.shutdown().await;
    });
    Ok(CancelOnDrop(task.abort_handle()))
}
