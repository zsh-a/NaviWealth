use worker::*;

pub mod ai;
mod auth;
pub mod error;
mod hlc;
mod routes;
mod sync;

/// Append CORS headers to a response.
fn add_cors(resp: &mut Response, origin: &str) {
    let h = resp.headers_mut();
    h.set("Access-Control-Allow-Origin", origin).ok();
    h.set(
        "Access-Control-Allow-Methods",
        "GET, POST, PUT, DELETE, OPTIONS",
    )
    .ok();
    h.set(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization, Sync-Protocol-Version",
    )
    .ok();
    h.set("Access-Control-Max-Age", "86400").ok();
}

#[event(fetch, respond_with_errors)]
pub async fn main(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    console_error_panic_hook::set_once();

    let origin = req
        .headers()
        .get("Origin")
        .ok()
        .flatten()
        .unwrap_or_else(|| "*".to_string());

    // Handle CORS preflight
    if req.method() == Method::Options {
        let mut resp = Response::empty()?;
        add_cors(&mut resp, &origin);
        return Ok(resp);
    }

    let mut resp = Router::new()
        .get("/", |_, _| Response::ok("naviwealth-backend"))
        .get("/health", routes::health::get)
        .get_async("/health/db", routes::health::get_db)
        .post_async("/auth/login", routes::auth::login)
        .get_async("/auth/devices", routes::auth::list_devices)
        .post_async("/auth/logout/:device_id", routes::auth::logout)
        .post_async("/auth/refresh", routes::auth::refresh)
        .get_async("/me", routes::me::get)
        .post_async("/sync/push", routes::sync::push)
        .get_async("/sync/pull", routes::sync::pull)
        .post_async("/ai/chat", routes::ai::chat)
        .post_async("/ingest/parse", routes::ingest::parse)
        .run(req, env)
        .await?;

    add_cors(&mut resp, &origin);
    Ok(resp)
}
