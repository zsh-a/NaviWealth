use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

use crate::error::AppError;

const SALT_LEN: usize = 16;

pub fn hash(password: &str) -> Result<String, AppError> {
    let mut salt_bytes = [0u8; SALT_LEN];
    getrandom::getrandom(&mut salt_bytes).map_err(|e| AppError::Internal(format!("rng: {e}")))?;
    let salt = SaltString::encode_b64(&salt_bytes)
        .map_err(|e| AppError::Internal(format!("salt: {e}")))?;
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::Internal(format!("argon2: {e}")))
}

pub fn verify(password: &str, phc: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(phc) else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}
