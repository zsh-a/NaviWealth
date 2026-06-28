//! `GET /me` — JWT check plus a cheap "is there anything new" probe
//! (docs/sync/sync-v2.md §5.2).

use chrono::Utc;
use serde::Serialize;
use worker::{Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;
use crate::sync::store;

#[derive(Serialize)]
struct MeBody {
    user_id: String,
    server_now: String,
    /// The server's current `MAX(seq)`. A client whose cursor already equals
    /// this can skip the next sync round trip.
    seq: i64,
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
    let seq = store::max_seq(&db, &auth.user_id).await?;

    let body = MeBody {
        user_id: auth.user_id,
        server_now: Utc::now().to_rfc3339(),
        seq,
    };
    Response::from_json(&body).map_err(AppError::from)
}
