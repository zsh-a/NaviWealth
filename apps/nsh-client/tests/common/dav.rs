//! A real, isolated HTTP WebDAV server for backup flows. No external
//! process, fixed port, live feature or personal account is required.

use std::{
    collections::BTreeMap,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::Duration,
};

#[derive(Clone, Debug)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub headers: String,
    pub body: Vec<u8>,
}

#[derive(Default)]
struct State {
    folder: bool,
    files: BTreeMap<String, Vec<u8>>,
    requests: Vec<Request>,
    status: Option<u16>,
    redirect: Option<String>,
}

pub struct Dav {
    pub url: String,
    state: Arc<Mutex<State>>,
    stopped: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Dav {
    pub fn new() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/dav/NaviWealth", listener.local_addr().unwrap());
        listener.set_nonblocking(true).unwrap();
        let state = Arc::new(Mutex::new(State::default()));
        let stopped = Arc::new(AtomicBool::new(false));
        let (shared, stop) = (state.clone(), stopped.clone());
        let worker = thread::spawn(move || {
            while !stop.load(Ordering::Relaxed) {
                if let Ok((mut stream, _)) = listener.accept() {
                    stream
                        .set_read_timeout(Some(Duration::from_secs(2)))
                        .unwrap();
                    if let Some(request) = read_request(&mut stream) {
                        let mut state = shared.lock().unwrap();
                        let (status, body) = respond(&mut state, &request);
                        state.requests.push(request);
                        let location = state
                            .redirect
                            .as_ref()
                            .map(|url| format!("Location: {url}\r\n"))
                            .unwrap_or_default();
                        let _ = write!(
                            stream,
                            "HTTP/1.1 {status} Result\r\nContent-Length: {}\r\n{location}Connection: close\r\n\r\n",
                            body.len()
                        );
                        let _ = stream.write_all(&body);
                    }
                } else {
                    thread::sleep(Duration::from_millis(5));
                }
            }
        });
        Self {
            url,
            state,
            stopped,
            worker: Some(worker),
        }
    }

    pub fn put(&self, name: &str, bytes: Vec<u8>) {
        let mut state = self.state.lock().unwrap();
        state.folder = true;
        state.files.insert(name.into(), bytes);
    }

    pub fn files(&self) -> BTreeMap<String, Vec<u8>> {
        self.state.lock().unwrap().files.clone()
    }
    pub fn requests(&self) -> Vec<Request> {
        self.state.lock().unwrap().requests.clone()
    }
    pub fn status(&self, status: u16) {
        self.state.lock().unwrap().status = Some(status);
    }
    pub fn redirect(&self, url: String) {
        let mut state = self.state.lock().unwrap();
        state.status = Some(302);
        state.redirect = Some(url);
    }
}

impl Drop for Dav {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Relaxed);
        self.worker.take().unwrap().join().unwrap();
    }
}

fn read_request(stream: &mut TcpStream) -> Option<Request> {
    let mut bytes = Vec::new();
    let mut buf = [0; 8192];
    let header_end = loop {
        let n = stream.read(&mut buf).ok()?;
        if n == 0 {
            return None;
        }
        bytes.extend_from_slice(&buf[..n]);
        if let Some(at) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
            break at + 4;
        }
    };
    let headers = String::from_utf8(bytes[..header_end].to_vec()).ok()?;
    let length: usize = headers
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse().ok())
                .flatten()
        })
        .unwrap_or(0);
    while bytes.len() < header_end + length {
        let n = stream.read(&mut buf).ok()?;
        if n == 0 {
            return None;
        }
        bytes.extend_from_slice(&buf[..n]);
    }
    let mut first = headers.lines().next()?.split_whitespace();
    Some(Request {
        method: first.next()?.into(),
        path: first.next()?.into(),
        body: bytes[header_end..header_end + length].to_vec(),
        headers,
    })
}

fn respond(state: &mut State, request: &Request) -> (u16, Vec<u8>) {
    if let Some(status) = state.status {
        return (status, vec![]);
    }
    if !request
        .headers
        .to_ascii_lowercase()
        .contains("authorization: basic dgvzdgvyonnly3jldc1wyxnz")
    {
        // Basic tester:secret-pass, compared without exposing any real key.
        return (401, vec![]);
    }
    let name = request.path.rsplit('/').next().unwrap_or_default();
    match request.method.as_str() {
        "MKCOL" => {
            state.folder = true;
            (201, vec![])
        }
        "PUT" if !state.folder => (409, vec![]),
        "PUT" if state.files.contains_key(name) => (412, vec![]),
        "PUT" => {
            state.files.insert(name.into(), request.body.clone());
            (201, vec![])
        }
        "PROPFIND" => {
            let responses: String = state
                .files
                .keys()
                .map(|name| {
                    format!("<d:response><d:href>/dav/NaviWealth/{name}</d:href></d:response>")
                })
                .collect();
            (
                207,
                format!("<d:multistatus xmlns:d=\"DAV:\">{responses}</d:multistatus>").into_bytes(),
            )
        }
        "GET" => state
            .files
            .get(name)
            .map(|b| (200, b.clone()))
            .unwrap_or((404, vec![])),
        _ => (405, vec![]),
    }
}
