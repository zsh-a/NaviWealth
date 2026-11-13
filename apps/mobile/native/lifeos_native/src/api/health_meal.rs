//! Narrow host adapter for the shared meal core. Photos and credentials stay
//! device-local; only the explicitly approved endpoint receives the images.

use anyhow::Result;
use health_core::{
    consent::{Consent, UploadTarget},
    photo::{MealPhoto, prepare},
    recognition::{Lang, recognize_meal},
};
use llm_client::{CapabilityCache, Client, Endpoint, Protocol, Timeouts};
use llm_reqwest::ReqwestTransport;
use serde::Deserialize;
use std::{sync::OnceLock, time::Duration};

static CAPABILITIES: OnceLock<CapabilityCache> = OnceLock::new();

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MealRequest {
    provider: String,
    base_url: Option<String>,
    model: String,
    #[serde(default)]
    api_key: String,
    #[serde(default)]
    allow_upload: bool,
    language_code: String,
    #[serde(default)]
    context: String,
    photos: Vec<MealPhoto>,
}

/// Completes one recognition against the profile frozen by the consent dialog.
/// JSON carries only a validated draft; persistence remains in the Host.
pub async fn health_meal_recognize_json(request_json: String) -> Result<String> {
    // Four 2 MiB byte arrays encoded as JSON fit comfortably within this bound.
    // Reject before deserialization to avoid unbounded allocations at the FFI seam.
    anyhow::ensure!(
        request_json.len() <= 40 * 1024 * 1024,
        "meal_request_too_large"
    );
    let request: MealRequest =
        serde_json::from_str(&request_json).map_err(|_| anyhow::anyhow!("invalid_meal_request"))?;
    let (protocol, default_base) = match request.provider.as_str() {
        "anthropic" => (Protocol::Anthropic, "https://api.anthropic.com/v1"),
        "openai" | "openai-compatible" => (Protocol::OpenAiCompatible, "https://api.openai.com/v1"),
        _ => anyhow::bail!("unsupported_meal_provider"),
    };
    let base_url = request.base_url.as_deref().unwrap_or(default_base);
    let target = UploadTarget::new(&request.provider, base_url, &request.model);
    let consent = Consent::approve(target, request.allow_upload)?;
    crate::android_tls::ensure_initialized()?;
    let endpoint = Endpoint::new(protocol, &request.provider, base_url, &request.api_key)?;
    let client = Client::new(endpoint, ReqwestTransport::new()?)
        .with_capability_cache(CAPABILITIES.get_or_init(CapabilityCache::default).clone())
        .with_timeouts(Timeouts {
            total: Duration::from_secs(150),
            ..Timeouts::default()
        });
    let estimate = recognize_meal(
        &client,
        &request.model,
        &request.photos,
        &consent,
        Lang::from_language(&request.language_code),
        &request.context,
    )
    .await?;
    Ok(serde_json::to_string(&estimate.adapter_json())?)
}

/// Corrects orientation, bounds decoded memory, and emits a metadata-free JPEG.
pub fn health_meal_normalize_photo(bytes: Vec<u8>) -> Result<Vec<u8>> {
    Ok(prepare(&bytes)?.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn unapproved_photo_never_reaches_transport() {
        let request = json!({
            "provider": "anthropic", "model": "model", "api_key": "secret",
            "base_url": "http://127.0.0.1:1/v1", "allow_upload": false,
            "language_code": "en", "photos": [{"bytes":[1], "role":"overview"}]
        });
        let error = health_meal_recognize_json(request.to_string())
            .await
            .unwrap_err();
        assert!(error.to_string().contains("not approved"));
        assert!(!error.to_string().contains("secret"));
    }

    #[test]
    fn invalid_photo_is_rejected() {
        assert!(health_meal_normalize_photo(b"not an image".to_vec()).is_err());
    }

    #[tokio::test]
    async fn native_adapter_recognizes_and_preserves_shared_provenance() {
        use std::io::{Cursor, Read, Write};
        use std::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(10)))
                .unwrap();
            let mut bytes = Vec::new();
            let header_end = loop {
                let mut byte = [0];
                socket.read_exact(&mut byte).unwrap();
                bytes.push(byte[0]);
                if bytes.ends_with(b"\r\n\r\n") {
                    break bytes.len();
                }
                assert!(bytes.len() < 16_384);
            };
            let headers = String::from_utf8(bytes).unwrap();
            assert!(headers.starts_with("POST /v1/messages "));
            let length: usize = headers
                .lines()
                .find_map(|line| {
                    let (name, value) = line.split_once(':')?;
                    name.eq_ignore_ascii_case("content-length")
                        .then(|| value.trim().parse().unwrap())
                })
                .unwrap();
            assert!(header_end < 16_384 && length < 100_000);
            let mut body = vec![0; length];
            socket.read_exact(&mut body).unwrap();
            let request: serde_json::Value = serde_json::from_slice(&body).unwrap();
            assert_eq!(request["messages"][0]["content"][1]["type"], "image");
            let answer = json!({"title":"Rice", "foods":[{
                "name":"Rice", "grams":150, "catalog_id":"168878",
                "per_100g":{"kcal":1,"protein":1,"carbs":1,"fat":1},
                "confidence":"medium"
            }]});
            let response = json!({
                "model":"fixture-vision", "stop_reason":"end_turn",
                "content":[{"type":"text","text":answer.to_string()}]
            })
            .to_string();
            write!(socket, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", response.len(), response).unwrap();
        });
        let mut png = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(4, 4)
            .write_to(&mut png, image::ImageFormat::Png)
            .unwrap();
        let request = json!({
            "provider":"anthropic", "base_url":format!("http://{address}/v1"),
            "model":"fixture-vision", "api_key":"test-key", "allow_upload":true,
            "language_code":"en", "context":"One meal", "photos":[{
                "bytes":png.into_inner(), "role":"overview"
            }]
        });
        let result: serde_json::Value = serde_json::from_str(
            &health_meal_recognize_json(request.to_string())
                .await
                .unwrap(),
        )
        .unwrap();
        server.join().unwrap();
        assert_eq!(result["model"], "fixture-vision");
        assert_eq!(
            result["prompt_version"],
            health_core::recognition::PROMPT_VERSION
        );
        assert_eq!(result["foods"][0]["source"], "USDA FDC 168878");
        assert_eq!(result["foods"][0]["per_100g"]["kcal"], 130.0);
        assert_eq!(result["foods"][0]["nutrients"]["kcal"], 195.0);
    }
}
