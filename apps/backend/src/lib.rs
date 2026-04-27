use worker::*;

mod auth;
mod error;
mod routes;

#[event(fetch, respond_with_errors)]
pub async fn main(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    console_error_panic_hook::set_once();

    Router::new()
        .get("/", |_, _| Response::ok("naviwealth-backend"))
        .get("/health", routes::health::get)
        .get_async("/health/db", routes::health::get_db)
        .post_async("/auth/login", routes::auth::login)
        .get_async("/auth/devices", routes::auth::list_devices)
        .post_async("/auth/logout/:device_id", routes::auth::logout)
        .post_async("/auth/refresh", routes::auth::refresh)
        .run(req, env)
        .await
}
