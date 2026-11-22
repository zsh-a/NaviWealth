//! Context supplied by the device. Only the explicit recognition request can
//! include saved examples, and only for a destination the owner opted into.
use super::{clock, favorites, finance, meals, settings, weights};
use crate::domain::{account::ModelAccount, nutrition::Food};
use navi_finance::{
    account::{AccountKind, defaults},
    currency::Currency,
};
use serde_json::{Value, json};

pub fn clock_context() -> Value {
    let now = clock::zoned(clock::now_ms()).datetime();
    json!({"local_date": now.date().to_string(), "local_time": now.time().to_string()})
}

pub fn for_request(account: &ModelAccount) -> Value {
    let mut context = clock_context();
    context["known_accounts"] = json!(
        finance::accounts_snapshot()
            .iter()
            .filter(|a| a.is_cash())
            .map(ToString::to_string)
            .collect::<Vec<_>>()
    );
    context["known_categories"] = json!(
        Currency::ALL
            .into_iter()
            .flat_map(|currency| defaults::all()
                .into_iter()
                .filter(|a| matches!(a.kind(), AccountKind::Expenses | AccountKind::Income))
                .map(move |a| a.in_currency(currency).to_string()))
            .collect::<Vec<_>>()
    );
    if settings::capture_options(account).recent_context {
        context["known_securities"] = json!(
            finance::holdings_snapshot()
                .securities
                .iter()
                .map(|s| json!({"id":s.id,"name":s.name,"currency":s.currency().code()}))
                .collect::<Vec<_>>()
        );
        let mut saved = favorites::all();
        saved.sort_by_key(|f| std::cmp::Reverse(f.used_at_ms));
        context["favorites"] = json!(
            saved
                .iter()
                .take(4)
                .map(|f| json!({"title":short(&f.name()), "foods":food_examples(&f.foods)}))
                .collect::<Vec<_>>()
        );
        context["recent_records"] = recent_records();
    }
    context
}

fn short(text: &str) -> String {
    text.chars().take(80).collect()
}

fn food_examples(foods: &[Food]) -> Vec<Value> {
    foods
        .iter()
        .take(8)
        .map(|f| json!({"name":short(&f.name),"grams":f.grams,"per_100g":f.per_100g}))
        .collect()
}

fn recent_records() -> Value {
    let mut entries = Vec::new();
    let mut meals = meals::all();
    meals.sort_by_key(|m| std::cmp::Reverse((m.day, m.logged_at_ms)));
    entries.extend(meals.iter().take(3).map(|meal| {
        json!({
            "kind": "meal", "day": meal.day.to_string(), "slot": meal.slot,
            "title": meal.title.as_deref().map(short), "foods": food_examples(&meal.foods),
        })
    }));
    let snapshot = finance::transactions_snapshot();
    let mut money: Vec<_> = snapshot.iter().collect();
    money.sort_by_key(|t| std::cmp::Reverse(t.at));
    entries.extend(money.into_iter().take(3).map(|transaction| {
        let postings: Vec<_> = transaction.postings.iter().take(4).map(|p| json!({
            "account": p.account, "minor_units": p.amount, "currency": p.account.currency().code(),
        })).collect();
        json!({"kind":"money", "day":transaction.at.date().to_string(), "payee":short(&transaction.payee), "postings":postings})
    }));
    if let Some(w) = weights::all().iter().max_by_key(|w| w.day) {
        entries.push(json!({"kind":"weight","day":w.day.to_string(),"kg":w.kg}));
    }
    Value::Array(entries)
}
