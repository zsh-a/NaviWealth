//! The headline and FX drill-down consume the same reactive valuation. Labels
//! are recomputed with the underlying balances, positions, dated rates and day.
use super::*;
use navi_finance::currency::Currency;
use std::{collections::BTreeMap, rc::Rc};

#[derive(Default, PartialEq)]
pub(crate) struct Excluded {
    pub cash: Vec<String>,
    pub debt: Vec<String>,
    pub holdings: Vec<String>,
}

impl Excluded {
    pub fn count(&self) -> usize {
        self.cash.len() + self.debt.len() + self.holdings.len()
    }

    pub fn groups(&self) -> impl Iterator<Item = (&'static str, &[String])> {
        [
            (s().cash_accounts, self.cash.as_slice()),
            (s().debt_accounts, self.debt.as_slice()),
            (s().holdings, self.holdings.as_slice()),
        ]
        .into_iter()
        .filter(|(_, names)| !names.is_empty())
    }
}

#[derive(PartialEq)]
pub(crate) struct Overview {
    pub net: assets::Snapshot,
    pub balances: BTreeMap<Account, i64>,
    pub excluded: BTreeMap<Currency, Excluded>,
    pub has_open_holdings: bool,
    pub has_included_holdings: bool,
    pub at_cost: Vec<(String, String)>,
}

pub(crate) fn provide() {
    provide_context(computed(|| {
        let entries = finance::transactions_snapshot();
        let book = finance::holdings_snapshot();
        let rates = finance::rates_snapshot();
        let day = clock::today().0;
        let valued = book.overview_with_rates(&entries, day, &rates).ok()?;
        let balances = journal::balances(entries.iter().filter(|t| t.at.date() <= day));
        let mut excluded: BTreeMap<_, _> = valued
            .missing
            .into_iter()
            .map(|c| (c, Excluded::default()))
            .collect();
        for (account, &value) in &balances {
            if value != 0
                && account.is_cash()
                && let Some(group) = excluded.get_mut(&account.currency())
            {
                let names = if account.kind() == AccountKind::Liabilities {
                    &mut group.debt
                } else {
                    &mut group.cash
                };
                names.push(account.name().to_owned());
            }
        }
        let mut overview = Overview {
            net: valued.snapshot,
            balances,
            excluded,
            has_open_holdings: false,
            has_included_holdings: false,
            at_cost: Vec::new(),
        };
        for security in &book.securities {
            let position = book.position(security, day).ok()?;
            if position.quantity == 0 {
                continue;
            }
            overview.has_open_holdings = true;
            if let Some(group) = overview.excluded.get_mut(&security.currency()) {
                group.holdings.push(security.name.clone());
            } else {
                overview.has_included_holdings = true;
                if position.value.is_none() {
                    overview
                        .at_cost
                        .push((security.id.clone(), security.name.clone()));
                }
            }
        }
        Some(Rc::new(overview))
    }));
}

pub(crate) fn get() -> Option<Rc<Overview>> {
    use_context::<Memo<Option<Rc<Overview>>>>()
        .expect("app provides the current valuation")
        .get()
}
