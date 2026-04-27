use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

use crate::error::AppError;

type HmacSha256 = Hmac<Sha256>;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Claims {
    pub sub: String,
    pub did: String,
    pub jti: String,
    pub iat: i64,
    pub exp: i64,
}

#[derive(Serialize)]
struct Header {
    alg: &'static str,
    typ: &'static str,
}

pub fn encode(claims: &Claims, secret: &[u8]) -> Result<String, AppError> {
    let header = serde_json::to_vec(&Header {
        alg: "HS256",
        typ: "JWT",
    })
    .map_err(|e| AppError::Internal(format!("jwt header: {e}")))?;
    let payload =
        serde_json::to_vec(claims).map_err(|e| AppError::Internal(format!("jwt payload: {e}")))?;

    let signing_input = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(&header),
        URL_SAFE_NO_PAD.encode(&payload),
    );
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|e| AppError::Internal(format!("hmac key: {e}")))?;
    mac.update(signing_input.as_bytes());
    let sig = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());
    Ok(format!("{signing_input}.{sig}"))
}

pub fn decode(token: &str, secret: &[u8]) -> Result<Claims, AppError> {
    let mut parts = token.split('.');
    let h_b64 = parts.next().ok_or(AppError::Unauthorized)?;
    let p_b64 = parts.next().ok_or(AppError::Unauthorized)?;
    let s_b64 = parts.next().ok_or(AppError::Unauthorized)?;
    if parts.next().is_some() {
        return Err(AppError::Unauthorized);
    }

    let signing_input = format!("{h_b64}.{p_b64}");
    let sig_bytes = URL_SAFE_NO_PAD
        .decode(s_b64)
        .map_err(|_| AppError::Unauthorized)?;

    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|e| AppError::Internal(format!("hmac key: {e}")))?;
    mac.update(signing_input.as_bytes());
    mac.verify_slice(&sig_bytes)
        .map_err(|_| AppError::Unauthorized)?;

    let payload = URL_SAFE_NO_PAD
        .decode(p_b64)
        .map_err(|_| AppError::Unauthorized)?;
    serde_json::from_slice(&payload).map_err(|_| AppError::Unauthorized)
}
