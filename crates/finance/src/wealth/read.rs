use super::store::{checked, invalid};

pub(super) fn valuation_as_of_at(requested: i64, now: i64, local_day: i64) -> i64 {
    if requested > now && requested.rem_euclid(86_400) == 0 && requested <= local_day {
        return requested;
    }
    let at = requested.min(now);
    if at.div_euclid(86_400) == now.div_euclid(86_400) {
        at.max(local_day)
    } else {
        at
    }
}

/// Current reads include today's local civil-date label. Historical instants
/// in earlier UTC days retain their requested boundary; no future quote
/// instant becomes eligible through this normalization.
pub fn valuation_as_of(requested: i64) -> i64 {
    valuation_as_of_at(
        requested,
        lifeos::ids::now_secs(),
        super::store::local_civil_day(),
    )
}
use super::*;
use crate::{Result, models::AccountSide, repos::account_repository};
use rusqlite::{Connection, params};
use rust_decimal::Decimal;
use std::collections::{BTreeMap, BTreeSet};

/// Ledger cash facts as of an instant, including archived containers. Non-cash
/// units never enter a currency sum. Debt is represented by its signed balance.
pub fn cash_balances(conn: &Connection, owner: &str, as_of: i64) -> Result<Vec<CashBalance>> {
    super::replay::verify(conn, owner, &operations(conn, owner, None)?)?;
    cash_balances_verified(conn, owner, valuation_as_of(as_of))
}

fn cash_balances_verified(conn: &Connection, owner: &str, as_of: i64) -> Result<Vec<CashBalance>> {
    let mut sums: BTreeMap<(String, String), Decimal> = BTreeMap::new();
    let mut q = conn.prepare(
        r#"SELECT p.account_id,p.unit,p.units FROM "fin:postings" p
 JOIN "fin:journal_entries" j ON j.id=p.journal_entry_id
 WHERE p.owner_user_id=?1 AND j.owner_user_id=?1 AND p.deleted_at IS NULL
 AND j.deleted_at IS NULL AND j.date<=?2"#,
    )?;
    for row in q.query_map(params![owner, as_of], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
        ))
    })? {
        let (id, unit, raw) = row?;
        if lifeos::money::Currency::new(&unit).is_err() {
            continue;
        }
        let value = Decimal::from_str_exact(&raw).map_err(|e| invalid(e.to_string()))?;
        let pair = sums.entry((id, unit)).or_default();
        *pair = checked(pair.checked_add(value))?;
    }
    let mut out = Vec::new();
    for ((id, currency), amount) in sums {
        let a = account_repository::get_required(conn, &id)?;
        if a.sync.owner_user_id != owner {
            return Err(invalid("账户所属数据空间不一致"));
        }
        if a.sync.deleted_at.is_some()
            || !matches!(a.side, AccountSide::Asset | AccountSide::Liability)
        {
            continue;
        }
        out.push(CashBalance {
            account_id: id,
            name: a.name,
            currency,
            amount,
            liability: a.side == AccountSide::Liability,
        });
    }
    // Empty accounts still appear in account-assignment pickers.
    for a in account_repository::list(conn, true)? {
        if a.sync.owner_user_id == owner
            && matches!(a.side, AccountSide::Asset | AccountSide::Liability)
            && !out.iter().any(|b| b.account_id == a.id)
        {
            out.push(CashBalance {
                account_id: a.id,
                name: a.name,
                currency: a.currency,
                amount: Decimal::ZERO,
                liability: a.side == AccountSide::Liability,
            });
        }
    }
    Ok(out)
}
pub fn snapshot(
    conn: &Connection,
    owner: &str,
    as_of: i64,
    base_currency: &str,
) -> Result<WealthSnapshot> {
    lifeos::money::Currency::new(base_currency).map_err(|e| invalid(e.to_string()))?;
    let as_of = valuation_as_of(as_of);
    let ops = operations(conn, owner, None)?;
    super::replay::verify(conn, owner, &ops)?;
    let mut pairs = BTreeSet::new();
    for op in &ops {
        if op.details.date <= as_of {
            pairs.insert((op.details.asset_id.clone(), op.details.account_id.clone()));
        }
    }
    let mut result = WealthSnapshot {
        as_of,
        base_currency: base_currency.to_owned(),
        holdings: Vec::new(),
        currencies: Vec::new(),
        missing_prices: Vec::new(),
        missing_fx: Vec::new(),
        net_worth: Some(Decimal::ZERO),
    };
    let mut by_currency: BTreeMap<String, (Decimal, Decimal)> = BTreeMap::new();
    for (asset_id, account_id) in pairs {
        let a = asset(conn, owner, &asset_id)?;
        let account = account_repository::get_required(conn, &account_id)?;
        if account.sync.owner_user_id != owner || account.sync.deleted_at.is_some() {
            return Err(invalid("持仓账户不可用或所属数据空间不一致"));
        }
        let p = super::replay::project(&ops, &asset_id, &account_id, as_of)?;
        let price = prices(conn, owner, &asset_id)?
            .into_iter()
            .filter(|q| {
                super::store::is_quote_date_allowed(q.observed_on, q.source.as_deref())
                    && q.quote_currency == a.details.currency
                    && q.observed_on <= as_of
                    && q.per_unit > Decimal::ZERO
            })
            .max_by_key(|q| (q.observed_on, q.sync.hlc.clone()));
        let market_value = if p.quantity == Decimal::ZERO {
            Some(Decimal::ZERO)
        } else {
            price
                .as_ref()
                .map(|q| checked(p.quantity.checked_mul(q.per_unit)))
                .transpose()?
        };
        let base_value = if let Some(v) = market_value {
            let pair = by_currency.entry(a.details.currency.clone()).or_default();
            pair.0 = checked(pair.0.checked_add(v))?;
            if v == Decimal::ZERO {
                Some(Decimal::ZERO)
            } else if let Some(fx) =
                crate::fx::rate_at(conn, &a.details.currency, base_currency, as_of)
            {
                Some(checked(v.checked_mul(fx))?)
            } else {
                result
                    .missing_fx
                    .push(format!("{}/{}", a.details.currency, base_currency));
                None
            }
        } else {
            result
                .missing_prices
                .push(format!("{} · {}", a.details.name, account.name));
            None
        };
        result.holdings.push(Holding {
            asset_id,
            account_id,
            name: a.details.name,
            currency: a.details.currency,
            quantity: p.quantity,
            cost_basis: p.cost,
            market_price: price.as_ref().map(|q| q.per_unit),
            price_as_of: price.as_ref().map(|q| q.observed_on),
            market_value,
            base_value,
            unrealized_pnl: market_value
                .map(|v| checked(v.checked_sub(p.cost)))
                .transpose()?,
            realized_pnl: p.realized,
            dividends: p.dividends,
        });
    }
    for cash in cash_balances_verified(conn, owner, as_of)? {
        let pair = by_currency.entry(cash.currency).or_default();
        if cash.liability {
            pair.1 = checked(pair.1.checked_sub(cash.amount))?;
        } else {
            pair.0 = checked(pair.0.checked_add(cash.amount))?;
        }
    }
    let mut net = Decimal::ZERO;
    for (currency, (assets, liabilities)) in by_currency {
        let value = checked(assets.checked_sub(liabilities))?;
        if value != Decimal::ZERO {
            if let Some(rate) = crate::fx::rate_at(conn, &currency, base_currency, as_of) {
                net = checked(net.checked_add(checked(value.checked_mul(rate))?))?;
            } else {
                result
                    .missing_fx
                    .push(format!("{currency}/{base_currency}"));
            }
        }
        result.currencies.push(CurrencyWealth {
            currency,
            assets,
            liabilities,
            net: value,
        });
    }
    result.missing_prices.sort();
    result.missing_prices.dedup();
    result.missing_fx.sort();
    result.missing_fx.dedup();
    result.net_worth =
        (result.missing_prices.is_empty() && result.missing_fx.is_empty()).then_some(net);
    Ok(result)
}
/// Charts use only actual recorded fact instants. There is no fabricated
/// daily series, interpolation, or pre-history baseline.
pub fn wealth_history(
    conn: &Connection,
    owner: &str,
    base_currency: &str,
) -> Result<Vec<WealthHistoryPoint>> {
    let mut dates: BTreeSet<i64> = BTreeSet::new();
    let mut q=conn.prepare(r#"SELECT date FROM "fin:journal_entries" WHERE owner_user_id=?1 AND deleted_at IS NULL UNION SELECT observed_on FROM "fin:prices" WHERE owner_user_id=?1 AND deleted_at IS NULL AND (observed_on<=?2 OR source IN ('manual','manual_fx'))"#)?;
    for date in q.query_map(params![owner, lifeos::ids::now_secs()], |r| {
        r.get::<_, i64>(0)
    })? {
        let date = date?;
        if super::store::is_record_date_allowed(date) {
            dates.insert(date);
        }
    }
    dates
        .into_iter()
        .map(|as_of| {
            let v = snapshot(conn, owner, as_of, base_currency)?;
            Ok(WealthHistoryPoint {
                as_of,
                net_worth: v.net_worth,
                missing_prices: v.missing_prices,
                missing_fx: v.missing_fx,
            })
        })
        .collect()
}
