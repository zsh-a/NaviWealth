//! A repository page boundary must never truncate the user's visible history.
use naviwealth_client::{
    Services,
    finance::{RecordDraft, RecordKind},
};
use naviwealth_finance::models::{AccountCategory, NewAccount};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
#[test]
fn ledger_load_more_crosses_two_hundred_records() {
    naviwealth_client::enable_test_mode();
    let services = Services::shared();
    let oldest = services.runtime.block_on(async {
        let account = services
            .create_account(
                NewAccount::custody(AccountCategory::Cash, "分页账户", "CNY"),
                None,
            )
            .await
            .unwrap();
        let category = services
            .finance_categories(RecordKind::Expense)
            .await
            .unwrap()
            .remove(0)
            .0;
        let today = chrono::Local::now()
            .date_naive()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp();
        for i in 0..205 {
            services
                .save_finance_record(
                    None,
                    RecordDraft {
                        kind: RecordKind::Expense,
                        date: today + i,
                        amount: 1.into(),
                        account_id: account.id.clone(),
                        category_id: Some(category.clone()),
                        destination_account_id: None,
                        destination_amount: None,
                        payee: Some(format!("分页商家{i}")),
                        note: None,
                    },
                )
                .await
                .unwrap();
        }
        services
            .finance_records(Default::default(), 10, 200)
            .await
            .unwrap()
            .remove(4)
            .id
    });
    let mut app = Headless::start(EngineConfig::new(Root::of::<naviwealth_client::App>())).unwrap();
    for _ in 0..4 {
        app.wait_for("id:ledger-load-more").unwrap();
        app.wait_until(
            "加载更多可用",
            std::time::Duration::from_secs(5),
            |screen| screen.enabled("id:ledger-load-more").unwrap_or(false),
        )
        .unwrap();
        app.press("id:ledger-load-more").unwrap();
    }
    app.wait_for(&format!("id:record-{oldest}")).unwrap();
    app.wait_for_gone("id:ledger-load-more", std::time::Duration::from_secs(5))
        .unwrap();
}
