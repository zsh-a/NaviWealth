//! Month facts and metadata do not subscribe to record search or pagination.
use super::*;
use naviwealth_finance::{daily::ExpenseCategory, planning::BudgetProgress};
use std::{future::Future, pin::Pin};
pub(super) struct MonthData {
    pub composition: Result<Vec<composition::Composition>, String>,
    pub totals: Result<Vec<(String, Decimal, Decimal)>, String>,
    pub budgets: Result<Vec<BudgetProgress>, String>,
}
#[derive(Clone, Copy)]
pub(super) struct MonthFacts {
    pub composition: Signal<Vec<composition::Composition>>,
    pub composition_error: Signal<String>,
    pub totals: Signal<Vec<(String, Decimal, Decimal)>>,
    pub error: Signal<String>,
    pub budgets: Signal<Vec<budget::Summary>>,
}
pub(super) fn month_facts(
    s: Arc<Services>,
    month: Signal<i32>,
    version: Signal<u64>,
) -> MonthFacts {
    observe_month(month, version, move |offset| {
        let s = s.clone();
        let (from, until, _) = month_window(offset);
        Box::pin(async move {
            let (composition, totals, budgets) = tokio::join!(
                composition::load(&s, from, until),
                s.finance_monthly_totals(from, until),
                s.finance_budgets(ui::ymd(from)[..7].into())
            );
            MonthData {
                composition,
                totals,
                budgets,
            }
        })
    })
}
pub(super) fn observe_month(
    month: Signal<i32>,
    version: Signal<u64>,
    fetch: impl Fn(i32) -> Pin<Box<dyn Future<Output = MonthData>>> + 'static,
) -> MonthFacts {
    let facts = MonthFacts {
        composition: signal(vec![]),
        composition_error: signal(String::new()),
        totals: signal(vec![]),
        error: signal(String::new()),
        budgets: signal(vec![]),
    };
    let generation = Rc::new(Cell::new(0));
    let previous = Rc::new(Cell::new(None));
    effect(move || {
        version.get();
        let key = month.get();
        if previous.replace(Some(key)) != Some(key) {
            facts.composition.set(vec![]);
            facts.totals.set(vec![]);
            facts.budgets.set(vec![]);
            facts.composition_error.set(String::new());
            facts.error.set(String::new());
        }
        let n = generation.get() + 1;
        generation.set(n);
        let current = generation.clone();
        let future = fetch(key);
        spawn(async move {
            let data = future.await;
            if current.get() != n {
                return;
            }
            match data.composition {
                Ok(value) => {
                    facts.composition.set(value);
                    facts.composition_error.set(String::new());
                }
                Err(e) => {
                    facts.composition.set(vec![]);
                    facts
                        .composition_error
                        .set(format!("分类构成暂不可用：{e}"));
                }
            }
            match data.totals {
                Ok(value) => {
                    facts.totals.set(value);
                    facts.error.set(String::new());
                }
                Err(e) => {
                    facts.totals.set(vec![]);
                    facts.error.set(e);
                }
            }
            facts.budgets.set(budget::summarize(data.budgets));
        });
    });
    facts
}
#[derive(Clone, Copy)]
pub(super) struct Metadata {
    pub currencies: Signal<ui::RecordCurrencies>,
    pub options: Signal<Vec<ui::SelectOption>>,
    pub count: Signal<usize>,
    pub categories: Signal<Vec<ExpenseCategory>>,
    pub error: Signal<String>,
}
pub(super) fn metadata(s: Arc<Services>, version: Signal<u64>) -> Metadata {
    let state = Metadata {
        currencies: signal(Default::default()),
        options: signal(vec![]),
        count: signal(0),
        categories: signal(vec![]),
        error: signal(String::new()),
    };
    let generation = Rc::new(Cell::new(0));
    effect(move || {
        version.get();
        let n = generation.get() + 1;
        generation.set(n);
        let current = generation.clone();
        let s = s.clone();
        spawn(async move {
            let (accounts, base, categories) = tokio::join!(
                s.finance_accounts(true),
                s.settings_get("finance.base_currency"),
                s.finance_expense_categories()
            );
            if current.get() != n {
                return;
            }
            match (accounts, categories) {
                (Ok(accounts), Ok(categories)) => {
                    state
                        .count
                        .set(accounts.iter().filter(|(a, _)| !a.archived).count());
                    state.currencies.set(ui::RecordCurrencies {
                        base: base.unwrap_or_else(|| "CNY".into()),
                        accounts: accounts
                            .iter()
                            .map(|(a, _)| (a.id.clone(), a.currency.clone()))
                            .collect(),
                    });
                    let mut options = vec![ui::SelectOption::new("", "全部账户")];
                    options.extend(
                        accounts
                            .into_iter()
                            .filter(|(a, _)| !a.archived)
                            .map(|(a, _)| ui::SelectOption::account(&a)),
                    );
                    state.options.set(options);
                    state.categories.set(categories);
                    state.error.set(String::new());
                }
                (Err(e), _) | (_, Err(e)) => state.error.set(e),
            }
        });
    });
    state
}
#[cfg(test)]
#[path = "loading_tests.rs"]
mod tests;
