//! Why net worth changed between the close of two days.
//!
//! Net worth at a close is the CNY value of own balances plus the unrealized
//! gain of priced holdings, each currency at the rate known on that day
//! ([`Book::overview_with_rates`]). The change from the close of `start` to
//! the close of `end` splits into what the journal recorded in between and
//! what moved without a record:
//!
//! - income and spending: income and expense postings outside investment
//!   entries (refunds reduce spending);
//! - investment: each holding's unrealized change plus its realized gains
//!   and dividends;
//! - openings: balances first recorded against `权益:期初` — bookkeeping, not
//!   a gain;
//! - adjustments: balance-check corrections (`权益:调整`) and any other equity
//!   entry except the currency-exchange bridge;
//! - exchange rates: the remainder. Recorded amounts convert at the rate
//!   known at the start (else at the end, for a currency first held during
//!   the period), so the remainder is the revaluation of foreign balances and
//!   holdings, the spread of currency exchanges against the reference rate,
//!   and conversion rounding. With CNY alone it is exactly zero.
//!
//! The parts always sum to the change exactly. A currency without a rate where
//! one is needed makes the attribution incomplete rather than partial.
use std::collections::{BTreeMap, BTreeSet};

use jiff::civil::Date;

use crate::{
    account::AccountKind,
    currency::{self, Currency, FxRate},
    holdings::{Book, Error, Position},
    journal::{Source, Transaction},
    money::Minor,
};

/// The equity account that bridges the two currencies of an exchange.
const EXCHANGE_BRIDGE: &str = "换汇";
/// The equity account of balances first recorded.
const OPENING: &str = "期初";

/// One part of the change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Part {
    Income,
    Spending,
    Investment,
    Openings,
    Adjustments,
    Exchange,
}

/// An opening or adjustment entry and its CNY contribution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Correction {
    pub transaction: String,
    pub day: Date,
    pub part: Part,
    pub amount: Minor,
}

/// The change in CNY minor units. Every part is a contribution to the
/// change: spending is negative when money was spent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attribution {
    pub start: Minor,
    pub end: Minor,
    pub income: Minor,
    pub spending: Minor,
    pub investment: Minor,
    pub openings: Minor,
    pub adjustments: Minor,
    pub exchange: Minor,
    /// Investment by security id, largest movement first; sums to `investment`.
    pub holdings: Vec<(String, Minor)>,
    /// Opening and adjustment entries in date order; they sum to `openings`
    /// and `adjustments`.
    pub corrections: Vec<Correction>,
}

impl Attribution {
    pub fn change(&self) -> Minor {
        self.end - self.start
    }

    /// The parts in display order with their contributions.
    pub fn parts(&self) -> [(Part, Minor); 6] {
        [
            (Part::Income, self.income),
            (Part::Spending, self.spending),
            (Part::Investment, self.investment),
            (Part::Openings, self.openings),
            (Part::Adjustments, self.adjustments),
            (Part::Exchange, self.exchange),
        ]
    }
}

/// An attribution, or the currencies whose missing rates prevent one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Complete(Attribution),
    Missing(Vec<Currency>),
}

/// Native amounts awaiting conversion, by currency.
type Native = BTreeMap<Currency, i128>;

fn add(native: &mut Native, currency: Currency, amount: i128) {
    *native.entry(currency).or_default() += amount;
}

/// A priced position's gain over cost; an unpriced one is valued at cost.
fn unrealized(position: &Position) -> i128 {
    position
        .value
        .map_or(0, |value| i128::from(value) - i128::from(position.cost))
}

/// Attributes the change in net worth from the close of `start` to the
/// close of `end` (`start` before `end`). `entries` is the whole journal,
/// including the entries generated from trades.
pub fn attribute(
    book: &Book,
    entries: &[Transaction],
    rates: &[FxRate],
    start: Date,
    end: Date,
) -> Result<Outcome, Error> {
    if start >= end {
        return Err(Error::Invalid);
    }
    let opening = book.overview_with_rates(entries, start, rates)?;
    let closing = book.overview_with_rates(entries, end, rates)?;
    let mut missing: BTreeSet<_> = opening.missing.into_iter().collect();
    missing.extend(closing.missing);

    let trades: BTreeMap<_, _> = book
        .trades
        .iter()
        .map(|t| (t.id.as_str(), t.security.as_str()))
        .collect();
    let (mut income, mut spending) = (Native::new(), Native::new());
    // Investment by security id; "" holds income of a trade no longer known.
    let mut investment = BTreeMap::<String, Native>::new();
    let mut corrections = BTreeMap::<(Date, String, Part), Native>::new();
    for t in entries {
        let day = t.at.date();
        if day <= start || day > end {
            continue;
        }
        for p in &t.postings {
            let (currency, contribution) = (p.account.currency(), -i128::from(p.amount));
            match p.account.kind() {
                AccountKind::Assets | AccountKind::Liabilities => {}
                AccountKind::Equity if p.account.name() == EXCHANGE_BRIDGE => {}
                AccountKind::Equity => {
                    let part = if p.account.name() == OPENING {
                        Part::Openings
                    } else {
                        Part::Adjustments
                    };
                    add(
                        corrections.entry((day, t.id.clone(), part)).or_default(),
                        currency,
                        contribution,
                    );
                }
                AccountKind::Income | AccountKind::Expenses => match &t.source {
                    Source::Investment { trade_id } => {
                        let security = trades.get(trade_id.as_str()).copied().unwrap_or("");
                        add(
                            investment.entry(security.to_owned()).or_default(),
                            currency,
                            contribution,
                        );
                    }
                    _ if p.account.kind() == AccountKind::Income => {
                        add(&mut income, currency, contribution)
                    }
                    _ => add(&mut spending, currency, contribution),
                },
            }
        }
    }
    for security in &book.securities {
        let change = unrealized(&book.position(security, end)?)
            - unrealized(&book.position(security, start)?);
        if change != 0 {
            add(
                investment.entry(security.id.clone()).or_default(),
                security.currency(),
                change,
            );
        }
    }

    // Recorded amounts convert at the start's rate, else the end's.
    let mut convert = |native: &Native| -> Result<i128, Error> {
        let mut total = 0_i128;
        for (&currency, &amount) in native.iter().filter(|(_, amount)| **amount != 0) {
            let Some(rate) = currency::rate_in(rates, currency, start)
                .or_else(|| currency::rate_in(rates, currency, end))
            else {
                missing.insert(currency);
                continue;
            };
            let amount = Minor::try_from(amount).map_err(|_| Error::Overflow)?;
            total += i128::from(
                currency::convert_to_cny(amount, rate.rate).map_err(|_| Error::Overflow)?,
            );
        }
        Ok(total)
    };
    let income = convert(&income)?;
    let spending = convert(&spending)?;
    let mut holdings = Vec::new();
    for (security, native) in &investment {
        let amount = convert(native)?;
        if amount != 0 {
            holdings.push((security.clone(), amount));
        }
    }
    let mut listed = Vec::new();
    for ((day, transaction, part), native) in &corrections {
        let amount = convert(native)?;
        if amount != 0 {
            listed.push((*day, transaction.clone(), *part, amount));
        }
    }
    if !missing.is_empty() {
        return Ok(Outcome::Missing(missing.into_iter().collect()));
    }

    let total = |part: Part| -> i128 {
        listed
            .iter()
            .filter(|c| c.2 == part)
            .map(|c| c.3)
            .sum::<i128>()
    };
    let investment: i128 = holdings.iter().map(|h| h.1).sum();
    let (openings, adjustments) = (total(Part::Openings), total(Part::Adjustments));
    let change = i128::from(closing.snapshot.net) - i128::from(opening.snapshot.net);
    let exchange = change - income - spending - investment - openings - adjustments;
    let minor = |v: i128| Minor::try_from(v).map_err(|_| Error::Overflow);
    holdings.sort_by(|a, b| b.1.abs().cmp(&a.1.abs()).then(a.0.cmp(&b.0)));
    Ok(Outcome::Complete(Attribution {
        start: opening.snapshot.net,
        end: closing.snapshot.net,
        income: minor(income)?,
        spending: minor(spending)?,
        investment: minor(investment)?,
        openings: minor(openings)?,
        adjustments: minor(adjustments)?,
        exchange: minor(exchange)?,
        holdings: holdings
            .into_iter()
            .map(|(id, amount)| Ok((id, minor(amount)?)))
            .collect::<Result<_, Error>>()?,
        corrections: listed
            .into_iter()
            .map(|(day, transaction, part, amount)| {
                Ok(Correction {
                    transaction,
                    day,
                    part,
                    amount: minor(amount)?,
                })
            })
            .collect::<Result<_, Error>>()?,
    }))
}
