//! Thin application adapter for reviewed imports and financial operations.
use crate::state::Services;
use naviwealth_finance::operations;
#[allow(unused_imports)]
pub use naviwealth_finance::operations::{
    CloseStep, CloseStepReadiness, CloseStepReview, CloseStepStatus, FinancialIssue,
    ImportConfirmation, ImportPreview, ImportPreviewRow, ImportRow, ImportSession, ImportStatus,
    ImportUndoReadiness, IssueDisposition, IssueKind, IssueNote, MonthClose, MonthCloseReadiness,
    MonthlyAccount, MonthlySnapshot, MonthlyTotals, ParsedRow, ParsedStatement, Reconciliation,
    ReconciliationStatus, RowReview, STATEMENT_CSV_HEADER, export_statement_csv,
    parse_statement_csv,
};
use rust_decimal::Decimal;
impl Services {
    pub async fn finance_import_undo_readiness(
        &self,
        session_id: String,
    ) -> Result<ImportUndoReadiness, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::import_undo_readiness(c, &owner, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn finance_cancel_reconciliation(&self, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::cancel_reconciliation(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn finance_import_preview(
        &self,
        session_id: String,
    ) -> Result<ImportPreview, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::preview_import(c, &owner, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_cancel_import(&self, session_id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::cancel_import(c, &st, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn finance_import_csv(
        &self,
        source_name: String,
        csv: String,
    ) -> Result<ImportSession, String> {
        let parsed = parse_statement_csv(&csv).map_err(|e| e.to_string())?;
        self.finance_create_import(source_name, parsed).await
    }
    pub async fn finance_create_import(
        &self,
        source_name: String,
        parsed: ParsedStatement,
    ) -> Result<ImportSession, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::create_import(c, &st, &source_name, &parsed)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_imports(&self) -> Result<Vec<ImportSession>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::imports(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_import_rows(&self, session_id: String) -> Result<Vec<ImportRow>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::import_rows(c, &owner, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_assign_import_account(
        &self,
        session_id: String,
        account_id: String,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::assign_import_account(
                    c,
                    &st,
                    &session_id,
                    &account_id,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_review_import_row(
        &self,
        session_id: String,
        row_id: String,
        review: RowReview,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::review_import_row(
                    c,
                    &st,
                    &session_id,
                    &row_id,
                    review,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_exclude_import_row(
        &self,
        session_id: String,
        row_id: String,
        reason: String,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::exclude_import_row(
                    c,
                    &st,
                    &session_id,
                    &row_id,
                    &reason,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_confirm_import(
        &self,
        session_id: String,
    ) -> Result<ImportConfirmation, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::confirm_import(c, &st, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_undo_import(&self, session_id: String) -> Result<usize, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::undo_import(c, &st, &session_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_reconciliations(&self) -> Result<Vec<Reconciliation>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::reconciliations(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_create_reconciliation(
        &self,
        account_id: String,
        date: i64,
        actual: Decimal,
        note: String,
    ) -> Result<Reconciliation, String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::create_reconciliation(
                    c,
                    &st,
                    &account_id,
                    date,
                    actual,
                    &note,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_confirm_reconciliation(
        &self,
        id: String,
    ) -> Result<Reconciliation, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::confirm_reconciliation(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_undo_reconciliation(&self, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::undo_reconciliation(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_inbox(&self, as_of: i64) -> Result<Vec<FinancialIssue>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::financial_inbox(c, &owner, as_of)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_note_issue(
        &self,
        key: String,
        disposition: IssueDisposition,
        note: String,
        as_of: i64,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::note_financial_issue(
                    c,
                    &st,
                    &key,
                    disposition,
                    &note,
                    as_of,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_month_closes(&self) -> Result<Vec<MonthClose>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::month_closes(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_month_close_readiness(
        &self,
        month: String,
    ) -> Result<MonthCloseReadiness, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(operations::month_close_readiness(c, &owner, &month)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_review_month_step(
        &self,
        month: String,
        step: CloseStep,
        note: String,
        override_reason: Option<String>,
    ) -> Result<MonthCloseReadiness, String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(operations::review_month_close_step(
                    c,
                    &st,
                    &month,
                    step,
                    &note,
                    override_reason.as_deref(),
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_finalize_month_close(
        &self,
        month: String,
    ) -> Result<MonthlySnapshot, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(operations::finalize_month_close(c, &st, &month)?))
            .await
            .map_err(|e| e.to_string())
    }
}
