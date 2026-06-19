use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use worker::{D1Database, D1Type, Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::{
    jwt::{self, default_domains, Claims},
    middleware::{jwt_secret, require_auth},
    password, AuthContext, ACCESS_TOKEN_TTL_DAYS,
};
use crate::error::AppError;

#[derive(Deserialize)]
struct AuthRequest {
    email: String,
    password: String,
    domains: Vec<String>,
    #[serde(default)]
    device_name: Option<String>,
    #[serde(default)]
    device_id: Option<String>,
}

#[derive(Deserialize)]
struct RefreshRequest {
    domains: Vec<String>,
}

#[derive(Serialize)]
struct LoginResponse {
    access_token: String,
    token_type: &'static str,
    expires_at: String,
    user_id: String,
    device_id: String,
}

#[derive(Deserialize)]
struct UserRow {
    id: String,
    password_hash: String,
}

#[derive(Deserialize)]
struct ExistingUserRow {
    id: String,
}

#[derive(Deserialize, Serialize)]
struct DeviceRow {
    id: String,
    name: Option<String>,
    created_at: String,
    last_seen_at: String,
}

#[derive(Serialize)]
struct DevicesResponse {
    devices: Vec<DeviceRow>,
    current_device_id: String,
}

#[derive(Serialize)]
struct OkResponse {
    ok: bool,
}

#[derive(Serialize)]
struct RefreshResponse {
    access_token: String,
    token_type: &'static str,
    expires_at: String,
}

fn db(ctx: &RouteContext<()>) -> Result<D1Database, AppError> {
    ctx.env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))
}

fn into_response<T: Serialize>(result: Result<T, AppError>) -> WorkerResult<Response> {
    match result {
        Ok(body) => Response::from_json(&body),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

fn issue_token(
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

fn normalise_domains(domains: Vec<String>) -> Vec<String> {
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

pub async fn login(mut req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let body: AuthRequest = match req.json().await {
        Ok(b) => b,
        Err(_) => return AppError::BadRequest("invalid JSON body".into()).into_response(),
    };
    into_response(login_inner(body, &ctx).await)
}

async fn login_inner(body: AuthRequest, ctx: &RouteContext<()>) -> Result<LoginResponse, AppError> {
    if body.email.is_empty() || body.password.is_empty() {
        return Err(AppError::BadRequest("email and password required".into()));
    }
    let email_norm = body.email.trim().to_ascii_lowercase();

    let db = db(ctx)?;
    let user: Option<UserRow> = db
        .prepare("SELECT id, password_hash FROM users WHERE email = ?1")
        .bind_refs([&D1Type::Text(&email_norm)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;

    // Always burn the argon2 cost even when the email misses, so an attacker
    // can't tell "no such email" from "wrong password" from request timing.
    let user_id = match user {
        Some(u) if password::verify(&body.password, &u.password_hash) => u.id,
        Some(_) => return Err(AppError::Unauthorized),
        None => {
            let _ = password::hash(&body.password);
            return Err(AppError::Unauthorized);
        }
    };

    issue_session(
        user_id,
        body.domains,
        body.device_name,
        body.device_id,
        ctx,
        &db,
    )
    .await
}

pub async fn register(mut req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let body: AuthRequest = match req.json().await {
        Ok(b) => b,
        Err(_) => return AppError::BadRequest("invalid JSON body".into()).into_response(),
    };
    into_response(register_inner(body, &ctx).await)
}

async fn register_inner(
    body: AuthRequest,
    ctx: &RouteContext<()>,
) -> Result<LoginResponse, AppError> {
    if body.email.is_empty() || body.password.is_empty() {
        return Err(AppError::BadRequest("email and password required".into()));
    }
    if body.password.len() < 8 {
        return Err(AppError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    let email_norm = body.email.trim().to_ascii_lowercase();
    if !email_norm.contains('@') {
        return Err(AppError::BadRequest("email must be valid".into()));
    }

    let db = db(ctx)?;
    let existing: Option<ExistingUserRow> = db
        .prepare("SELECT id FROM users LIMIT 1")
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;
    if let Some(row) = existing {
        worker::console_log!("registration_rejected_existing_user id={}", row.id);
        return Err(AppError::coded(
            409,
            "registration_closed",
            "registration is already complete",
        ));
    }

    let user_id = Uuid::new_v4().to_string();
    let password_hash = password::hash(&body.password)?;
    db.prepare("INSERT INTO users (id, email, password_hash) VALUES (?1, ?2, ?3)")
        .bind_refs([
            &D1Type::Text(&user_id),
            &D1Type::Text(&email_norm),
            &D1Type::Text(&password_hash),
        ])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .run()
        .await
        .map_err(|e| {
            let msg = e.to_string();
            if msg.contains("UNIQUE") || msg.contains("constraint") {
                AppError::coded(
                    409,
                    "registration_closed",
                    "registration is already complete",
                )
            } else {
                AppError::Internal(format!("d1 run: {e}"))
            }
        })?;

    issue_session(
        user_id,
        body.domains,
        body.device_name,
        body.device_id,
        ctx,
        &db,
    )
    .await
}

async fn issue_session(
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

pub async fn list_devices(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let auth = match require_auth(&req, &ctx).await {
        Ok(a) => a,
        Err(e) => {
            e.log();
            return e.into_response();
        }
    };
    into_response(list_devices_inner(auth, &ctx).await)
}

async fn list_devices_inner(
    auth: AuthContext,
    ctx: &RouteContext<()>,
) -> Result<DevicesResponse, AppError> {
    let db = db(ctx)?;
    let result = db
        .prepare(
            "SELECT id, name, created_at, last_seen_at \
             FROM devices \
             WHERE user_id = ?1 AND revoked_at IS NULL \
             ORDER BY created_at ASC",
        )
        .bind_refs([&D1Type::Text(&auth.user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("d1 all: {e}")))?;

    let devices: Vec<DeviceRow> = result
        .results()
        .map_err(|e| AppError::Internal(format!("d1 results: {e}")))?;

    Ok(DevicesResponse {
        devices,
        current_device_id: auth.device_id,
    })
}

pub async fn logout(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let auth = match require_auth(&req, &ctx).await {
        Ok(a) => a,
        Err(e) => {
            e.log();
            return e.into_response();
        }
    };
    let target_id = match ctx.param("device_id").cloned() {
        Some(s) if !s.is_empty() => s,
        _ => return AppError::BadRequest("device_id required".into()).into_response(),
    };
    into_response(logout_inner(auth, target_id, &ctx).await)
}

async fn logout_inner(
    auth: AuthContext,
    target_device_id: String,
    ctx: &RouteContext<()>,
) -> Result<OkResponse, AppError> {
    let db = db(ctx)?;
    let now_iso = Utc::now().to_rfc3339();
    let result = db
        .prepare(
            "UPDATE devices SET revoked_at = ?1 \
             WHERE id = ?2 AND user_id = ?3 AND revoked_at IS NULL",
        )
        .bind_refs([
            &D1Type::Text(&now_iso),
            &D1Type::Text(&target_device_id),
            &D1Type::Text(&auth.user_id),
        ])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("d1 run: {e}")))?;

    if result
        .meta()
        .ok()
        .flatten()
        .and_then(|m| m.changes)
        .unwrap_or(0)
        == 0
    {
        return Err(AppError::NotFound);
    }
    Ok(OkResponse { ok: true })
}

pub async fn refresh(mut req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let auth = match require_auth(&req, &ctx).await {
        Ok(a) => a,
        Err(e) => {
            e.log();
            return e.into_response();
        }
    };
    let body: RefreshRequest = match req.json().await {
        Ok(b) => b,
        Err(_) => {
            return AppError::BadRequest("invalid JSON body".into()).into_response();
        }
    };
    into_response(refresh_inner(auth, body.domains, &ctx).await)
}

async fn refresh_inner(
    auth: AuthContext,
    domains: Vec<String>,
    ctx: &RouteContext<()>,
) -> Result<RefreshResponse, AppError> {
    let secret = jwt_secret(ctx)?;
    let now = Utc::now();
    let (token, jti, exp) = issue_token(
        &auth.user_id,
        &auth.device_id,
        domains,
        secret.as_bytes(),
        now,
    )?;

    let now_iso = now.to_rfc3339();
    let db = db(ctx)?;
    let result = db
        .prepare(
            "UPDATE devices SET jti = ?1, last_seen_at = ?2 \
             WHERE id = ?3 AND user_id = ?4 AND revoked_at IS NULL",
        )
        .bind_refs([
            &D1Type::Text(&jti),
            &D1Type::Text(&now_iso),
            &D1Type::Text(&auth.device_id),
            &D1Type::Text(&auth.user_id),
        ])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("d1 run: {e}")))?;

    if result
        .meta()
        .ok()
        .flatten()
        .and_then(|m| m.changes)
        .unwrap_or(0)
        == 0
    {
        // Device was revoked between the auth check and the update.
        return Err(AppError::Unauthorized);
    }

    Ok(RefreshResponse {
        access_token: token,
        token_type: "Bearer",
        expires_at: exp.to_rfc3339(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalise_domains_keeps_finance_and_curated_optional_domains() {
        let domains = normalise_domains(vec![
            "knowledge".to_string(),
            "time".to_string(),
            "health".to_string(),
            "health".to_string(),
        ]);
        assert_eq!(
            domains,
            vec![
                "finance".to_string(),
                "health".to_string(),
                "knowledge".to_string()
            ]
        );
    }
}
