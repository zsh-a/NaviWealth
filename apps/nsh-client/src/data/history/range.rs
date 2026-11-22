//! Resolve a chart's dates into the instruments its valuation actually uses.
use super::*;
use navi_finance::{
    holdings::{Book, Kind},
    journal::{self, Transaction},
};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum HistoryScope {
    Portfolio,
    Security(String),
    Rate(Currency),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum Instrument {
    Security(catalog::SecurityBinding),
    Rate(Currency),
}

impl Instrument {
    pub(super) fn key(&self) -> String {
        match self {
            Self::Security(b) => format!("{}:{}:{}", b.market, b.symbol, b.currency),
            Self::Rate(c) => format!("fx:{c}"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct Period {
    pub from: Date,
    pub to: Date,
}

impl Period {
    pub fn previous_close(mut self) -> Self {
        self.from = self
            .from
            .checked_sub(jiff::Span::new().days(10))
            .unwrap_or(Date::MIN);
        self
    }

    /// Never ask the daily providers for more than 365 inclusive dates in one request.
    pub fn newest_chunk(self) -> (Self, Option<Self>) {
        let from = self.from.max(
            self.to
                .checked_sub(jiff::Span::new().days(364))
                .unwrap_or(Date::MIN),
        );
        (
            Self { from, to: self.to },
            (self.from < from).then(|| Self {
                from: self.from,
                to: from.yesterday().expect("remainder has an earlier date"),
            }),
        )
    }

    pub fn uncovered(self, mut covered: Vec<Self>) -> Vec<Self> {
        covered.sort_unstable();
        let mut cursor = self.from;
        let mut gaps = Vec::new();
        for part in covered {
            if part.to < cursor {
                continue;
            }
            if part.from > self.to {
                break;
            }
            if part.from > cursor {
                gaps.push(Self {
                    from: cursor,
                    to: part.from.yesterday().expect("earlier date exists"),
                });
            }
            if part.to >= self.to {
                return gaps;
            }
            cursor = part.to.tomorrow().expect("later date exists");
        }
        gaps.push(Self {
            from: cursor,
            to: self.to,
        });
        gaps
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Job {
    pub instrument: Instrument,
    pub period: Period,
    pub epoch: u64,
}

pub(super) fn resolve(scope: HistoryScope, period: Period, epoch: u64) -> Vec<Job> {
    let job = |instrument, period| Job {
        instrument,
        period,
        epoch,
    };
    match scope {
        HistoryScope::Rate(Currency::CNY) => Vec::new(),
        HistoryScope::Rate(c) => vec![job(Instrument::Rate(c), period)],
        HistoryScope::Security(id) => crate::data::catalog::bindings()
            .into_iter()
            .filter(|b| b.security == id)
            .map(|b| job(Instrument::Security(b), period))
            .collect(),
        HistoryScope::Portfolio => portfolio(
            &finance::holdings_snapshot(),
            &finance::transactions_snapshot(),
            &crate::data::catalog::bindings(),
            period,
            epoch,
        ),
    }
}

/// The automatic recent window also keeps archived holdings' price histories up to date.
pub(super) fn default_jobs(period: Period, rates: &[Currency], epoch: u64) -> Vec<Job> {
    let book = finance::holdings_snapshot();
    let mut jobs = Vec::new();
    for binding in crate::data::catalog::bindings() {
        if let Some(first) = book
            .trades
            .iter()
            .filter(|t| t.security == binding.security)
            .map(|t| t.at.date())
            .min()
            .filter(|d| *d <= period.to)
        {
            jobs.push(Job {
                epoch,
                instrument: Instrument::Security(binding),
                period: Period {
                    from: period.from.max(first),
                    to: period.to,
                }
                .previous_close(),
            });
        }
    }
    jobs.extend(rates.iter().filter(|&&c| c != Currency::CNY).map(|&c| Job {
        epoch,
        instrument: Instrument::Rate(c),
        period: period.previous_close(),
    }));
    jobs
}

fn portfolio(
    book: &Book,
    entries: &[Transaction],
    bindings: &[catalog::SecurityBinding],
    period: Period,
    epoch: u64,
) -> Vec<Job> {
    let mut jobs = Vec::new();
    let mut currencies = BTreeMap::new();
    let mut need_rate = |currency: Currency, from: Date| {
        if currency != Currency::CNY {
            let start = currencies.entry(currency).or_insert(from);
            *start = from.min(*start);
        }
    };
    for (account, balance) in
        journal::balances(entries.iter().filter(|t| t.at.date() <= period.from))
    {
        if account.is_cash() && balance != 0 {
            need_rate(account.currency(), period.from);
        }
    }
    for transaction in entries
        .iter()
        .filter(|t| t.at.date() > period.from && t.at.date() <= period.to)
    {
        for posting in &transaction.postings {
            if posting.account.is_cash() && posting.amount != 0 {
                need_rate(posting.account.currency(), transaction.at.date());
            }
        }
    }
    for security in &book.securities {
        let held_at_start = book
            .position(security, period.from)
            .is_ok_and(|p| p.quantity > 0);
        let first = if held_at_start {
            Some(period.from)
        } else {
            book.trades
                .iter()
                .filter(|t| {
                    t.security == security.id
                        && t.at.date() >= period.from
                        && t.at.date() <= period.to
                        && matches!(t.kind, Kind::Opening | Kind::Buy)
                })
                .map(|t| t.at.date())
                .min()
        };
        if let Some(from) = first {
            need_rate(security.currency(), from);
            if let Some(binding) = bindings.iter().find(|b| b.security == security.id) {
                jobs.push(Job {
                    epoch,
                    instrument: Instrument::Security(binding.clone()),
                    period: Period {
                        from,
                        to: period.to,
                    }
                    .previous_close(),
                });
            }
        }
    }
    jobs.extend(currencies.into_iter().map(|(currency, from)| {
        Job {
            epoch,
            instrument: Instrument::Rate(currency),
            period: Period {
                from,
                to: period.to,
            }
            .previous_close(),
        }
    }));
    jobs
}

#[cfg(test)]
mod tests {
    use super::*;
    use navi_finance::{
        account::Account,
        holdings::{Security, Trade},
    };
    #[test]
    fn portfolio_requests_only_relevant_bindings_and_foreign_exposure_with_one_warmup() {
        let day = |year| jiff::civil::date(year, 1, 1);
        let traded = Security::new_in("US", "Dollar holding", Currency::USD).unwrap();
        let closed = Security::new_in("HK", "Closed holding", Currency::HKD).unwrap();
        let opening = |id: &str, year| Trade {
            id: format!("{id}-{year}"),
            security: id.into(),
            at: day(year).at(12, 0, 0, 0),
            kind: Kind::Opening,
            quantity: 1_000_000,
            price: 2_000_000,
            fee: 0,
            amount: 0,
            cash: None,
        };
        let bindings = [
            catalog::SecurityBinding {
                security: "US".into(),
                market: "us_stock".into(),
                symbol: "AAPL".into(),
                currency: "USD".into(),
            },
            catalog::SecurityBinding {
                security: "HK".into(),
                market: "hk_stock".into(),
                symbol: "00700".into(),
                currency: "HKD".into(),
            },
        ];
        let book = Book {
            securities: vec![traded, closed],
            trades: vec![
                opening("US", 2018),
                opening("HK", 2010),
                Trade {
                    id: "HK-close".into(),
                    kind: Kind::Sell,
                    cash: Some(Account::parse("资产/HKD:Cash").unwrap()),
                    ..opening("HK", 2011)
                },
            ],
            quotes: vec![],
        };
        let period = Period {
            from: day(2015),
            to: day(2022),
        };
        let jobs = portfolio(&book, &[], &bindings, period, 7);
        assert_eq!(jobs.len(), 2);
        assert_eq!(
            jobs[0].instrument,
            Instrument::Security(bindings[0].clone())
        );
        assert_eq!(jobs[1].instrument, Instrument::Rate(Currency::USD));
        for j in jobs {
            assert_eq!(j.period.from, jiff::civil::date(2017, 12, 22));
            assert_eq!(j.period.to, day(2022));
        }
    }
}
