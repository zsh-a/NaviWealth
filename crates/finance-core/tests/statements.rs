//! The statement corpus: each fixture's manifest pins the provider, the
//! candidate, accepted and skipped counts, every accepted row and every
//! issue, exactly as the Flutter parsers produced them.

use std::{fs, path::Path};

use finance_core::statement::{self, Kind, Provider};
use serde_json::Value;

fn provider_name(provider: Provider) -> &'static str {
    match provider {
        Provider::Alipay => "alipay",
        Provider::WechatPay => "wechatPay",
        Provider::CmbCreditCard => "bank",
        Provider::Generic => "generic",
    }
}

/// `2026-07-10T12:30:01`, `2026-06-20T00:00:00.000Z` → civil time.
fn civil(text: &str) -> jiff::civil::DateTime {
    let trimmed = text.trim_end_matches('Z');
    let trimmed = trimmed.strip_suffix(".000").unwrap_or(trimmed);
    trimmed.parse().unwrap()
}

#[test]
fn every_fixture_matches_its_manifest() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let mut checked = 0;
    for entry in fs::read_dir(&dir).unwrap() {
        let path = entry.unwrap().path();
        if !path.to_string_lossy().ends_with(".expected.json") {
            continue;
        }
        let manifest: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(manifest["privacy"]["containsUserData"], false);
        let fixture = manifest["fixture"].as_str().unwrap();
        let bytes = fs::read(dir.join(fixture)).unwrap();
        let report =
            statement::parse_file(&bytes, manifest["defaultCurrency"].as_str().unwrap()).unwrap();
        let expected = &manifest["expected"];

        assert_eq!(
            provider_name(report.provider),
            expected["provider"],
            "{fixture}"
        );
        assert_eq!(
            report.candidates as u64, expected["candidateRowCount"],
            "{fixture}"
        );
        assert_eq!(
            report.rows.len() as u64,
            expected["acceptedRowCount"],
            "{fixture}"
        );
        assert_eq!(
            report.issues.len() as u64,
            expected["skippedRowCount"],
            "{fixture}"
        );
        assert_eq!(
            report.accounts_for_every_candidate(),
            expected["accountsForEveryCandidate"] == true
        );

        let rows = expected["rows"].as_array().unwrap();
        assert_eq!(report.rows.len(), rows.len());
        for (row, want) in report.rows.iter().zip(rows) {
            assert_eq!(
                row.at,
                civil(want["occurredAt"].as_str().unwrap()),
                "{fixture}"
            );
            assert_eq!(row.description, want["description"], "{fixture}");
            assert_eq!(
                row.amount,
                want["amountMinor"].as_i64().unwrap(),
                "{fixture}"
            );
            assert_eq!(row.currency, want["currency"], "{fixture}");
            let kind = match row.kind {
                Kind::Expense => "expense",
                Kind::Income => "income",
                _ => panic!("legacy corpus must not contain ledger review kinds"),
            };
            assert_eq!(kind, want["kind"], "{fixture}");
            assert_eq!(
                row.category_hint.map(Value::from).unwrap_or(Value::Null),
                want["categoryHint"],
                "{fixture}"
            );
        }
        let issues: Vec<(u64, &str)> = report
            .issues
            .iter()
            .map(|i| (i.line as u64, i.code.name()))
            .collect();
        let want: Vec<(u64, &str)> = expected["issues"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| {
                (
                    i["lineNumber"].as_u64().unwrap(),
                    i["code"].as_str().unwrap(),
                )
            })
            .collect();
        assert_eq!(issues, want, "{fixture}");
        checked += 1;
    }
    assert_eq!(checked, 3, "alipay, wechat and cmb fixtures");
}

#[test]
fn rows_keep_their_fields_for_mapping() {
    let bytes = fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/alipay_representative.csv"),
    )
    .unwrap();
    let report = statement::parse_file(&bytes, "CNY").unwrap();
    let lunch = &report.rows[0];
    assert_eq!(lunch.payee.as_deref(), Some("示例餐厅"));
    assert_eq!(lunch.item.as_deref(), Some("午餐"));
    assert_eq!(lunch.provider_type.as_deref(), Some("餐饮美食"));
    assert_eq!(lunch.payment_method.as_deref(), Some("余额"));
    assert_eq!(lunch.reference.as_deref(), Some("trade-1"));
    assert!(lunch.has_time);

    // The same statement saved by Alipay in GB18030 reads the same.
    let text = String::from_utf8(bytes).unwrap();
    let (gbk, _, _) = encoding_rs::GB18030.encode(&text);
    assert_eq!(statement::parse_file(&gbk, "CNY").unwrap(), report);
}
