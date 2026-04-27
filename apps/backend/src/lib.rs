use worker::*;

mod error;
mod routes;

#[event(fetch, respond_with_errors)]
pub async fn main(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    console_error_panic_hook::set_once();

    Router::new()
        .get("/", |_, _| Response::ok("naviwealth-backend"))
        .get("/health", routes::health::get)
        .get_async("/health/db", routes::health::get_db)
        .run(req, env)
        .await
}
