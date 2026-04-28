use serde::Deserialize;
use worker::{D1Type, Request, RouteContext};

use super::jwt::{self, Claims};
use crate::error::AppError;

#[derive(Debug, Clone)]
pub struct AuthContext {
    pub user_id: String,
    pub device_id: String,
}

#[derive(Deserialize)]
struct DeviceCheck {
    jti: String,
    revoked_at: Option<String>,
}

pub fn jwt_secret(ctx: &RouteContext<()>) -> Result<String, AppError> {
    ctx.env
        .secret("JWT_SECRET")
        .map(|s| s.to_string())
        .map_err(|_| AppError::Internal("JWT_SECRET unbound".into()))
}

fn bearer_token(req: &Request) -> Result<String, AppError> {
    let header = req
        .headers()
        .get("Authorization")
        .map_err(|e| AppError::Internal(format!("headers: {e}")))?
        .ok_or(AppError::Unauthorized)?;
    let token = header
        .strip_prefix("Bearer ")
        .or_else(|| header.strip_prefix("bearer "))
        .ok_or(AppError::Unauthorized)?
        .trim();
    if token.is_empty() {
        return Err(AppError::Unauthorized);
    }
    Ok(token.to_string())
}

pub fn verify_token(token: &str, secret: &[u8]) -> Result<Claims, AppError> {
    let claims = jwt::decode(token, secret)?;
    let now = chrono::Utc::now().timestamp();
    if claims.exp <= now {
        return Err(AppError::Unauthorized);
    }
    Ok(claims)
}

/// Verifies the request's bearer token and matches it against the active device
/// row in D1. Returns the resolved [`AuthContext`] or an [`AppError`] suitable
/// for surfacing to the client (401 on any auth failure, 500 only on infra
/// problems like a missing JWT_SECRET binding).
pub async fn require_auth(req: &Request, ctx: &RouteContext<()>) -> Result<AuthContext, AppError> {
    let token = bearer_token(req)?;
    let secret = jwt_secret(ctx)?;
    let claims = verify_token(&token, secret.as_bytes())?;

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    let row: Option<DeviceCheck> = db
        .prepare("SELECT jti, revoked_at FROM devices WHERE id = ?1 AND user_id = ?2")
        .bind_refs([&D1Type::Text(&claims.did), &D1Type::Text(&claims.sub)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;

    let Some(row) = row else {
        return Err(AppError::Unauthorized);
    };
    if row.revoked_at.is_some() || row.jti != claims.jti {
        return Err(AppError::Unauthorized);
    }

    Ok(AuthContext {
        user_id: claims.sub,
        device_id: claims.did,
    })
}
