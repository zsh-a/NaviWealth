use serde::Serialize;
use worker::{Request, Response, Result, RouteContext};

#[derive(Serialize)]
struct HealthBody {
    status: &'static str,
    service: &'static str,
    version: &'static str,
}

#[derive(Serialize)]
struct DbHealthBody {
    status: &'static str,
    db: &'static str,
}

pub fn get(_req: Request, _ctx: RouteContext<()>) -> Result<Response> {
    Response::from_json(&HealthBody {
        status: "ok",
        service: "naviwealth-backend",
        version: env!("CARGO_PKG_VERSION"),
    })
}

pub async fn get_db(_req: Request, ctx: RouteContext<()>) -> Result<Response> {
    let db = match ctx.env.d1("DB") {
        Ok(db) => db,
        Err(_) => {
            return Response::from_json(&DbHealthBody {
                status: "unbound",
                db: "DB",
            })
            .map(|r| r.with_status(503));
        }
    };

    let stmt = db.prepare("SELECT 1 AS one");
    match stmt.first::<serde_json::Value>(None).await {
        Ok(_) => Response::from_json(&DbHealthBody {
            status: "ok",
            db: "DB",
        }),
        Err(e) => {
            worker::console_log!("d1 health probe failed: {e}");
            Response::from_json(&DbHealthBody {
                status: "error",
                db: "DB",
            })
            .map(|r| r.with_status(503))
        }
    }
}
