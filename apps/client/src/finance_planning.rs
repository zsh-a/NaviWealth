//! Thin application adapter: planning facts and calculations stay in Finance.
use crate::state::Services;
use naviwealth_finance::planning as p;
pub use naviwealth_finance::planning::*;
use rust_decimal::Decimal;

impl Services {
    pub async fn update_finance_liability(
        &self,
        id: String,
        draft: LiabilityDraft,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::update_liability(c, &st, &id, draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn delete_finance_liability(&self, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::delete_liability(c, &st, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn archive_finance_liability(
        &self,
        id: String,
        archived: bool,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::archive_liability(c, &st, &id, archived)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_rebalance_receipts(
        &self,
        id: String,
    ) -> Result<Vec<Stored<RebalanceReceipt>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::rebalance_receipts(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_contribution_candidates(
        &self,
        id: String,
    ) -> Result<Vec<ContributionCandidate>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::contribution_candidates(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn unlink_finance_goal_contribution(
        &self,
        goal_id: String,
        journal_id: String,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::unlink_goal_contribution(c, &st, &goal_id, &journal_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_budget(&self, id: String) -> Result<BudgetProgress, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::budget(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn remove_finance_plan(&self, kind: PlanKind, id: String) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::remove_plan(c, &st, kind, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_cash_scenarios(&self) -> Result<Vec<Stored<CashScenario>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::cash_scenarios(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_cash_scenario(
        &self,
        id: Option<String>,
        draft: CashScenario,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_cash_scenario(c, &st, id.as_deref(), draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn undo_finance_dca_occurrence(
        &self,
        plan_id: String,
        due: i64,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::undo_dca_occurrence(c, &st, &plan_id, due)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn unlink_finance_rebalance_trade(
        &self,
        plan_id: String,
        operation_id: String,
        restore_inclusions: bool,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| {
                Ok(p::unlink_rebalance_trade(
                    c,
                    &st,
                    &plan_id,
                    &operation_id,
                    restore_inclusions,
                )?)
            })
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_planning_actions(
        &self,
        from: i64,
        until: i64,
    ) -> Result<Vec<PlanningAction>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::planning_actions(c, &owner, from, until)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_dca_plans(&self) -> Result<Vec<Stored<DcaPlan>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::dca_plans(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_dca(
        &self,
        id: Option<String>,
        draft: DcaPlan,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_dca(c, &st, id.as_deref(), draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_dca_occurrences(
        &self,
        from: i64,
        until: i64,
    ) -> Result<Vec<Occurrence>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::dca_occurrences(c, &owner, from, until)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn link_finance_dca_trade(
        &self,
        plan_id: String,
        due: i64,
        operation_id: String,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::link_dca_trade(c, &st, &plan_id, due, &operation_id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn skip_finance_dca_occurrence(
        &self,
        plan_id: String,
        due: i64,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::skip_dca_occurrence(c, &st, &plan_id, due)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_budgets(&self, month: String) -> Result<Vec<BudgetProgress>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::budgets(c, &owner, &month)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_budget(&self, draft: Budget) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_budget(c, &st, draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_recurring(&self) -> Result<Vec<Stored<Recurring>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::list_recurring(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_recurring(
        &self,
        id: Option<String>,
        draft: Recurring,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_recurring(c, &st, id.as_deref(), draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_occurrences(
        &self,
        from: i64,
        until: i64,
    ) -> Result<Vec<Occurrence>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::occurrences(c, &owner, from, until)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn resolve_finance_occurrence(
        &self,
        template_id: String,
        due: i64,
        post: bool,
    ) -> Result<Option<String>, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::resolve_occurrence(c, &st, &template_id, due, post)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn undo_finance_occurrence(
        &self,
        template_id: String,
        due: i64,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::undo_occurrence(c, &st, &template_id, due)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_liabilities(&self) -> Result<Vec<Stored<Liability>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::liabilities(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn create_finance_liability(&self, draft: LiabilityDraft) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::create_liability(c, &st, draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_liability_schedule(&self, id: String) -> Result<Vec<Installment>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::liability_schedule(c, &owner, &id)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn pay_finance_installment(
        &self,
        id: String,
        index: u32,
        cash_id: String,
        paid_on: i64,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::pay_installment(c, &st, &id, index, &cash_id, paid_on)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn undo_finance_installment(&self, id: String, index: u32) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::undo_installment(c, &st, &id, index)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_runway(
        &self,
        as_of: i64,
        currency: String,
        horizon_days: u32,
    ) -> Result<Runway, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::runway(c, &owner, as_of, &currency, horizon_days)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_goals(&self) -> Result<Vec<GoalProgress>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::goals(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_goal(
        &self,
        id: Option<String>,
        draft: Goal,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_goal(c, &st, id.as_deref(), draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn contribute_finance_goal(
        &self,
        goal_id: String,
        journal_id: String,
        amount: Decimal,
    ) -> Result<(), String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::contribute_goal(c, &st, &goal_id, &journal_id, amount)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_fire_plans(&self) -> Result<Vec<Stored<FirePlan>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::fire_plans(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_fire(
        &self,
        id: Option<String>,
        draft: FirePlan,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_fire(c, &st, id.as_deref(), draft)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_portfolio_plans(&self) -> Result<Vec<Stored<InvestmentPlan>>, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::portfolio_plans(c, &owner)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn save_finance_portfolio_plan(
        &self,
        id: Option<String>,
        draft: InvestmentPlan,
        as_of: i64,
    ) -> Result<String, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::save_portfolio_plan(c, &st, id.as_deref(), draft, as_of)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn finance_portfolio_snapshot(
        &self,
        id: String,
        as_of: i64,
    ) -> Result<PortfolioSnapshot, String> {
        let owner = self.owner();
        self.db
            .call(move |c| Ok(p::portfolio_snapshot(c, &owner, &id, as_of)?))
            .await
            .map_err(|e| e.to_string())
    }
    pub async fn link_finance_rebalance_trade(
        &self,
        plan_id: String,
        operation_id: String,
    ) -> Result<PortfolioSnapshot, String> {
        let st = self.stamper();
        self.db
            .call(move |c| Ok(p::link_rebalance_trade(c, &st, &plan_id, &operation_id)?))
            .await
            .map_err(|e| e.to_string())
    }
}
