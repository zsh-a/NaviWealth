use chrono::Utc;
use serde::Serialize;
use worker::{Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;
use crate::sync::state;

#[derive(Serialize)]
struct MeBody {
    user_id: String,
    server_now: String,
    server_hlc: String,
}

pub async fn get(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    match handle(req, ctx).await {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn handle(req: Request, ctx: RouteContext<()>) -> Result<Response, AppError> {
    check_protocol_version(req.headers())?;
    let auth = require_auth(&req, &ctx).await?;

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    let clock = state::load(&db, &auth.user_id).await?;
    let now_ms = Utc::now().timestamp_millis();
    // Surface the highest HLC the server would mint *now*; clone the state
    // so a probe doesn't burn server clock state.
    let mut probe = clock;
    let next = state::stamp(&mut probe, 0, now_ms);

    let body = MeBody {
        user_id: auth.user_id,
        server_now: Utc::now().to_rfc3339(),
        server_hlc: next.to_canonical(),
    };
    Response::from_json(&body).map_err(AppError::from)
}
