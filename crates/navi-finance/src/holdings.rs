//! A native-currency portfolio: exact quantities/prices, moving-average cost and
//! confirmed trades. Cash and security cost share the double-entry journal.
pub mod store;

use crate::{
    account::{Account, AccountKind, defaults},
    assets,
    currency::Currency,
    journal::{Posting, Source, Transaction},
    money::{self, Minor},
};
use jiff::civil::{Date, DateTime};
use serde::{Deserialize, Serialize};

pub const SCALE: i64 = 1_000_000;
pub const ACCOUNT_PREFIX: &str = "持仓·";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Security {
    pub id: String,
    pub name: String,
    pub account: Account,
}
impl Security {
    pub fn new(id: &str, name: &str) -> Result<Self, Error> {
        Self::new_in(id, name, Currency::CNY)
    }
    pub fn currency(&self) -> Currency {
        self.account.currency()
    }
    pub fn new_in(id: &str, name: &str, currency: Currency) -> Result<Self, Error> {
        let name = name.trim();
        if id.is_empty()
            || id.len() > 30
            || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
            || name.is_empty()
            || name.chars().count() > 40
            || name.chars().any(char::is_control)
        {
            return Err(Error::Invalid);
        }
        Ok(Self {
            id: id.into(),
            name: name.into(),
            account: Account::new_in(
                AccountKind::Assets,
                &format!("{ACCOUNT_PREFIX}{id}"),
                currency,
            )
            .map_err(|_| Error::Invalid)?,
        })
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Kind {
    Opening,
    Buy,
    Sell,
    Dividend,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Trade {
    pub id: String,
    pub security: String,
    pub at: DateTime,
    pub kind: Kind,
    /// Millionths of a share and millionths of the security currency per share.
    pub quantity: i64,
    pub price: i64,
    /// Dividend cash in native minor units (zero for other kinds).
    pub amount: Minor,
    pub fee: Minor,
    pub cash: Option<Account>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Quote {
    pub security: String,
    pub day: Date,
    pub price: i64,
}
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Book {
    pub securities: Vec<Security>,
    pub trades: Vec<Trade>,
    pub quotes: Vec<Quote>,
}
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Position {
    pub quantity: i64,
    pub cost: Minor,
    pub realized: Minor,
    pub dividends: Minor,
    pub value: Option<Minor>,
    pub quote: Option<Quote>,
}
impl Position {
    pub fn unrealized(&self) -> Option<Minor> {
        self.value.and_then(|v| v.checked_sub(self.cost))
    }
    pub fn average(&self) -> Option<i64> {
        if self.quantity == 0 {
            None
        } else {
            rounded(
                i128::from(self.cost) * i128::from(SCALE) * i128::from(SCALE),
                i128::from(self.quantity) * 100,
            )
            .ok()
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid security, trade, price or quantity")]
    Invalid,
    #[error("the sale exceeds the position at that time")]
    Oversell,
    #[error("cash account is required")]
    Cash,
    #[error("the security or trade no longer exists")]
    Missing,
    #[error("this security already exists")]
    Duplicate,
    #[error("the amount is outside the supported range")]
    Overflow,
    #[error(transparent)]
    Sql(#[from] navi_storage::sqlite::Error),
    #[error(transparent)]
    Ledger(#[from] crate::repository::Error),
}

/// Positive fixed-point input, up to six places. Never parse through f64.
pub fn parse_units(input: &str) -> Option<i64> {
    let text = input.trim();
    let (whole, decimal) = text.split_once('.').unwrap_or((text, ""));
    if (whole.is_empty() && decimal.is_empty())
        || decimal.len() > 6
        || !whole
            .chars()
            .chain(decimal.chars())
            .all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let whole = if whole.is_empty() {
        0
    } else {
        whole.parse::<i64>().ok()?
    };
    let fraction = if decimal.is_empty() {
        0
    } else {
        decimal.parse::<i64>().ok()? * 10_i64.pow(6 - decimal.len() as u32)
    };
    whole.checked_mul(SCALE)?.checked_add(fraction)
}
pub fn format_units(value: i64) -> String {
    let fraction = format!("{:06}", value.unsigned_abs() % SCALE as u64);
    let fraction = fraction.trim_end_matches('0');
    format!(
        "{}{}{}",
        if value < 0 { "-" } else { "" },
        value.unsigned_abs() / SCALE as u64,
        if fraction.is_empty() {
            String::new()
        } else {
            format!(".{fraction}")
        }
    )
}
fn rounded(value: i128, divisor: i128) -> Result<i64, Error> {
    i64::try_from((value + divisor / 2) / divisor).map_err(|_| Error::Overflow)
}
pub fn gross(quantity: i64, price: i64) -> Result<Minor, Error> {
    if quantity < 0 || price < 0 {
        return Err(Error::Invalid);
    }
    rounded(
        i128::from(quantity) * i128::from(price),
        i128::from(SCALE) * i128::from(SCALE) / 100,
    )
}

/// Replays in civil-time/id order. Backdated edits must leave every historical
/// sale covered. Fees enter buy cost or reduce sale/dividend proceeds.
pub fn replay(
    security: &Security,
    trades: &[Trade],
    day: Date,
) -> Result<(Position, Vec<Transaction>), Error> {
    let mut ordered: Vec<_> = trades
        .iter()
        .filter(|t| t.security == security.id && t.at.date() <= day)
        .collect();
    ordered.sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
    let mut p = Position::default();
    let mut entries = Vec::new();
    for t in ordered {
        if t.id.is_empty() || t.fee < 0 || t.amount < 0 {
            return Err(Error::Invalid);
        }
        let mut postings = Vec::new();
        let mut post = |a: Account, amount: i64| {
            if amount != 0 {
                postings.push(Posting { account: a, amount });
            }
        };
        match t.kind {
            Kind::Opening | Kind::Buy => {
                if t.quantity <= 0 || t.price <= 0 || t.amount != 0 {
                    return Err(Error::Invalid);
                }
                if t.kind == Kind::Opening
                    && (p.quantity != 0 || !entries.is_empty() || t.cash.is_some() || t.fee != 0)
                {
                    return Err(Error::Invalid);
                }
                let total = gross(t.quantity, t.price)?
                    .checked_add(t.fee)
                    .filter(|v| *v > 0)
                    .ok_or(Error::Overflow)?;
                let from = if t.kind == Kind::Opening {
                    defaults::opening().in_currency(security.currency())
                } else {
                    cash(t, security.currency())?
                };
                post(security.account.clone(), total);
                post(from, -total);
                p.quantity = p.quantity.checked_add(t.quantity).ok_or(Error::Overflow)?;
                p.cost = p.cost.checked_add(total).ok_or(Error::Overflow)?;
            }
            Kind::Sell => {
                if t.quantity <= 0 || t.price <= 0 || t.amount != 0 {
                    return Err(Error::Invalid);
                }
                if t.quantity > p.quantity {
                    return Err(Error::Oversell);
                }
                let net = gross(t.quantity, t.price)?
                    .checked_sub(t.fee)
                    .filter(|v| *v >= 0)
                    .ok_or(Error::Invalid)?;
                let released = if t.quantity == p.quantity {
                    p.cost
                } else {
                    rounded(
                        i128::from(p.cost) * i128::from(t.quantity),
                        i128::from(p.quantity),
                    )?
                };
                let gain = net.checked_sub(released).ok_or(Error::Overflow)?;
                post(cash(t, security.currency())?, net);
                post(security.account.clone(), -released);
                post(
                    defaults::other_income().in_currency(security.currency()),
                    -gain,
                );
                p.quantity -= t.quantity;
                p.cost -= released;
                p.realized = p.realized.checked_add(gain).ok_or(Error::Overflow)?;
            }
            Kind::Dividend => {
                if t.quantity != 0 || t.price != 0 || t.amount <= t.fee || p.quantity == 0 {
                    return Err(Error::Invalid);
                }
                let net = t.amount - t.fee;
                post(cash(t, security.currency())?, net);
                post(
                    defaults::other_income().in_currency(security.currency()),
                    -net,
                );
                p.dividends = p.dividends.checked_add(net).ok_or(Error::Overflow)?;
            }
        }
        let entry = Transaction {
            id: format!("trade:{}", t.id),
            at: t.at,
            payee: security.name.clone(),
            note: String::new(),
            source: Source::Investment {
                trade_id: t.id.clone(),
            },
            postings,
        };
        entry.validate().map_err(crate::repository::Error::from)?;
        entries.push(entry);
    }
    Ok((p, entries))
}
fn cash(t: &Trade, currency: Currency) -> Result<Account, Error> {
    t.cash
        .as_ref()
        .filter(|a| a.is_cash() && a.kind() == AccountKind::Assets && a.currency() == currency)
        .cloned()
        .ok_or(Error::Cash)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValuedOverview {
    pub snapshot: assets::Snapshot,
    pub missing: Vec<Currency>,
}

impl Book {
    pub fn validate_values(&self) -> Result<(), Error> {
        for security in &self.securities {
            let dates: std::collections::BTreeSet<_> = self
                .trades
                .iter()
                .filter(|t| t.security == security.id)
                .map(|t| t.at.date())
                .chain(
                    self.quotes
                        .iter()
                        .filter(|q| q.security == security.id)
                        .map(|q| q.day),
                )
                .collect();
            for day in dates {
                self.position(security, day)?;
            }
        }
        Ok(())
    }
    pub fn position(&self, security: &Security, day: Date) -> Result<Position, Error> {
        let (mut p, _) = replay(security, &self.trades, day)?;
        p.quote = self
            .quotes
            .iter()
            .filter(|q| q.security == security.id && q.day <= day)
            .max_by_key(|q| q.day)
            .cloned();
        p.value = if p.quantity == 0 {
            Some(0)
        } else {
            p.quote
                .as_ref()
                .map(|q| gross(p.quantity, q.price))
                .transpose()?
        };
        Ok(p)
    }
    /// Daily valuations start at the first journal entry, using only information
    /// available on each day. A failure on one day preserves the other dates.
    pub fn valuation_range(
        &self,
        entries: &[Transaction],
        rates: &[crate::currency::FxRate],
        first: Date,
        last: Date,
    ) -> Vec<(Date, Result<ValuedOverview, Error>)> {
        let start = entries
            .iter()
            .map(|entry| entry.at.date())
            .min()
            .map(|day| day.max(first));
        std::iter::successors(start, |day| day.tomorrow().ok())
            .take_while(|day| *day <= last)
            .map(|day| (day, self.overview_with_rates(entries, day, rates)))
            .collect()
    }

    /// Convert native account balances and security marks using only rates known
    /// by the valuation day. Missing rates exclude that currency explicitly.
    pub fn overview_with_rates(
        &self,
        entries: &[Transaction],
        day: Date,
        rates: &[crate::currency::FxRate],
    ) -> Result<ValuedOverview, Error> {
        let mut balances = crate::journal::balances(entries.iter().filter(|t| t.at.date() <= day));
        for security in &self.securities {
            let p = self.position(security, day)?;
            if let Some(value) = p.value {
                let balance = balances.entry(security.account.clone()).or_default();
                *balance = balance
                    .checked_add(value.checked_sub(p.cost).ok_or(Error::Overflow)?)
                    .ok_or(Error::Overflow)?;
            }
        }
        let mut totals = std::collections::BTreeMap::<Currency, (i128, i128)>::new();
        for (account, value) in balances {
            let total = totals.entry(account.currency()).or_default();
            match account.kind() {
                AccountKind::Assets => total.0 += i128::from(value),
                AccountKind::Liabilities => total.1 -= i128::from(value),
                _ => {}
            }
        }
        let (mut assets, mut debt) = (0_i128, 0_i128);
        let mut missing = Vec::new();
        for (currency, (a, d)) in totals {
            if a == 0 && d == 0 {
                continue;
            }
            let Some(rate) = crate::currency::rate_in(rates, currency, day) else {
                missing.push(currency);
                continue;
            };
            let convert = |v| {
                crate::currency::convert_to_cny(
                    i64::try_from(v).map_err(|_| Error::Overflow)?,
                    rate.rate,
                )
                .map_err(|_| Error::Overflow)
            };
            assets += i128::from(convert(a)?);
            debt += i128::from(convert(d)?);
        }
        Ok(ValuedOverview {
            snapshot: assets::Snapshot {
                assets: i64::try_from(assets).map_err(|_| Error::Overflow)?,
                debt: i64::try_from(debt).map_err(|_| Error::Overflow)?,
                net: i64::try_from(assets - debt).map_err(|_| Error::Overflow)?,
            },
            missing,
        })
    }
    /// Security cost is already an asset posting. Replace it with the known
    /// market value, not cost+market value. Unpriced positions remain at cost.
    /// Legacy CNY-only view; use overview_with_rates for a multi-currency book.
    pub fn overview(&self, entries: &[Transaction], day: Date) -> Result<assets::Snapshot, Error> {
        let mut snap = assets::snapshot(entries, day);
        let mut delta = 0_i128;
        for security in self
            .securities
            .iter()
            .filter(|s| s.currency() == Currency::CNY)
        {
            let p = self.position(security, day)?;
            if let Some(value) = p.value {
                delta += i128::from(value) - i128::from(p.cost);
            }
        }
        snap.assets = money::saturate(i128::from(snap.assets) + delta);
        snap.net = money::saturate(i128::from(snap.net) + delta);
        Ok(snap)
    }
}
