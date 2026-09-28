use anyhow::{Result, bail};
use futures::future::{AbortHandle, Abortable};
use market_data_rs::{
    Adjustment, Eastmoney, FetchOptions, HistoryRequest, MarketData, PriorityRouting,
    ServiceConfig, Sina, Symbol, Tencent,
    cache::NoCache,
    transport::{HttpClient, HttpPolicy},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, LazyLock, Mutex},
    time::Duration,
};
use tokio::sync::OnceCell;

static ENGINE: OnceCell<MarketData> = OnceCell::const_new();
static REQUESTS: LazyLock<Mutex<HashMap<String, AbortHandle>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Quote {
        symbol: Symbol,
    },
    History {
        symbol: Symbol,
        from: chrono::NaiveDate,
        to: chrono::NaiveDate,
    },
}

async fn engine() -> Result<&'static MarketData> {
    ENGINE
        .get_or_try_init(|| async {
            crate::android_tls::ensure_initialized()?;
            let client = reqwest::Client::builder()
                .user_agent("Mozilla/5.0 NaviWealth/market-data")
                .connect_timeout(Duration::from_secs(5))
                .redirect(reqwest::redirect::Policy::limited(3))
                .build()?;
            Ok(MarketData::builder()
                .register(Tencent)
                .register(Sina)
                .register(Eastmoney)
                .cache(Arc::new(NoCache))
                .http(Arc::new(HttpClient::with_client(client)))
                .config(ServiceConfig {
                    request_timeout: Duration::from_secs(25),
                    ..Default::default()
                })
                .routing(Arc::new(PriorityRouting {
                    quote_order: vec!["tencent".into(), "sina".into()],
                    history_order: vec!["tencent".into(), "eastmoney".into(), "sina".into()],
                }))
                .http_policy(
                    "eastmoney",
                    HttpPolicy {
                        max_attempts: 1,
                        ..Default::default()
                    },
                )
                .build()?)
        })
        .await
}

fn envelope<T: serde::Serialize>(value: market_data_rs::Result<T>) -> Value {
    match value {
        Ok(data) => json!({"version": 1, "ok": data}),
        Err(error) => json!({"version": 1, "error": error}),
    }
}

struct Registration(String);
impl Drop for Registration {
    fn drop(&mut self) {
        REQUESTS.lock().unwrap().remove(&self.0);
    }
}

pub(crate) async fn request(id: String, input: String) -> Result<String> {
    if id.is_empty() || id.len() > 128 || input.len() > 4096 {
        bail!("invalid market request size");
    }
    let req: Request = serde_json::from_str(&input)?;
    let (handle, registration) = AbortHandle::new_pair();
    {
        let mut requests = REQUESTS.lock().unwrap();
        if requests.contains_key(&id) || requests.len() >= 32 {
            bail!("duplicate request or market concurrency limit reached");
        }
        requests.insert(id.clone(), handle);
    }
    let _guard = Registration(id);
    let work = async {
        let engine = engine().await?;
        let options = FetchOptions::default();
        let result = match req {
            Request::Quote { symbol } => envelope(engine.quote(symbol, options).await),
            Request::History { symbol, from, to } => envelope(
                engine
                    .history(
                        HistoryRequest {
                            symbol,
                            from,
                            to,
                            adjustment: Adjustment::Raw,
                            allow_partial: false,
                        },
                        options,
                    )
                    .await,
            ),
        };
        Ok::<_, anyhow::Error>(result.to_string())
    };
    Abortable::new(work, registration).await?
}

pub(crate) fn cancel(id: &str) {
    if let Some(handle) = REQUESTS.lock().unwrap().get(id) {
        handle.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_contract_preserves_errors_and_rejects_adjusted_requests() {
        let error = market_data_rs::Error::new(market_data_rs::ErrorKind::Incomplete, "gap");
        let result = envelope::<Value>(Err(error));
        assert_eq!(result["version"], 1);
        assert_eq!(result["error"]["kind"], "incomplete");
        assert!(serde_json::from_str::<Request>(r#"{"operation":"history","symbol":"600519","from":"2026-08-01","to":"2026-09-01","adjustment":"forward"}"#).is_err());
    }
}
