use super::*;

#[test]
fn chat_request_parses_with_context_pack() {
    let raw = r#"{
        "messages": [{"role": "user", "content": "hi"}],
        "context_pack": {
            "version": {"major": 1, "minor": 0},
            "base": {
                "preferred_currency": "USD",
                "risk_preference": "moderate",
                "accounts": {"total_count": 0, "by_kind": {}},
                "cashflow": {
                    "base_currency": "USD",
                    "months_covered": 0,
                    "average_inflow_minor": "0",
                    "average_outflow_minor": "0",
                    "trend": "unknown"
                }
            },
            "task": {
                "route": {"path": "/expense", "area": "expense"},
                "intent": {"capability": "analyze", "risk": "suggest"}
            },
            "budget": {"tier": "standard"}
        }
    }"#;

    let body: ChatRequest = serde_json::from_str(raw).expect("parse");
    let pack = body.context_pack.expect("context_pack present");

    assert!(pack.assert_version(&CURRENT_CONTEXT_PACK_VERSION).is_ok());
    assert!(pack.assert_budget().is_ok());
}

#[test]
fn chat_request_parses_without_context_pack_for_legacy_clients() {
    let raw = r#"{"messages": [{"role": "user", "content": "hi"}]}"#;
    let body: ChatRequest = serde_json::from_str(raw).expect("parse");
    assert!(body.context_pack.is_none());
}

#[test]
fn chat_request_parses_freshness_hint_with_force_refresh() {
    let raw = r#"{
        "messages": [{"role": "user", "content": "hi"}],
        "context_pack": {
            "version": {"major": 1, "minor": 0},
            "base": {
                "preferred_currency": "USD",
                "risk_preference": "moderate",
                "accounts": {"total_count": 0, "by_kind": {}},
                "cashflow": {
                    "base_currency": "USD",
                    "months_covered": 0,
                    "average_inflow_minor": "0",
                    "average_outflow_minor": "0",
                    "trend": "unknown"
                }
            },
            "task": {
                "route": {"path": "/", "area": "home"},
                "intent": {"capability": "analyze", "risk": "info"},
                "freshness_hint": {
                    "force_refresh_read_models": [
                        "monthly_spend_by_category",
                        "holdings_snapshot"
                    ]
                }
            },
            "budget": {"tier": "standard"}
        }
    }"#;
    let body: ChatRequest = serde_json::from_str(raw).expect("parse");
    let pack = body.context_pack.expect("present");
    let hint = pack.task.freshness_hint.expect("hint present");

    assert_eq!(
        hint.force_refresh_read_models,
        vec![
            "monthly_spend_by_category".to_string(),
            "holdings_snapshot".to_string()
        ]
    );
}
