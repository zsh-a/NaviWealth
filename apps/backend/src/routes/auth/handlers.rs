use chrono::Utc;
use uuid::Uuid;
use worker::{D1Type, Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::{
    middleware::{jwt_secret, require_auth},
    password, AuthContext,
};
use crate::error::AppError;

use super::models::{
    AuthRequest, DeviceRow, DevicesResponse, ExistingUserRow, LoginResponse, OkResponse,
    RefreshRequest, RefreshResponse, UserRow,
};
use super::session::{db, into_response, issue_session, issue_token};

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
