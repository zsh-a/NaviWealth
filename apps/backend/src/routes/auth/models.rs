use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub(super) struct AuthRequest {
    pub(super) email: String,
    pub(super) password: String,
    pub(super) domains: Vec<String>,
    #[serde(default)]
    pub(super) device_name: Option<String>,
    #[serde(default)]
    pub(super) device_id: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct RefreshRequest {
    pub(super) domains: Vec<String>,
}

#[derive(Serialize)]
pub(super) struct LoginResponse {
    pub(super) access_token: String,
    pub(super) token_type: &'static str,
    pub(super) expires_at: String,
    pub(super) user_id: String,
    pub(super) device_id: String,
}

#[derive(Deserialize)]
pub(super) struct UserRow {
    pub(super) id: String,
    pub(super) password_hash: String,
}

#[derive(Deserialize)]
pub(super) struct ExistingUserRow {
    pub(super) id: String,
}

#[derive(Deserialize, Serialize)]
pub(super) struct DeviceRow {
    pub(super) id: String,
    pub(super) name: Option<String>,
    pub(super) created_at: String,
    pub(super) last_seen_at: String,
}

#[derive(Serialize)]
pub(super) struct DevicesResponse {
    pub(super) devices: Vec<DeviceRow>,
    pub(super) current_device_id: String,
}

#[derive(Serialize)]
pub(super) struct OkResponse {
    pub(super) ok: bool,
}

#[derive(Serialize)]
pub(super) struct RefreshResponse {
    pub(super) access_token: String,
    pub(super) token_type: &'static str,
    pub(super) expires_at: String,
}
