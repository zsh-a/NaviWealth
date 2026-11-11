//! Application adapter for the FinanceOS daily ledger use cases.

use crate::state::Services;
pub use naviwealth_finance::daily::{FinanceRecord, RecordDraft, RecordFilter, RecordKind};
use naviwealth_finance::{daily, models::Account, repos::account_repository::AccountBalance};
use rust_decimal::Decimal;

impl Services {
    pub async fn finance_accounts(
        &self,
        include_archived: bool,
    ) -> Result<Vec<(Account, Option<AccountBalance>)>, String> {
        let owner = self.owner();
        self.db
            .call(move |conn| Ok(daily::list_accounts(conn, &owner, include_archived)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_categories(
        &self,
        kind: RecordKind,
    ) -> Result<Vec<(String, String)>, String> {
        let owner = self.owner();
        self.db
            .call(move |conn| Ok(daily::categories(conn, &owner, kind)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_records(
        &self,
        filter: RecordFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FinanceRecord>, String> {
        let owner = self.owner();
        self.db
            .call(move |conn| Ok(daily::records(conn, &owner, &filter, limit, offset)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_record(&self, id: &str) -> Result<FinanceRecord, String> {
        let owner = self.owner();
        let id = id.to_owned();
        self.db
            .call(move |conn| Ok(daily::record(conn, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_record(
        &self,
        id: Option<String>,
        draft: RecordDraft,
    ) -> Result<(), String> {
        let stamper = self.stamper();
        self.db
            .call(move |conn| Ok(daily::save(conn, &stamper, id.as_deref(), &draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn delete_finance_record(&self, id: &str) -> Result<(), String> {
        let stamper = self.stamper();
        let id = id.to_owned();
        self.db
            .call(move |conn| Ok(daily::delete_record(conn, &stamper, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn update_finance_account(
        &self,
        id: &str,
        name: String,
        institution: Option<String>,
        note: Option<String>,
    ) -> Result<(), String> {
        let stamper = self.stamper();
        let id = id.to_owned();
        self.db
            .call(move |conn| {
                Ok(daily::update_account(
                    conn,
                    &stamper,
                    &id,
                    name,
                    institution,
                    note,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn archive_finance_account(&self, id: &str, archived: bool) -> Result<(), String> {
        let stamper = self.stamper();
        let id = id.to_owned();
        self.db
            .call(move |conn| Ok(daily::archive_account(conn, &stamper, &id, archived)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn delete_finance_account(&self, id: &str) -> Result<(), String> {
        let stamper = self.stamper();
        let id = id.to_owned();
        self.db
            .call(move |conn| Ok(daily::delete_account(conn, &stamper, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_monthly_totals(
        &self,
        from: i64,
        until: i64,
    ) -> Result<Vec<(String, Decimal, Decimal)>, String> {
        let owner = self.owner();
        self.db
            .call(move |conn| Ok(daily::monthly_totals(conn, &owner, from, until)?))
            .await
            .map_err(|e| e.to_string())
    }
}
