use super::*;
use crate::{
    data::{capture, catalog},
    domain::capture::{self as model, Status},
};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::json;

fn parsed(draft: &mut Draft, records: serde_json::Value) {
    draft.records = model::parse(&json!({"records":records}).to_string())
        .unwrap()
        .0;
    draft.status = Status::Ready;
    draft.model = "test".into();
}
fn exercise() -> Result<(), String> {
    db::open()?;
    finance::load()?;
    let today = clock::today();
    let day = today.to_string();
    let account = Account::parse("资产:Cash").unwrap();
    if !finance::accounts().contains(&account) {
        finance::create_account(account.clone()).unwrap();
    }
    let security = Security::new("fund", "My index fund").unwrap();
    finance::add_trade(
        Some(&security),
        &Trade {
            id: "existing".into(),
            security: "fund".into(),
            at: today.0.at(0, 0, 0, 0),
            kind: holdings::Kind::Opening,
            quantity: holdings::SCALE,
            price: holdings::SCALE,
            amount: 0,
            fee: 0,
            cash: None,
        },
    )
    .unwrap();
    weights::set(today, 61.2);
    let before = finance::transactions();
    let mut draft = capture::new();
    draft.input = "Fund and Cash".into();
    draft.photo = Some("scale.png".into());
    draft.transcript.push(model::Turn::Owner {
        text: draft.input.clone(),
        photo: true,
        images: vec!["scale.png".into(), "lunch.png".into()],
    });
    parsed(
        &mut draft,
        json!([
            {"kind":"balance","day":day,"balance":{"account":"资产:Cash","actual":"100.00"}},
            {"kind":"weight","day":day,"weight_kg":62.3},
            {"kind":"price","day":day,"price":{"security":"My index fund","currency":"CNY","unit_price":"2.345678"}},
            {"kind":"money","day":day,"money":{"kind":"expense","currency":"CNY","amount":"1.03","account":"资产:Cash","other_account":null,"category":"支出:餐饮","time":null,"payee":"Bus","note":""}},
            {"kind":"note","day":day,"note":"Walked to work"},
            {"kind":"trade","day":day,"trade":{"security":"My index fund","currency":"CNY","kind":"buy","quantity":"0.123456","unit_price":"8.000001","fee":"0.02","amount":null,"cash":"资产:Cash"}},
            {"kind":"meal","day":day,"slot":"lunch","meal":{"source_image":2,"title":"Rice","foods":[{"name":"rice","grams":100,"catalog_id":null,"confidence":"high","per_100g":{"kcal":100,"protein":2,"carbs":22,"fat":0,"fiber":null,"sugars":null,"sat_fat":null,"sodium_mg":null}}]}}
        ]),
    );
    // Price, holding and check all keep their exact native integer precision.
    assert_eq!(book_balance(&draft, 0), Some(-204));
    capture::put(draft.clone())?;
    assert!(capture::ready(&draft));
    finance::set_account_archived(&account, true).unwrap();
    for index in [0, 3, 5] {
        assert_eq!(
            record_issue(&draft, index),
            Some(CaptureIssue::UnknownAccount)
        );
    }
    assert!(!capture::ready(&draft));
    assert!(capture::confirm_review(&draft).is_err());
    assert!(capture::get(&draft.id).is_some());
    finance::set_account_archived(&account, false).unwrap();
    let receipt = capture::confirm_review(&draft)?;
    assert!(capture::get(&draft.id).is_none());
    assert_eq!(
        journal::balance_on(&finance::transactions(), &account, today.0),
        10000
    );
    assert_eq!(finance::checks().len(), 1);
    assert_eq!(finance::holdings().trades.len(), 2);
    assert!(capture::confirm_review(&draft).is_err());
    assert_eq!(crate::data::meals::all().len(), 1);
    assert_eq!(
        crate::data::meals::all()[0].photo.as_deref(),
        Some("lunch.png")
    );
    assert_eq!(weights::on(today).unwrap().kg, 62.3);
    assert_eq!(
        crate::data::notes::between(today, today)[0].1,
        "Walked to work"
    );
    assert_eq!(
        db::with(|c| manual_price(c, "fund", today))
            .unwrap()
            .unwrap(),
        Some(2345678)
    );
    let count = finance::transactions().len();
    // Editing one record rejects Undo of the entire batch, including records
    // visited before that row. Leave both the owner's later edit and the batch.
    db::with(|c| {
        c.execute(
            "UPDATE review_notes SET text='Changed independently' WHERE day=?1",
            [&day],
        )
    })
    .unwrap()
    .unwrap();
    assert!(undo(&receipt).is_err());
    assert_eq!(
        db::with(navi_health::store::meals).unwrap().unwrap().len(),
        1
    );
    assert_eq!(
        db::with(repository::transactions).unwrap().unwrap().len(),
        count
    );
    db::with(|c| {
        c.execute(
            "UPDATE review_notes SET text='Walked to work' WHERE day=?1",
            [&day],
        )
    })
    .unwrap()
    .unwrap();
    undo(&receipt)?;
    assert_eq!(finance::transactions(), before);
    assert!(finance::checks().is_empty());
    assert_eq!(weights::on(today).unwrap().kg, 61.2);
    assert!(crate::data::notes::between(today, today).is_empty());
    assert!(crate::data::meals::all().is_empty());
    assert!(
        db::with(|c| manual_price(c, "fund", today))
            .unwrap()
            .unwrap()
            .is_none()
    );
    assert!(undo(&receipt).is_err());
    db::with(repository::validate).unwrap().unwrap();

    // A late storage failure must not consume the draft or commit the trade,
    // typed note, manual quote audit or change to the previous weight.
    capture::put(draft.clone())?;
    db::with(|c|c.execute_batch("CREATE TRIGGER fail_last BEFORE INSERT ON finance_balance_checks BEGIN SELECT RAISE(ABORT,'full'); END;")).unwrap().unwrap();
    assert!(capture::confirm_review(&draft).is_err());
    assert!(capture::get(&draft.id).is_some());
    db::with(|c| {
        assert_eq!(repository::transactions(c).unwrap(), before);
        assert!(store::load(c).unwrap().quotes.is_empty());
        assert!(navi_health::store::meals(c).unwrap().is_empty());
        c.execute_batch("DROP TRIGGER fail_last").unwrap();
    });
    let receipt = capture::confirm_review(&draft)?;
    undo(&receipt)?;
    // Buying a new verified listing creates the security, binding, trade and
    // journal entry only at confirmation. Undo releases the new identity.
    db::with(|c| {
        navi_finance::catalog::install(
            c,
            include_str!(
                "../../../../../../tool/asset_catalog/tests/fixtures/catalog-sample.ndjson"
            ),
        )
    })
    .unwrap()
    .unwrap();
    catalog::load()?;
    let usd = Account::parse("资产/USD:Broker").unwrap();
    finance::create_account(usd).unwrap();
    let mut first = capture::new();
    first.input = "Buy Apple AAPL with Broker".into();
    parsed(
        &mut first,
        json!([{"kind":"trade","day":day,"trade":{"security":"AAPL","kind":"buy","currency":"USD","quantity":"1","unit_price":"100","cash":"资产/USD:Broker","fee":null,"amount":null}}]),
    );
    assert!(trade_security_name("AAPL", Currency::USD).is_some());
    assert!(trade_security_name("UNKNOWN", Currency::USD).is_none());
    capture::put(first.clone())?;
    let undo_first = capture::confirm_review(&first)?;
    assert!(
        db::with(navi_finance::catalog::bindings)
            .unwrap()
            .unwrap()
            .iter()
            .any(|b| b.symbol == "AAPL")
    );
    undo(&undo_first)?;
    assert_eq!(finance::holdings().securities, vec![security]);
    assert!(
        db::with(navi_finance::catalog::bindings)
            .unwrap()
            .unwrap()
            .is_empty()
    );
    capture::put(first.clone())?;
    let undo_first = capture::confirm_review(&first)?;
    // Once held, the public ticker resolves through the stored binding even
    // with the verified catalog removed and no holding list in the prompt.
    db::with(|c| c.execute("DELETE FROM securities_catalog", []))
        .unwrap()
        .unwrap();
    catalog::load()?;
    let mut mark = capture::new();
    mark.input = "AAPL.US closed at USD 0".into();
    parsed(
        &mut mark,
        json!([{"kind":"price","day":day,"price":{"security":"AAPL.US","currency":"USD","unit_price":"0"}}]),
    );
    assert!(price_security_name("AAPL.US", Currency::USD).is_some());
    capture::put(mark.clone())?;
    let undo_mark = capture::confirm_review(&mark)?;
    assert_eq!(finance::holdings().quotes[0].price, 0);
    undo(&undo_mark)?;
    assert!(
        undo(&undo_first).is_err(),
        "keep the holding identity referenced by later price audit"
    );
    Ok(())
}
#[component]
fn BatchProbe() -> impl IntoElement {
    let result = signal(String::from("ready"));
    view().child(text(move || result.get())).child(
        text("exercise")
            .on_press(move || result.set(exercise().err().unwrap_or_else(|| "passed".into()))),
    )
}
#[test]
fn mixed_capture_commits_and_undoes_all_seven_records_as_one() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<BatchProbe>())).unwrap();
    app.wait_for("ready").unwrap();
    app.press("exercise").unwrap();
    app.wait_for("passed").unwrap();
}

#[test]
fn financial_payloads_reject_cross_kind_data_fractional_minor_units_and_guessed_ranges() {
    let item = json!({"day":"2026-11-20","kind":"balance","balance":{"account":"负债:Credit","actual":"30.12"}});
    let parse = |v| model::parse(&json!({"records":[v]}).to_string());
    let parsed = parse(item.clone()).unwrap().0;
    assert!(matches!(&parsed[0], Record::Balance { actual: -3012, .. }));
    let mut bad = item.clone();
    bad["balance"]["actual"] = json!("30.123");
    assert!(parse(bad).is_err());
    let mut bad = item.clone();
    bad["note"] = json!("unexpected");
    assert!(parse(bad).is_err());
    let mut bad = item;
    bad["balance"]["actual"] = json!(30.12);
    assert!(parse(bad).is_err());
    let trade = json!({"day":"2026-11-20","kind":"trade","trade":{"security":"fund","currency":"HKD","kind":"buy","quantity":"1.0000001","unit_price":"1.0","cash":null,"fee":null,"amount":null}});
    assert!(parse(trade).is_err());
}

#[test]
fn private_holdings_resolve_unique_names_ids_and_bound_exchange_codes_without_catalog() {
    let hk = Currency::HKD;
    let owner = Security::new_in("owner-7", "腾讯控股", hk).unwrap();
    let mut book = Book {
        securities: vec![owner.clone()],
        ..Book::default()
    };
    let b = SecurityBinding {
        security: "owner-7".into(),
        market: "hk_stock".into(),
        symbol: "0700.HK".into(),
        currency: "HKD".into(),
    };
    for name in [
        "owner-7",
        "id:owner-7",
        "腾讯控股",
        "00700",
        "00700.HK",
        "hk_stock:0700.HK",
    ] {
        assert_eq!(
            resolve_security(name, hk, &book, None, std::slice::from_ref(&b)),
            Some((owner.clone(), None))
        );
    }
    assert!(resolve_security("腾讯", hk, &book, None, std::slice::from_ref(&b)).is_none());
    assert!(
        resolve_security(
            "腾讯控股",
            Currency::USD,
            &book,
            None,
            std::slice::from_ref(&b)
        )
        .is_none()
    );
    book.securities
        .push(Security::new_in("owner-8", "第二账户", hk).unwrap());
    let b2 = SecurityBinding {
        security: "owner-8".into(),
        ..b.clone()
    };
    assert!(resolve_security("00700", hk, &book, None, &[b, b2]).is_none());
}
