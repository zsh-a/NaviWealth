//! Opt-in screenshot fixture. Never called by app startup or production data.
//! Run only with XDG_DATA_HOME=/tmp/naviwealth-direction-a-data.
use naviwealth_client::{
    Services,
    finance::{RecordDraft, RecordKind},
};
use naviwealth_finance::{
    models::{AccountCategory, NewAccount},
    planning::{Budget, FlowKind, Goal, Recurring},
    wealth::{AssetDraft, OperationDraft, OperationKind},
};
use rust_decimal::Decimal;
use serde_json::Value;
use std::collections::BTreeMap;

fn text(v: &Value, key: &str) -> String {
    v[key].as_str().unwrap().to_owned()
}
fn cents(v: &Value) -> Decimal {
    Decimal::new(v.as_i64().unwrap(), 2)
}
fn date(v: &str) -> i64 {
    chrono::NaiveDate::parse_from_str(v, "%Y-%m-%d")
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp()
}
fn draft(
    kind: RecordKind,
    date: i64,
    amount: Decimal,
    account_id: String,
    category_id: Option<String>,
    payee: Option<String>,
) -> RecordDraft {
    RecordDraft {
        kind,
        date,
        amount,
        account_id,
        category_id,
        payee,
        destination_account_id: None,
        destination_amount: None,
        note: None,
    }
}
#[tokio::main]
async fn main() -> Result<(), String> {
    assert_eq!(
        std::env::var("XDG_DATA_HOME").as_deref(),
        Ok("/tmp/naviwealth-direction-a-data"),
        "fixture requires its own temporary data directory"
    );
    let data: Value = serde_json::from_str(include_str!("fixtures/direction_a.json")).unwrap();
    let s = Services::try_shared()?;
    assert!(
        s.finance_accounts(false).await?.is_empty(),
        "refusing to seed a nonempty ledger"
    );
    let start = date("2026-10-14");
    let mut accounts = BTreeMap::new();
    for a in data["accounts"].as_array().unwrap() {
        let kind = match a["type"].as_str().unwrap() {
            "bank" => AccountCategory::Bank,
            "broker" => AccountCategory::Broker,
            "card" => AccountCategory::Credit,
            _ => AccountCategory::Cash,
        };
        let mut new = NewAccount::custody(kind, text(a, "name"), "CNY");
        new.account_number = a["tail"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(str::to_owned);
        let opening = cents(&a["opening_cents"])
            + match a["id"].as_str().unwrap() {
                "bank" => cents(&data["goal"]["contributed_cents"]),
                "broker" => -cents(&data["goal"]["contributed_cents"]),
                _ => Decimal::ZERO,
            };
        let account = s.create_account(new, Some(opening)).await?;
        let record = s
            .finance_records(
                naviwealth_client::finance::RecordFilter {
                    kind: Some(RecordKind::OpeningBalance),
                    account_id: Some(account.id.clone()),
                    ..Default::default()
                },
                1,
                0,
            )
            .await?
            .remove(0);
        s.save_finance_record(
            Some(record.id),
            draft(
                RecordKind::OpeningBalance,
                start,
                opening,
                account.id.clone(),
                None,
                None,
            ),
        )
        .await?;
        accounts.insert(text(a, "id"), account.id);
    }
    let expense_categories = s.finance_categories(RecordKind::Expense).await?;
    let income_categories = s.finance_categories(RecordKind::Income).await?;
    let mut categories = BTreeMap::new();
    for c in data["categories"].as_array().unwrap() {
        categories.insert(
            text(c, "id"),
            expense_categories
                .iter()
                .find(|(_, label)| *label == text(c, "full"))
                .expect("builtin category")
                .0
                .clone(),
        );
    }
    // A real transfer supplies the goal's contribution; opening offsets keep
    // the four final balances identical to the approved mock ledger.
    let goal_amount = cents(&data["goal"]["contributed_cents"]);
    let mut contribution = draft(
        RecordKind::Transfer,
        start,
        goal_amount,
        accounts["bank"].clone(),
        None,
        Some("旅行储蓄".into()),
    );
    contribution.destination_account_id = Some(accounts["broker"].clone());
    let contribution_id = s.save_finance_record(None, contribution).await?;
    for e in data["entries"].as_array().unwrap().iter().rev() {
        let income = e["kind"] == "income";
        let category = if income {
            Some(income_categories[0].0.clone())
        } else {
            Some(categories[&text(e, "category")].clone())
        };
        // Financial history is a civil-date series, matching the app date picker.
        let at = date(&text(e, "date"));
        s.save_finance_record(
            None,
            draft(
                if income {
                    RecordKind::Income
                } else {
                    RecordKind::Expense
                },
                at,
                cents(&e["cents"]),
                accounts[&text(e, "account")].clone(),
                category,
                Some(text(e, "name")),
            ),
        )
        .await?;
    }
    for c in data["categories"].as_array().unwrap() {
        s.save_finance_budget(Budget {
            month: text(&data, "month"),
            category_id: categories[&text(c, "id")].clone(),
            currency: "CNY".into(),
            limit: cents(&c["limit"]),
        })
        .await?;
    }
    let h = &data["holding"];
    let asset = s
        .save_wealth_asset(
            None,
            AssetDraft {
                kind: "etf".into(),
                name: text(h, "name"),
                market: Some("SH".into()),
                symbol: Some(text(h, "symbol")),
                currency: "CNY".into(),
                note: None,
            },
        )
        .await?;
    let quantity = Decimal::from(h["quantity"].as_i64().unwrap());
    s.save_wealth_operation(
        None,
        OperationDraft {
            kind: OperationKind::Opening,
            asset_id: asset.id.clone(),
            account_id: accounts["broker"].clone(),
            cash_account_id: None,
            date: start,
            quantity,
            unit_price: cents(&h["cost_cents"]) / quantity,
            fees: Decimal::ZERO,
            amount: Decimal::ZERO,
            note: None,
        },
    )
    .await?;
    for (index, value) in data["history_cents"].as_array().unwrap().iter().enumerate() {
        let at = start + index as i64 * 86400;
        let cash = s
            .wealth_cash_balances(at)
            .await?
            .into_iter()
            .map(|c| c.amount)
            .sum::<Decimal>();
        let price = (cents(value) - cash) / quantity;
        s.save_wealth_price(asset.id.clone(), price, at, Some("演示账本历史收盘".into()))
            .await?;
    }
    s.save_finance_recurring(
        None,
        Recurring {
            name: text(&data["due"], "name"),
            kind: FlowKind::Bill,
            account_id: accounts["bank"].clone(),
            category_id: expense_categories
                .iter()
                .find(|(_, n)| n == "运动健身")
                .unwrap()
                .0
                .clone(),
            currency: "CNY".into(),
            amount: cents(&data["due"]["cents"]),
            first_due: date(&text(&data["due"], "date")),
            interval_months: 1,
            end_due: None,
            paused: false,
        },
    )
    .await?;
    let goal = s
        .save_finance_goal(
            None,
            Goal {
                name: text(&data["goal"], "name"),
                currency: "CNY".into(),
                target: cents(&data["goal"]["target_cents"]),
                target_date: date("2027-06-01"),
                monthly_contribution: 2000.into(),
                asset_id: None,
            },
        )
        .await?;
    s.contribute_finance_goal(
        goal,
        contribution_id,
        cents(&data["goal"]["contributed_cents"]),
    )
    .await?;
    let snapshot = s.wealth_snapshot(date("2026-11-12"), "CNY".into()).await?;
    assert_eq!(
        snapshot.net_worth.unwrap().round_dp(2),
        cents(&data["net_worth_cents"])
    );
    println!(
        "45 flows, 4 accounts, 10 budgets, 1 holding, 30 historical prices, 1 due bill, 1 goal. Net worth: {:?}",
        snapshot.net_worth
    );
    Ok(())
}
