use super::*;
#[derive(Clone)]
pub(super) struct Allocation {
    pub wealth: CurrencyWealth,
    pub investment: Decimal,
    pub cash: Decimal,
    pub missing: usize,
}
pub(super) fn allocations(v: &WealthSnapshot) -> Result<Vec<Allocation>, String> {
    let mut groups = std::collections::BTreeMap::new();
    for c in &v.currencies {
        groups.insert(c.currency.clone(), c.clone());
    }
    for h in &v.holdings {
        if h.quantity != Decimal::ZERO {
            groups.entry(h.currency.clone()).or_insert(CurrencyWealth {
                currency: h.currency.clone(),
                assets: Decimal::ZERO,
                liabilities: Decimal::ZERO,
                net: Decimal::ZERO,
            });
        }
    }
    groups
        .into_values()
        .map(|c| {
            let holdings = v
                .holdings
                .iter()
                .filter(|h| h.currency == c.currency && h.quantity != Decimal::ZERO)
                .collect::<Vec<_>>();
            let missing = holdings.iter().filter(|h| h.market_value.is_none()).count();
            let investment = holdings
                .iter()
                .filter_map(|h| h.market_value)
                .try_fold(Decimal::ZERO, |a, b| a.checked_add(b))
                .ok_or("已知投资金额超出范围")?;
            let cash = c
                .assets
                .checked_sub(investment)
                .ok_or("已知现金金额超出范围")?;
            Ok(Allocation {
                wealth: c,
                investment,
                cash,
                missing,
            })
        })
        .collect()
}
pub(super) struct HistoryWindow {
    pub points: Vec<WealthHistoryPoint>,
    pub label: &'static str,
}
pub(super) fn history_window(points: Vec<WealthHistoryPoint>, as_of: i64) -> HistoryWindow {
    let cutoff = as_of.saturating_sub(30 * 86400);
    let recent = points
        .iter()
        .filter(|p| p.as_of >= cutoff && p.as_of <= as_of)
        .cloned()
        .collect::<Vec<_>>();
    if recent.iter().filter(|p| p.net_worth.is_some()).count() >= 3 {
        HistoryWindow {
            points: recent,
            label: "近30天",
        }
    } else {
        HistoryWindow {
            points,
            label: "全部历史",
        }
    }
}
#[cfg(test)]
#[path = "summary_tests.rs"]
mod tests;
