//! Income, expense and transfer capture share one guarded full-page editor.
use crate::{
    finance::{RecordDraft, RecordKind},
    state::Services,
    ui,
};
use nsh_base::{SheetEvent, dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Clone)]
struct Form {
    kind: Signal<RecordKind>,
    date: Signal<String>,
    amount: Signal<String>,
    account: Signal<String>,
    destination: Signal<String>,
    received: Signal<String>,
    category: Signal<String>,
    payee: Signal<String>,
    note: Signal<String>,
    accounts: Signal<Vec<ui::SelectOption>>,
    categories: Signal<Vec<(String, String)>>,
    budgets: Signal<Vec<naviwealth_finance::planning::BudgetProgress>>,
    currencies: Signal<Vec<(String, String)>>,
    loading: Signal<bool>,
    saving: Signal<bool>,
    error: Signal<String>,
    baseline: Signal<String>,
    discard: Signal<bool>,
}
impl Form {
    fn new() -> Self {
        Self {
            kind: signal(RecordKind::Expense),
            date: signal(ui::today_text()),
            amount: signal(String::new()),
            account: signal(String::new()),
            destination: signal(String::new()),
            received: signal(String::new()),
            category: signal(String::new()),
            payee: signal(String::new()),
            note: signal(String::new()),
            accounts: signal(Vec::new()),
            categories: signal(Vec::new()),
            budgets: signal(Vec::new()),
            currencies: signal(Vec::new()),
            loading: signal(true),
            saving: signal(false),
            error: signal(String::new()),
            baseline: signal(String::new()),
            discard: signal(false),
        }
    }
    fn signature(&self) -> String {
        format!(
            "{:?}|{}|{}|{}|{}|{}|{}|{}|{}",
            self.kind.get(),
            self.date.get(),
            self.amount.get(),
            self.account.get(),
            self.destination.get(),
            self.received.get(),
            self.category.get(),
            self.payee.get(),
            self.note.get()
        )
    }
    fn cancel(&self, open: Signal<bool>) {
        if self.saving.get() {
            return;
        }
        if !self.loading.get() && self.signature() != self.baseline.get() {
            self.discard.set(true);
        } else {
            open.set(false);
        }
    }
    fn currency(&self, account: &str) -> String {
        self.currencies.with(|v| {
            v.iter()
                .find(|(id, _)| id == account)
                .map(|(_, c)| c.clone())
                .unwrap_or_else(|| "CNY".to_owned())
        })
    }
    fn cross_currency(&self) -> bool {
        self.kind.get() == RecordKind::Transfer
            && !self.destination.get().is_empty()
            && self.currency(&self.account.get()) != self.currency(&self.destination.get())
    }
    fn categories(&self, services: Arc<Services>) {
        let state = self.clone();
        let kind = self.kind.get();
        spawn(async move {
            match services.finance_categories(kind).await {
                Ok(items) if state.kind.get() == kind => {
                    if !items.iter().any(|(id, _)| *id == state.category.get()) {
                        state
                            .category
                            .set(items.first().map(|v| v.0.clone()).unwrap_or_default());
                    }
                    state.categories.set(items);
                }
                Err(e) => state.error.set(e),
                _ => {}
            }
        });
    }
    fn load(&self, services: Arc<Services>, edit: Option<String>) {
        let state = self.clone();
        self.loading.set(true);
        self.error.set(String::new());
        spawn(async move {
            let result: Result<(), String> = async {
                state.kind.set(RecordKind::Expense);
                state.date.set(ui::today_text());
                for value in [
                    state.amount,
                    state.account,
                    state.destination,
                    state.received,
                    state.category,
                    state.payee,
                    state.note,
                ] {
                    value.set(String::new());
                }
                let editing = edit.is_some();
                let mut original_category = None;
                if let Some(id) = edit {
                    let record = services.finance_record(&id).await?;
                    original_category =
                        record.category_id.clone().zip(record.category_name.clone());
                    state.kind.set(record.kind);
                    state.date.set(ui::ymd(record.date));
                    state.amount.set(record.amount.normalize().to_string());
                    state.account.set(record.account_id);
                    state
                        .destination
                        .set(record.destination_account_id.unwrap_or_default());
                    state.received.set(
                        record
                            .destination_amount
                            .map(|v| v.normalize().to_string())
                            .unwrap_or_default(),
                    );
                    state.category.set(record.category_id.unwrap_or_default());
                    state.payee.set(record.payee.unwrap_or_default());
                    state.note.set(record.note.unwrap_or_default());
                }
                let accounts = services.finance_accounts(editing).await?;
                let accounts: Vec<_> = accounts
                    .into_iter()
                    .filter(|(a, _)| {
                        !a.archived
                            || a.id == state.account.get()
                            || a.id == state.destination.get()
                    })
                    .collect();
                state.currencies.set(
                    accounts
                        .iter()
                        .map(|(a, _)| (a.id.clone(), a.currency.clone()))
                        .collect(),
                );
                let items: Vec<_> = accounts
                    .into_iter()
                    .map(|(a, _)| ui::SelectOption::account(&a))
                    .collect();
                if state.account.get().is_empty() {
                    state
                        .account
                        .set(items.first().map(|v| v.value.clone()).unwrap_or_default());
                }
                if state.destination.get().is_empty() {
                    state.destination.set(
                        items
                            .iter()
                            .find(|v| v.value != state.account.get())
                            .map(|v| v.value.clone())
                            .unwrap_or_default(),
                    );
                }
                state.accounts.set(items);
                let mut categories = services.finance_categories(state.kind.get()).await?;
                if let Some(original) = original_category
                    && !categories.iter().any(|(id, _)| *id == original.0)
                {
                    categories.push(original);
                }
                if state.category.get().is_empty() {
                    state
                        .category
                        .set(categories.first().map(|v| v.0.clone()).unwrap_or_default());
                }
                state.categories.set(categories);
                Ok(())
            }
            .await;
            if let Err(e) = result {
                state.error.set(e);
            }
            state.baseline.set(state.signature());
            state.loading.set(false);
        });
    }
    fn submit(
        &self,
        services: Arc<Services>,
        edit: Option<String>,
        open: Signal<bool>,
        reload: Signal<u64>,
        source: &'static str,
    ) {
        if self.saving.get() || self.loading.get() {
            return;
        }
        let amount = match Decimal::from_str(self.amount.get().trim()) {
            Ok(v)
                if v > Decimal::ZERO
                    || (self.kind.get() == RecordKind::OpeningBalance && v != Decimal::ZERO) =>
            {
                v
            }
            _ => {
                self.error
                    .set("请输入有效金额，收入、支出和转账金额须大于 0".to_owned());
                return;
            }
        };
        let Some(date) = ui::date_to_secs(&self.date.get()) else {
            self.error.set("请输入有效日期，例如 2026-11-11".to_owned());
            return;
        };
        let received = if self.cross_currency() {
            match self.received.get().trim().parse::<Decimal>() {
                Ok(v) if v > Decimal::ZERO => Some(v),
                _ => {
                    self.error.set("请输入实际到账金额".to_owned());
                    return;
                }
            }
        } else {
            None
        };
        let optional = |v: String| {
            if v.trim().is_empty() {
                None
            } else {
                Some(v.trim().to_owned())
            }
        };
        let draft = RecordDraft {
            kind: self.kind.get(),
            date,
            amount,
            account_id: self.account.get(),
            category_id: optional(self.category.get()),
            destination_account_id: optional(self.destination.get()),
            destination_amount: received,
            payee: optional(self.payee.get()),
            note: optional(self.note.get()),
        };
        self.saving.set(true);
        self.error.set(String::new());
        let created = edit.is_none();
        let state = self.clone();
        spawn(async move {
            match services.save_finance_record(edit, draft).await {
                Ok(id) => {
                    state.saving.set(false);
                    if created {
                        // The undo pill owns the bottom slot for the window.
                        crate::finance_ui::offer_undo(
                            id.clone(),
                            "记录已保存，余额与预算已更新",
                            crate::finance_ui::UndoAction::Remove,
                        );
                    } else {
                        crate::finance_ui::notice("记录已保存，账户余额和预算已更新");
                    }
                    crate::finance_ui::acknowledge_fact(
                        source,
                        "记录已保存；余额与分类预算已更新。若列表未显示，请检查日期和筛选。",
                        Some(id),
                    );
                    reload.update(|v| *v += 1);
                    open.set(false);
                }
                Err(e) => {
                    state.saving.set(false);
                    state.error.set(e);
                }
            }
        });
    }
}

#[path = "record/editor.rs"]
mod editor;
pub use editor::{record_dialog, record_editor};
#[path = "record/categories.rs"]
mod categories;
use categories::category_grid;
