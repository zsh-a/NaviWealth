use naviwealth_backend::sync::store::RowChange;
use serde_json::json;

fn main() {
    let fixture = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: dump-sync-wire-fixture <fixture-name>");
        std::process::exit(64);
    });

    let row = match fixture.as_str() {
        "sync_v2_server_tombstone_row_change" => RowChange {
            table: "health:health_metrics".into(),
            id: "metric-1".into(),
            payload: Some(json!({})),
            version: "1716381000124.0000-device-b".into(),
            deleted: true,
            device_id: "device-b".into(),
            seq: 42,
        },
        other => {
            eprintln!("unknown sync wire fixture: {other}");
            std::process::exit(64);
        }
    };

    println!("{}", serde_json::to_string_pretty(&row).unwrap());
}
