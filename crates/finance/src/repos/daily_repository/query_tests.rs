use super::*;
use crate::{
    models::{AccountCategory, NewAccount},
    tables,
};
use lifeos::db::migrations::core_migrations;
fn setup() -> (Connection, MutationStamper, Account) {
    let conn = Connection::open_in_memory().unwrap();
    for m in core_migrations().push(tables::migration()).steps() {
        conn.execute_batch(m.sql).unwrap();
    }
    let st = MutationStamper::new("local", "device");
    system_accounts::seed_system_accounts(&conn, &st).unwrap();
    let account = accounts::create(
        &conn,
        &st,
        NewAccount::custody(AccountCategory::Bank, "银行卡", "CNY"),
    )
    .unwrap();
    (conn, st, account)
}
fn draft(
    st: &MutationStamper,
    account: &Account,
    kind: RecordKind,
    amount: Decimal,
) -> RecordDraft {
    RecordDraft {
        kind,
        date: 100 * 86400 + 3600,
        amount,
        account_id: account.id.clone(),
        category_id: match kind {
            RecordKind::Expense => Some(system_accounts::system_account_id(
                &st.owner_user_id,
                "expense:dining",
            )),
            RecordKind::Income => Some(system_accounts::system_account_id(
                &st.owner_user_id,
                "income:salary",
            )),
            _ => None,
        },
        destination_account_id: None,
        destination_amount: None,
        payee: None,
        note: None,
    }
}
#[test]
fn category_filter_uses_identity_after_rename_and_for_custom_categories() {
    let (mut c, st, a) = setup();
    let builtin = expense_categories(&c, "local")
        .unwrap()
        .into_iter()
        .find(|v| v.system_key.as_deref() == Some("dining"))
        .unwrap();
    let first = save(
        &mut c,
        &st,
        None,
        &draft(&st, &a, RecordKind::Expense, 10.into()),
    )
    .unwrap();
    c.execute(
        r#"UPDATE "fin:categories" SET name_override='朋友聚餐' WHERE ledger_account_id=?1"#,
        params![builtin.id],
    )
    .unwrap();
    // A custom category with no system_key; storage fixture only, no production mutation path.
    c.execute(r#"INSERT INTO "fin:accounts" (id,type,name,currency,category,owner_user_id,updated_at,updated_by_device,hlc)
        SELECT 'custom-expense',type,'自定义',currency,category,owner_user_id,updated_at,updated_by_device,hlc FROM "fin:accounts" WHERE id=?1"#,params![builtin.id]).unwrap();
    c.execute(r#"INSERT INTO "fin:categories" (id,name,ledger_account_id,sort_order,archived,owner_user_id,updated_at,updated_by_device,hlc)
        SELECT 'custom-category','宠物照护','custom-expense',sort_order,0,owner_user_id,updated_at,updated_by_device,hlc FROM "fin:categories" WHERE ledger_account_id=?1"#,params![builtin.id]).unwrap();
    let mut custom = draft(&st, &a, RecordKind::Expense, 20.into());
    custom.category_id = Some("custom-expense".into());
    let second = save(&mut c, &st, None, &custom).unwrap();
    let query = |id: &str| {
        records(
            &c,
            "local",
            &RecordFilter {
                category_id: Some(id.into()),
                ..Default::default()
            },
            1,
            0,
        )
        .unwrap()
    };
    assert_eq!(query(&builtin.id)[0].id, first);
    assert_eq!(query("custom-expense")[0].id, second);
    let cats = expense_categories(&c, "local").unwrap();
    assert!(cats.iter().any(|v| v.id == builtin.id
        && v.name == "朋友聚餐"
        && v.system_key.as_deref() == Some("dining")));
    assert!(
        cats.iter()
            .any(|v| v.id == "custom-expense" && v.system_key.is_none())
    );
    assert!(
        records(
            &c,
            "other",
            &RecordFilter {
                category_id: Some(builtin.id),
                ..Default::default()
            },
            200,
            0
        )
        .unwrap()
        .is_empty()
    );
    assert!(
        records(
            &c,
            "local",
            &RecordFilter {
                category_id: Some("custom-expense".into()),
                ..Default::default()
            },
            1,
            1
        )
        .unwrap()
        .is_empty()
    );
}
#[test]
fn daily_spending_matches_expense_legs_without_pagination() {
    let (mut c, st, a) = setup();
    for i in 0..=205 {
        let mut d = draft(&st, &a, RecordKind::Expense, Decimal::new(1, 2));
        d.date += i;
        save(&mut c, &st, None, &d).unwrap();
    }
    save(
        &mut c,
        &st,
        None,
        &draft(&st, &a, RecordKind::Income, 9999.into()),
    )
    .unwrap();
    let dest = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Cash, "现金", "CNY"),
    )
    .unwrap();
    let mut transfer = draft(&st, &a, RecordKind::Transfer, 400.into());
    transfer.destination_account_id = Some(dest.id);
    save(&mut c, &st, None, &transfer).unwrap();
    let jpy = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Bank, "日元账户", "JPY"),
    )
    .unwrap();
    let mut foreign = draft(&st, &jpy, RecordKind::Expense, 900.into());
    foreign.date += 86400;
    save(&mut c, &st, None, &foreign).unwrap();
    let opening = builders::opening_balance(
        100 * 86400,
        &a.id,
        system_accounts::system_account_id("local", "equity:openingBalance"),
        1000.into(),
        "CNY",
        None,
        None,
        vec![],
    )
    .unwrap();
    journal::create(
        &mut c,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        opening,
    )
    .unwrap();
    let from = 100 * 86400;
    let until = from + 2 * 86400;
    let rows = daily_spending(&c, "local", from, until).unwrap();
    assert_eq!(
        rows,
        vec![
            DailySpending {
                date: from,
                currency: "CNY".into(),
                amount: Decimal::new(206, 2)
            },
            DailySpending {
                date: from + 86400,
                currency: "JPY".into(),
                amount: 900.into()
            }
        ]
    );
    let totals = monthly_totals(&c, "local", from, until).unwrap();
    for row in rows {
        assert_eq!(
            totals
                .iter()
                .find(|(cur, _, _)| *cur == row.currency)
                .unwrap()
                .2,
            row.amount
        );
    }
    assert!(daily_spending(&c, "other", from, until).unwrap().is_empty());
    assert!(daily_spending(&c, "local", until, until).is_err());
    assert!(
        daily_spending(&c, "local", until, until + 86400)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn category_filter_matches_split_entry_legs_without_a_primary_category() {
    let (mut c, st, a) = setup();
    let dining = system_accounts::system_account_id("local", "expense:dining");
    let shopping = system_accounts::system_account_id("local", "expense:shopping");
    let mut build = builders::expense(
        100 * 86400,
        &dining,
        &a.id,
        30.into(),
        "CNY",
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    build
        .postings
        .iter_mut()
        .find(|p| p.account_id == dining)
        .unwrap()
        .units = 20.into();
    build.postings.push(builders::PostingDraft {
        position: 2,
        account_id: shopping.clone(),
        units: 10.into(),
        unit: "CNY".into(),
        cost: None,
        price: None,
    });
    let id = journal::create(
        &mut c,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        build,
    )
    .unwrap()
    .entry
    .id;
    for category in [dining, shopping] {
        let rows = records(
            &c,
            "local",
            &RecordFilter {
                category_id: Some(category),
                ..Default::default()
            },
            200,
            0,
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, id);
        assert_eq!(rows[0].category_id, None);
    }
    assert_eq!(
        daily_spending(&c, "local", 100 * 86400, 101 * 86400).unwrap()[0].amount,
        Decimal::from(30)
    );
}
