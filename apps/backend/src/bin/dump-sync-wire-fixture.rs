use naviwealth_backend::routes::sync::{RowAck, SyncResponse};
use naviwealth_backend::sync::store::RowChange;
use serde_json::json;
use std::collections::BTreeMap;

fn main() {
    let fixture = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: dump-sync-wire-fixture <fixture-name>");
        std::process::exit(64);
    });

    let output = match fixture.as_str() {
        "sync_v3_server_tombstone_row_change" => {
            serde_json::to_string_pretty(&server_tombstone()).unwrap()
        }
        "sync_v3_server_sync_response" => serde_json::to_string_pretty(&SyncResponse {
            seq: 42,
            changes: vec![server_tombstone()],
            more: false,
            accepted: vec![RowAck {
                table: "fin:accounts".into(),
                id: "acc-1".into(),
            }],
            domain_generations: BTreeMap::from([("finance".into(), 0), ("health".into(), 3)]),
        })
        .unwrap(),
        "sync_v3_server_empty_response" => serde_json::to_string_pretty(&SyncResponse {
            seq: 42,
            changes: vec![],
            more: false,
            accepted: vec![],
            domain_generations: BTreeMap::from([("finance".into(), 0)]),
        })
        .unwrap(),
        "sync_v3_server_more_response" => serde_json::to_string_pretty(&SyncResponse {
            seq: 42,
            changes: vec![server_tombstone()],
            more: true,
            accepted: vec![],
            domain_generations: BTreeMap::from([("health".into(), 3)]),
        })
        .unwrap(),
        "sync_v3_server_no_accepted_response" => serde_json::to_string_pretty(&SyncResponse {
            seq: 41,
            changes: vec![],
            more: false,
            accepted: vec![],
            domain_generations: BTreeMap::from([("finance".into(), 0)]),
        })
        .unwrap(),
        other => {
            eprintln!("unknown sync wire fixture: {other}");
            std::process::exit(64);
        }
    };

    println!("{output}");
}

fn server_tombstone() -> RowChange {
    RowChange {
        table: "health:health_metrics".into(),
        id: "metric-1".into(),
        payload: Some(json!({})),
        version: "1716381000124.0000-device-b".into(),
        deleted: true,
        device_id: "device-b".into(),
        seq: 42,
        generation: 3,
    }
}
