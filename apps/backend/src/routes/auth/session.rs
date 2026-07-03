use chrono::{DateTime, Duration, Utc};
use serde::Serialize;
use uuid::Uuid;
use worker::{D1Database, D1Type, Response, Result as WorkerResult, RouteContext};

use crate::auth::{
    jwt::{self, default_domains, Claims},
    middleware::jwt_secret,
    ACCESS_TOKEN_TTL_DAYS,
};
use crate::error::AppError;

use super::models::LoginResponse;

pub(super) fn db(ctx: &RouteContext<()>) -> Result<D1Database, AppError> {
    ctx.env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))
}

pub(super) fn into_response<T: Serialize>(result: Result<T, AppError>) -> WorkerResult<Response> {
    match result {
        Ok(body) => Response::from_json(&body),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

pub(super) fn issue_token(
    user_id: &str,
    device_id: &str,
    domains: Vec<String>,
    secret: &[u8],
    now: DateTime<Utc>,
) -> Result<(String, String, DateTime<Utc>), AppError> {
    let exp = now + Duration::days(ACCESS_TOKEN_TTL_DAYS);
    let jti = Uuid::new_v4().to_string();
    let claims = Claims {
        sub: user_id.to_string(),
        did: device_id.to_string(),
        jti: jti.clone(),
        iat: now.timestamp(),
        exp: exp.timestamp(),
        domains: normalise_domains(domains),
    };
    let token = jwt::encode(&claims, secret)?;
    Ok((token, jti, exp))
}

pub(super) fn normalise_domains(domains: Vec<String>) -> Vec<String> {
    let mut out = default_domains();
    for d in domains {
        match d.as_str() {
            "finance" | "health" | "knowledge" if !out.iter().any(|existing| existing == &d) => {
                out.push(d);
            }
            _ => {}
        }
    }
    out.sort();
    out
}

pub(super) async fn issue_session(
    user_id: String,
    domains: Vec<String>,
    device_name: Option<String>,
    requested_device_id: Option<String>,
    ctx: &RouteContext<()>,
    db: &D1Database,
) -> Result<LoginResponse, AppError> {
    let secret = jwt_secret(ctx)?;
    let now = Utc::now();
    let device_id = match requested_device_id.as_deref().map(str::trim) {
        Some(raw) if !raw.is_empty() => Uuid::parse_str(raw)
            .map_err(|_| AppError::BadRequest("device_id must be a UUID".into()))?
            .to_string(),
        _ => Uuid::new_v4().to_string(),
    };
    let (token, jti, exp) = issue_token(&user_id, &device_id, domains, secret.as_bytes(), now)?;

    let now_iso = now.to_rfc3339();
    let name_value = match device_name.as_deref().map(str::trim) {
        Some(s) if !s.is_empty() => D1Type::Text(s),
        _ => D1Type::Null,
    };
    db.prepare(
        "INSERT INTO devices (id, user_id, name, jti, created_at, last_seen_at, revoked_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?5, NULL) \
         ON CONFLICT(id) DO UPDATE SET \
             user_id = excluded.user_id, \
             name = excluded.name, \
             jti = excluded.jti, \
             last_seen_at = excluded.last_seen_at, \
             revoked_at = NULL",
    )
    .bind_refs([
        &D1Type::Text(&device_id),
        &D1Type::Text(&user_id),
        &name_value,
        &D1Type::Text(&jti),
        &D1Type::Text(&now_iso),
    ])
    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
    .run()
    .await
    .map_err(|e| AppError::Internal(format!("d1 run: {e}")))?;

    Ok(LoginResponse {
        access_token: token,
        token_type: "Bearer",
        expires_at: exp.to_rfc3339(),
        user_id,
        device_id,
    })
}
