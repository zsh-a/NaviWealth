//! Thin application adapters for authored wealth and investment workflows.
use crate::state::Services;
pub use naviwealth_finance::wealth::*;
use rust_decimal::Decimal;
impl Services {
    pub async fn wealth_assets(&self, include_archived: bool) -> Result<Vec<WealthAsset>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::assets(
                    c,
                    &owner,
                    include_archived,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_asset(&self, id: String) -> Result<WealthAsset, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::asset(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_wealth_asset(
        &self,
        id: Option<String>,
        draft: AssetDraft,
    ) -> Result<WealthAsset, String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::save_asset(
                    c,
                    &st,
                    id.as_deref(),
                    draft,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn archive_wealth_asset(&self, id: String, archived: bool) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::archive_asset(
                    c, &st, &id, archived,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn delete_wealth_asset(&self, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::delete_asset(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_operations(
        &self,
        asset_id: Option<String>,
    ) -> Result<Vec<WealthOperation>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::operations(
                    c,
                    &owner,
                    asset_id.as_deref(),
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_operation(&self, id: String) -> Result<WealthOperation, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::operation(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_wealth_operation(
        &self,
        id: Option<String>,
        draft: OperationDraft,
    ) -> Result<WealthOperation, String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::save_operation(
                    c,
                    &st,
                    id.as_deref(),
                    draft,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn delete_wealth_operation(&self, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::delete_operation(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_wealth_price(
        &self,
        asset_id: String,
        price: Decimal,
        observed_on: i64,
        source: Option<String>,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                naviwealth_finance::wealth::record_price(
                    c,
                    &st,
                    &asset_id,
                    price,
                    observed_on,
                    source,
                )?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_prices(
        &self,
        asset_id: String,
    ) -> Result<Vec<naviwealth_finance::models::AssetPrice>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::prices(c, &owner, &asset_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_snapshot(
        &self,
        as_of: i64,
        base_currency: String,
    ) -> Result<WealthSnapshot, String> {
        let owner = self.owner();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::snapshot(
                    c,
                    &owner,
                    as_of,
                    &base_currency,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_history(
        &self,
        base_currency: String,
    ) -> Result<Vec<WealthHistoryPoint>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| {
                Ok(naviwealth_finance::wealth::wealth_history(
                    c,
                    &owner,
                    &base_currency,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn wealth_cash_balances(&self, as_of: i64) -> Result<Vec<CashBalance>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(naviwealth_finance::wealth::cash_balances(c, &owner, as_of)?))
            .await
            .map_err(|e| e.to_string())
    }
}

impl Services {
    pub async fn save_wealth_fx(
        &self,
        from: String,
        to: String,
        rate: Decimal,
        as_of: i64,
    ) -> Result<(), String> {
        let stamper = self.stamper();
        self.db
            .call(move |c| {
                naviwealth_finance::wealth::record_manual_fx(c, &stamper, &from, &to, rate, as_of)?;
                Ok(())
            })
            .await
            .map_err(|e| e.to_string())
    }
}
