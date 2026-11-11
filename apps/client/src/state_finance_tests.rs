use super::*;
use naviwealth_finance::{
    daily::RecordSource,
    models::AccountCategory,
    operations::{CloseStep, IssueDisposition},
    planning::{Budget, FlowKind, OccurrenceState, Recurring},
    wealth::{AssetDraft, OperationDraft, OperationKind},
};
fn dec(value: i64) -> Decimal {
    Decimal::from(value)
}
fn day(value: &str) -> i64 {
    crate::ui::date_to_secs(value).unwrap()
}

#[test]
fn core_finance_adoption_and_backup_preserve_references_and_correction_paths() {
    let services = Services::init_at(None).unwrap();
    services.runtime.block_on(async{
        let cash=services.create_account(NewAccount::custody(AccountCategory::Bank,"Recovery bank","CNY"),Some(dec(1000))).await.unwrap();
        let broker=services.create_account(NewAccount::custody(AccountCategory::Broker,"Recovery broker","CNY"),None).await.unwrap();
        let category=services.finance_categories(crate::finance::RecordKind::Expense).await.unwrap()[0].0.clone();
        let budget=services.save_finance_budget(Budget{month:"2026-08".into(),category_id:category.clone(),currency:"CNY".into(),limit:dec(500)}).await.unwrap();
        let recurring=services.save_finance_recurring(None,Recurring{name:"Recovery bill".into(),kind:FlowKind::Bill,account_id:cash.id.clone(),category_id:category.clone(),currency:"CNY".into(),amount:dec(25),first_due:day("2026-08-01"),interval_months:1,end_due:Some(day("2026-08-01")),paused:false}).await.unwrap();
        let bill=services.resolve_finance_occurrence(recurring.clone(),day("2026-08-01"),true).await.unwrap().unwrap();
        assert_eq!(services.finance_record(&bill).await.unwrap().source,RecordSource::Planning);
        assert!(services.delete_finance_record(&bill).await.is_err());
        let asset=services.save_wealth_asset(None,AssetDraft{kind:"stock".into(),name:"Recovery asset".into(),market:None,symbol:None,currency:"CNY".into(),note:Some("Keep system-account:local-only in prose".into())}).await.unwrap();
        let trade=services.save_wealth_operation(None,OperationDraft{kind:OperationKind::Opening,asset_id:asset.id.clone(),account_id:broker.id.clone(),cash_account_id:None,date:day("2026-08-01"),quantity:dec(2),unit_price:dec(100),fees:Decimal::ZERO,amount:Decimal::ZERO,note:None}).await.unwrap();
        services.save_wealth_price(asset.id.clone(),dec(130),day("2026-08-02"),Some("manual".into())).await.unwrap();
        let projected=services.finance_record(&trade.id).await.unwrap();
        assert_eq!(projected.source,RecordSource::Wealth);
        assert_eq!(projected.amount,dec(200)); // Quantity 2 is not an amount of money.
        assert!(!projected.editable);
        assert!(services.delete_finance_record(&trade.id).await.is_err());
        let session=services.finance_import_csv("Recovery CSV".into(),"date,amount,currency,direction,counterparty,note\n2026-08-02,12.50,CNY,expense,Coffee,Recovery".into()).await.unwrap();
        services.finance_assign_import_account(session.id.clone(),cash.id.clone()).await.unwrap();
        let row=services.finance_import_rows(session.id.clone()).await.unwrap().remove(0);let mut review=row.draft.unwrap();review.category_id=Some(category);
        services.finance_review_import_row(session.id.clone(),row.id,review).await.unwrap();
        let receipt=services.finance_confirm_import(session.id.clone()).await.unwrap();
        let reconciliation=services.finance_create_reconciliation(cash.id.clone(),day("2026-08-31"),dec(900),"Bank statement".into()).await.unwrap();
        let reconciliation=services.finance_confirm_reconciliation(reconciliation.id).await.unwrap();
        let adjustment=reconciliation.journal_id.clone().unwrap();
        assert_eq!(services.finance_record(&adjustment).await.unwrap().source,RecordSource::Reconciliation);
        assert!(services.delete_finance_record(&adjustment).await.is_err());
        services.finance_review_month_step("2026-08".into(),CloseStep::ImportReview,"Reviewed".into(),None).await.unwrap();
        let issues=services.finance_inbox(day("2026-08-31")).await.unwrap();
        if let Some(issue)=issues.first(){services.finance_note_issue(issue.key.clone(),IssueDisposition::Dismissed,"Reviewed, retain source".into(),day("2026-08-31")).await.unwrap();}
        let session_auth=AuthSession{access_token:"token".into(),token_type:"Bearer".into(),expires_at:lifeos::ids::now_secs()+3600,user_id:"finance-owner".into(),device_id:services.device_id.clone()};
        services.store_session(session_auth,"https://example.com").await.unwrap();
        assert_eq!(services.owner(),"finance-owner");
        let budgets=services.finance_budgets("2026-08".into()).await.unwrap();
        assert_eq!(budgets.len(),1);assert_ne!(budgets[0].id,budget);assert_eq!(budgets[0].spent,Decimal::from_str_exact("37.50").unwrap());
        let occurrences=services.finance_occurrences(day("2026-08-01"),day("2026-09-01")).await.unwrap();
        assert_eq!(occurrences.len(),1);assert_eq!(occurrences[0].state,OccurrenceState::Posted);
        let migrated_bill=occurrences[0].journal_id.clone().unwrap();assert_ne!(migrated_bill,bill);
        assert_eq!(services.finance_record(&migrated_bill).await.unwrap().source,RecordSource::Planning);
        assert_eq!(services.finance_month_closes().await.unwrap().len(),1);
        let holdings=services.wealth_snapshot(lifeos::ids::now_secs(),"CNY".into()).await.unwrap().holdings;
        assert_eq!(holdings[0].quantity,dec(2));assert_eq!(holdings[0].market_value,Some(dec(260)));
        assert_eq!(services.wealth_asset(asset.id.clone()).await.unwrap().details.note.as_deref(),Some("Keep system-account:local-only in prose"));
        // Receipt HLCs were re-stamped only where they matched the original
        // journal, so both correction paths remain usable after sign-in.
        services.finance_undo_reconciliation(reconciliation.id.clone()).await.unwrap();
        services.finance_undo_import(session.id.clone()).await.unwrap();
        assert!(services.finance_record(&receipt.entry_ids[0]).await.is_err());
        services.undo_finance_occurrence(recurring.clone(),day("2026-08-01")).await.unwrap();
        assert_eq!(services.finance_occurrences(day("2026-08-01"),day("2026-09-01")).await.unwrap()[0].state,OccurrenceState::Due);
        let path=std::env::temp_dir().join(format!("finance-core-{}.bak",uuid::Uuid::new_v4()));
        services.backup_export(path.clone(),"finance recovery password".into()).await.unwrap();
        services.delete_wealth_operation(trade.id.clone()).await.unwrap();
        assert!(services.wealth_snapshot(lifeos::ids::now_secs(),"CNY".into()).await.unwrap().holdings.is_empty());
        services.backup_import(path.clone(),"finance recovery password".into()).await.unwrap();
        std::fs::remove_file(path).unwrap();
        assert_eq!(services.wealth_snapshot(lifeos::ids::now_secs(),"CNY".into()).await.unwrap().holdings[0].market_value,Some(dec(260)));
        assert_eq!(services.finance_month_closes().await.unwrap().len(),1);
        services.delete_wealth_operation(trade.id).await.unwrap();
    });
}

#[test]
fn adoption_preserves_incomplete_journal_revisions_instead_of_validating_them() {
    let services = Services::init_at(None).unwrap();
    services.runtime.block_on(async{
        let account=services.create_account(NewAccount::custody(AccountCategory::Bank,"Partial receipt","CNY"),None).await.unwrap();
        let category=services.finance_categories(crate::finance::RecordKind::Expense).await.unwrap()[0].0.clone();
        let batch=services.finance_import_csv("Partial sync".into(),"date,amount,currency,direction,counterparty,note\n2026-08-01,10,CNY,expense,Coffee,Original".into()).await.unwrap();
        services.finance_assign_import_account(batch.id.clone(),account.id).await.unwrap();
        let row=services.finance_import_rows(batch.id.clone()).await.unwrap().remove(0);let mut draft=row.draft.unwrap();draft.category_id=Some(category);
        services.finance_review_import_row(batch.id.clone(),row.id,draft).await.unwrap();
        let receipt=services.finance_confirm_import(batch.id.clone()).await.unwrap();
        let journal=receipt.entry_ids[0].clone();let st=services.stamper();
        services.db.call(move|conn|{
            let stamp=st.stamp(conn)?;
            conn.execute("UPDATE \"fin:postings\" SET hlc=?1 WHERE id=(SELECT id FROM \"fin:postings\" WHERE journal_entry_id=?2 LIMIT 1)",rusqlite::params![stamp.hlc,journal])?;
            Ok(())
        }).await.unwrap();
        services.store_session(AuthSession{access_token:"token".into(),token_type:"Bearer".into(),expires_at:lifeos::ids::now_secs()+3600,user_id:"partial-owner".into(),device_id:services.device_id.clone()},"https://example.com").await.unwrap();
        let before=services.outbox_count().await.unwrap();
        assert!(services.finance_undo_import(batch.id.clone()).await.is_err());
        assert_eq!(services.outbox_count().await.unwrap(),before);
        assert_eq!(services.finance_imports().await.unwrap()[0].status,naviwealth_finance::operations::ImportStatus::Confirmed);
        assert!(services.finance_record(&receipt.entry_ids[0]).await.is_ok());
    });
}
