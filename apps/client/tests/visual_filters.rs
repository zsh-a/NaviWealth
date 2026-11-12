//! Visual shortcuts must filter the complete ledger, not just its first page.
use naviwealth_client::{
    Services,
    finance::{RecordDraft, RecordKind},
};
use naviwealth_finance::models::{AccountCategory, NewAccount};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

#[test]
fn renamed_category_shortcut_is_exact_after_two_hundred_other_rows() {
    naviwealth_client::enable_test_mode();
    let s = Services::shared();
    let (wanted, unrelated) = s.runtime.block_on(async {
        let account = s
            .create_account(
                NewAccount::custody(AccountCategory::Cash, "分类筛选账户", "CNY"),
                Some(1000.into()),
            )
            .await
            .unwrap();
        let categories = s.finance_categories(RecordKind::Expense).await.unwrap();
        let shopping = categories
            .iter()
            .find(|(_, n)| n == "购物")
            .unwrap()
            .0
            .clone();
        let dining = categories
            .iter()
            .find(|(_, n)| n == "餐饮")
            .unwrap()
            .0
            .clone();
        let day = chrono::Local::now()
            .date_naive()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp();
        let draft = |date, category, payee: String| RecordDraft {
            kind: RecordKind::Expense,
            date,
            amount: 1.into(),
            account_id: account.id.clone(),
            category_id: Some(category),
            destination_account_id: None,
            destination_amount: None,
            payee: Some(payee),
            note: None,
        };
        let wanted = s
            .save_finance_record(None, draft(day, shopping, "历史购物".into()))
            .await
            .unwrap();
        let mut unrelated = String::new();
        for i in 1..=205 {
            // Generic text search would incorrectly include these dining rows.
            unrelated = s
                .save_finance_record(
                    None,
                    draft(day + i, dining.clone(), format!("购物中心餐饮{i}")),
                )
                .await
                .unwrap();
        }
        let owner=s.owner();
        s.db.call(move |conn| {
            conn.execute(r#"UPDATE "fin:categories" SET name_override='衣物与日用品' WHERE owner_user_id=?1 AND system_key='shopping'"#,[owner])?;
            Ok(())
        }).await.unwrap();
        (wanted, unrelated)
    });
    let mut app = Headless::start(EngineConfig::new(Root::of::<naviwealth_client::App>())).unwrap();
    app.wait_for("id:ledger-load-more").unwrap();
    app.press("id:ledger-category-购物").unwrap();
    app.wait_for(&format!("id:record-{wanted}")).unwrap();
    app.wait_for_gone("id:ledger-load-more", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(
        app.screen()
            .count(&format!("id:record-{unrelated}"))
            .unwrap(),
        0
    );
    app.press("id:ledger-category-全部").unwrap();
    app.wait_for(&format!("id:record-{unrelated}")).unwrap();
}
