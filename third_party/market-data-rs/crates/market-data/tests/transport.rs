use axum::{
    Router,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use market_data_rs::{
    transport::{HttpClient, HttpPolicy, HttpRequest, QuotaLimiter},
    *,
};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::time::Instant;

async fn server(router: Router) -> (String, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (format!("http://{address}/"), task)
}
fn policy() -> HttpPolicy {
    HttpPolicy {
        min_interval: Duration::ZERO,
        max_attempts: 2,
        circuit_failures: 5,
        ..Default::default()
    }
}

#[tokio::test]
async fn transient_http_failure_retries_but_400_does_not() {
    let calls = Arc::new(AtomicUsize::new(0));
    let c = calls.clone();
    let router = Router::new()
        .route(
            "/",
            get(move || {
                let c = c.clone();
                async move {
                    if c.fetch_add(1, Ordering::SeqCst) == 0 {
                        (StatusCode::SERVICE_UNAVAILABLE, "busy")
                    } else {
                        (StatusCode::OK, "ok")
                    }
                }
            }),
        )
        .route("/bad", get(|| async { StatusCode::BAD_REQUEST }));
    let (url, task) = server(router).await;
    let client = HttpClient::new().unwrap();
    client.register("quota", policy()).unwrap();
    assert_eq!(client.get("quota", &url, &[], &[]).await.unwrap(), b"ok");
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    assert_eq!(
        client
            .get("quota", &format!("{url}bad"), &[], &[])
            .await
            .unwrap_err()
            .kind,
        ErrorKind::Http
    );
    assert_eq!(client.stats().await["quota"].attempts, 3);
    task.abort();
}
#[tokio::test]
async fn shared_quota_spaces_parallel_calls() {
    let times = Arc::new(Mutex::new(Vec::new()));
    let t = times.clone();
    let (url, task) = server(Router::new().route(
        "/",
        get(move || {
            let t = t.clone();
            async move {
                t.lock().unwrap().push(Instant::now());
                "ok"
            }
        }),
    ))
    .await;
    let client = HttpClient::new().unwrap();
    client
        .register(
            "same-account",
            HttpPolicy {
                min_interval: Duration::from_millis(60),
                ..policy()
            },
        )
        .unwrap();
    let (a, b) = tokio::join!(
        client.get("same-account", &url, &[], &[]),
        client.get("same-account", &url, &[], &[])
    );
    assert!(a.is_ok() && b.is_ok());
    let times = times.lock().unwrap();
    assert!(times[1].duration_since(times[0]) >= Duration::from_millis(40));
    task.abort();
}
#[tokio::test]
async fn retry_after_is_honored() {
    let calls = Arc::new(AtomicUsize::new(0));
    let c = calls.clone();
    let (url, task) = server(Router::new().route(
        "/",
        get(move || {
            let c = c.clone();
            async move {
                if c.fetch_add(1, Ordering::SeqCst) == 0 {
                    (
                        StatusCode::TOO_MANY_REQUESTS,
                        [("retry-after", "1")],
                        "busy",
                    )
                        .into_response()
                } else {
                    "ok".into_response()
                }
            }
        }),
    ))
    .await;
    let client = HttpClient::new().unwrap();
    client.register("quota", policy()).unwrap();
    let start = Instant::now();
    assert_eq!(client.get("quota", &url, &[], &[]).await.unwrap(), b"ok");
    assert!(start.elapsed() >= Duration::from_millis(950));
    task.abort();
}
#[tokio::test]
async fn circuit_opens_then_recovers_after_probe() {
    let calls = Arc::new(AtomicUsize::new(0));
    let c = calls.clone();
    let (url, task) = server(Router::new().route(
        "/",
        get(move || {
            let c = c.clone();
            async move {
                if c.fetch_add(1, Ordering::SeqCst) == 0 {
                    StatusCode::SERVICE_UNAVAILABLE
                } else {
                    StatusCode::OK
                }
            }
        }),
    ))
    .await;
    let client = HttpClient::new().unwrap();
    client
        .register(
            "quota",
            HttpPolicy {
                circuit_failures: 1,
                circuit_cooldown: Duration::from_millis(40),
                ..policy()
            },
        )
        .unwrap();
    assert_eq!(
        client.get("quota", &url, &[], &[]).await.unwrap_err().kind,
        ErrorKind::Http
    );
    assert_eq!(
        client.get("quota", &url, &[], &[]).await.unwrap_err().kind,
        ErrorKind::CircuitOpen
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    tokio::time::sleep(Duration::from_millis(60)).await;
    assert!(client.get("quota", &url, &[], &[]).await.is_ok());
    assert!(client.get("quota", &url, &[], &[]).await.is_ok());
    task.abort();
}
#[tokio::test]
async fn body_limit_and_timeout_are_enforced() {
    let (url, task) = server(Router::new().route("/", get(|| async { "12345" })).route(
        "/slow",
        get(|| async {
            tokio::time::sleep(Duration::from_millis(100)).await;
            "ok"
        }),
    ))
    .await;
    let client = HttpClient::new().unwrap();
    client
        .register(
            "quota",
            HttpPolicy {
                max_body_bytes: 4,
                max_attempts: 1,
                timeout: Duration::from_millis(20),
                ..policy()
            },
        )
        .unwrap();
    assert_eq!(
        client.get("quota", &url, &[], &[]).await.unwrap_err().kind,
        ErrorKind::Parse
    );
    assert_eq!(
        client
            .get("quota", &format!("{url}slow"), &[], &[])
            .await
            .unwrap_err()
            .kind,
        ErrorKind::Timeout
    );
    task.abort();
}
struct Counter(AtomicUsize);
#[async_trait::async_trait]
impl QuotaLimiter for Counter {
    async fn acquire(&self, _: &str, cost: u32) -> Result<()> {
        self.0.fetch_add(cost as usize, Ordering::SeqCst);
        Ok(())
    }
}
#[tokio::test]
async fn unsafe_post_is_not_retried_and_external_limiter_accounts_cost() {
    let (url, task) =
        server(Router::new().route("/", post(|| async { StatusCode::SERVICE_UNAVAILABLE }))).await;
    let limiter = Arc::new(Counter(AtomicUsize::new(0)));
    let client = HttpClient::new().unwrap().with_limiter(limiter.clone());
    client.register("quota", policy()).unwrap();
    let mut request = HttpRequest::get(url);
    request.method = reqwest::Method::POST;
    request.retry_safe = false;
    request.cost = 3;
    assert!(client.send("quota", &request).await.is_err());
    assert_eq!(client.stats().await["quota"].attempts, 1);
    assert_eq!(limiter.0.load(Ordering::SeqCst), 3);
    task.abort();
}
#[test]
fn conflicting_shared_quota_configuration_is_rejected() {
    let client = HttpClient::new().unwrap();
    client.register("quota", policy()).unwrap();
    assert!(
        client
            .register(
                "quota",
                HttpPolicy {
                    max_concurrent: 10,
                    ..policy()
                }
            )
            .is_err()
    );
}

#[tokio::test]
async fn earlier_success_cannot_close_a_newly_opened_circuit() {
    let (url, task) = server(
        Router::new()
            .route(
                "/slow",
                get(|| async {
                    tokio::time::sleep(Duration::from_millis(80)).await;
                    StatusCode::OK
                }),
            )
            .route("/bad", get(|| async { StatusCode::SERVICE_UNAVAILABLE })),
    )
    .await;
    let client = Arc::new(HttpClient::new().unwrap());
    client
        .register(
            "quota",
            HttpPolicy {
                max_attempts: 1,
                circuit_failures: 1,
                ..policy()
            },
        )
        .unwrap();
    let c = client.clone();
    let slow_url = format!("{url}slow");
    let slow = tokio::spawn(async move { c.get("quota", &slow_url, &[], &[]).await });
    while client.stats().await["quota"].attempts == 0 {
        tokio::task::yield_now().await;
    }
    assert!(
        client
            .get("quota", &format!("{url}bad"), &[], &[])
            .await
            .is_err()
    );
    assert!(slow.await.unwrap().is_ok());
    assert_eq!(
        client
            .get("quota", &format!("{url}slow"), &[], &[])
            .await
            .unwrap_err()
            .kind,
        ErrorKind::CircuitOpen
    );
    task.abort();
}
