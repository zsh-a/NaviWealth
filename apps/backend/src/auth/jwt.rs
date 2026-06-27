use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hmac::{Hmac, KeyInit, Mac};
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
    /// LifeOS domains the caller is opted into (`docs/architecture/lifeos-shell.md`
    /// §5, D-1.5). FinanceOS is the seed domain so legacy tokens emitted
    /// before this claim landed decode as `["finance"]`.
    #[serde(default = "default_domains")]
    pub domains: Vec<String>,
}

/// Default for tokens that were issued before the `domains` claim
/// landed (D-1.5). Every legacy token belongs to FinanceOS — the only
/// domain that existed before Phase D.
pub fn default_domains() -> Vec<String> {
    vec!["finance".to_string()]
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

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_claims() -> Claims {
        Claims {
            sub: "user-1".into(),
            did: "device-1".into(),
            jti: "jti-1".into(),
            iat: 1_700_000_000,
            exp: 1_700_000_000 + 86_400,
            domains: default_domains(),
        }
    }

    #[test]
    fn encode_then_decode_roundtrips_default_domain() {
        let secret = b"unit-test-secret";
        let token = encode(&sample_claims(), secret).expect("encode");
        let decoded = decode(&token, secret).expect("decode");
        assert_eq!(decoded.domains, vec!["finance".to_string()]);
    }

    #[test]
    fn encode_then_decode_preserves_multi_domain_claim() {
        let secret = b"unit-test-secret";
        let mut claims = sample_claims();
        claims.domains = vec!["finance".to_string(), "health".to_string()];
        let token = encode(&claims, secret).expect("encode");
        let decoded = decode(&token, secret).expect("decode");
        assert_eq!(
            decoded.domains,
            vec!["finance".to_string(), "health".to_string()],
        );
    }

    #[test]
    fn legacy_payload_without_domains_decodes_to_finance() {
        // Construct a payload by hand the way a pre-D-1.5 token would
        // look — no `domains` field. The serde default must kick in.
        let header_b64 = URL_SAFE_NO_PAD.encode(b"{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        let payload = "{\"sub\":\"u\",\"did\":\"d\",\"jti\":\"j\",\"iat\":1,\"exp\":2}";
        let payload_b64 = URL_SAFE_NO_PAD.encode(payload.as_bytes());

        let secret = b"unit-test-secret";
        let signing_input = format!("{header_b64}.{payload_b64}");
        let mut mac = HmacSha256::new_from_slice(secret).unwrap();
        mac.update(signing_input.as_bytes());
        let sig_b64 = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());
        let token = format!("{signing_input}.{sig_b64}");

        let decoded = decode(&token, secret).expect("decode legacy");
        assert_eq!(decoded.domains, vec!["finance".to_string()]);
    }
}
