//! Talking to the user's model: requests go through the platform's own
//! network stack (`fetch`), straight from this device to the account's base
//! URL. No relay, no fallback.

use std::time::Duration;

use nsh_core::prelude::*;

use super::meals::new_food_id;
use crate::domain::{
    VisionFailure,
    account::ModelAccount,
    recognition::{Lang, Recognition, parse_recognition},
    wire::{Ask, Stop, WireRequest, build_request, parse_reply, rejects_structured_output},
};

/// How long a recognition may take: thinking models can need a minute.
pub const RECOGNIZE_TIMEOUT: Duration = Duration::from_secs(150);
/// How long the connection test may take.
pub const PING_TIMEOUT: Duration = Duration::from_secs(60);

/// What the model recognized, and which model it was.
#[derive(Debug, Clone, PartialEq)]
pub struct Estimate {
    pub recognition: Recognition,
    pub model: String,
}

/// Asks `account` to recognize the meal in `jpeg`. A provider that refuses
/// the structured-answer option is asked once more without it.
pub async fn recognize(
    account: ModelAccount,
    jpeg: std::rc::Rc<Vec<u8>>,
    lang: Lang,
) -> Result<Estimate, VisionFailure> {
    let mut structured = true;
    loop {
        let request = build_request(&account, Ask::Meal { jpeg: &jpeg, lang }, structured);
        let response = send(request, RECOGNIZE_TIMEOUT).await?;
        let body = response.text();
        if structured && rejects_structured_output(response.status(), &body) {
            log::info!("vision: provider takes no structured output; asking again without it");
            structured = false;
            continue;
        }
        let reply = parse_reply(account.provider, response.status(), &body)
            .map_err(VisionFailure::Provider)?;
        match reply.stop {
            Stop::Truncated => return Err(VisionFailure::Truncated),
            Stop::Refused => return Err(VisionFailure::Refused),
            Stop::Complete => {}
        }
        let recognition = parse_recognition(&reply.text, &mut new_food_id)
            .map_err(|_| VisionFailure::Unreadable)?;
        return Ok(Estimate {
            recognition,
            model: reply
                .model
                .unwrap_or_else(|| account.model.trim().to_owned()),
        });
    }
}

/// The smallest request that proves `account` answers: the model that did,
/// and the seconds it took.
pub async fn ping(account: ModelAccount) -> Result<(String, f64), VisionFailure> {
    let started = nsh_core::time::now();
    let response = send(build_request(&account, Ask::Ping, false), PING_TIMEOUT).await?;
    let reply = parse_reply(account.provider, response.status(), &response.text())
        .map_err(VisionFailure::Provider)?;
    let seconds = started.elapsed().as_secs_f64();
    Ok((
        reply
            .model
            .unwrap_or_else(|| account.model.trim().to_owned()),
        seconds,
    ))
}

async fn send(request: WireRequest, limit: Duration) -> Result<HttpResponse, VisionFailure> {
    let mut http = HttpRequest::new("POST", request.url);
    for (name, value) in request.headers {
        http = http.header(name, value);
    }
    let http = http.body(request.body);
    let fetching = async { fetch(http).await.map_err(VisionFailure::Offline) };
    let waiting = async {
        timer(limit).await;
        Err(VisionFailure::Timeout)
    };
    futures_lite::future::or(fetching, waiting).await
}
