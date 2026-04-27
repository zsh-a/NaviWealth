use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use worker::{D1Database, D1Type, Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::{
    jwt::{self, Claims},
    middleware::{jwt_secret, require_auth},
    password, AuthContext, ACCESS_TOKEN_TTL_DAYS,
};
use crate::error::AppError;

#[derive(Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
    #[serde(default)]
    device_name: Option<String>,
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
    };
    let token = jwt::encode(&claims, secret)?;
    Ok((token, jti, exp))
}

pub async fn login(mut req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let body: LoginRequest = match req.json().await {
        Ok(b) => b,
        Err(_) => return AppError::BadRequest("invalid JSON body".into()).into_response(),
    };
    into_response(login_inner(body, &ctx).await)
}

async fn login_inner(
    body: LoginRequest,
    ctx: &RouteContext<()>,
) -> Result<LoginResponse, AppError> {
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

    let secret = jwt_secret(ctx)?;
    let now = Utc::now();
    let device_id = Uuid::new_v4().to_string();
    let (token, jti, exp) = issue_token(&user_id, &device_id, secret.as_bytes(), now)?;

    let now_iso = now.to_rfc3339();
    let name_value = match body.device_name.as_deref().map(str::trim) {
        Some(s) if !s.is_empty() => D1Type::Text(s),
        _ => D1Type::Null,
    };
    db.prepare(
        "INSERT INTO devices (id, user_id, name, jti, created_at, last_seen_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
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

pub async fn refresh(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let auth = match require_auth(&req, &ctx).await {
        Ok(a) => a,
        Err(e) => {
            e.log();
            return e.into_response();
        }
    };
    into_response(refresh_inner(auth, &ctx).await)
}

async fn refresh_inner(
    auth: AuthContext,
    ctx: &RouteContext<()>,
) -> Result<RefreshResponse, AppError> {
    let secret = jwt_secret(ctx)?;
    let now = Utc::now();
    let (token, jti, exp) = issue_token(&auth.user_id, &auth.device_id, secret.as_bytes(), now)?;

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
