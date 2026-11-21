//! Foreground scheduling for quotes, historical observations and daily valuations.
use super::{Currency, clock, finance};
use crate::{
    data::{catalog, history, tasks, valuation},
    nav,
};
use jiff::civil::Date;
use navi_finance::catalog::SecurityBinding;
use nsh_core::{platform::Lifecycle, prelude::*};
use std::{collections::BTreeMap, time::Duration};

#[derive(Clone, Default, PartialEq)]
struct Generation(u64);

pub(super) fn invalidate() {
    global::<Generation>().update(|g| g.0 = g.0.wrapping_add(1));
}

pub(crate) fn generation() -> u64 {
    global::<Generation>().get().0
}

#[derive(Clone, PartialEq)]
struct Plan {
    epoch: u64,
    day: Date,
    quotes: Vec<SecurityBinding>,
    currencies: Vec<Currency>,
    history: bool,
    has_records: bool,
}

impl Plan {
    fn current() -> Self {
        let day = clock::today().0;
        let book = finance::holdings_snapshot();
        let accounts = finance::accounts_snapshot();
        let bindings = catalog::bindings();
        let show_rates = matches!(nav::open().last(), Some(nav::Route::PricesAndRates(None)));
        let needs = |currency| {
            accounts
                .iter()
                .any(|a| a.is_cash() && a.currency() == currency)
                || book.securities.iter().any(|s| s.currency() == currency)
        };
        let foreign = [Currency::HKD, Currency::USD];
        Self {
            epoch: generation(),
            day,
            history: show_rates || !bindings.is_empty() || foreign.into_iter().any(needs),
            quotes: bindings
                .into_iter()
                .filter(|b| {
                    book.securities
                        .iter()
                        .find(|s| s.id == b.security)
                        .is_some_and(|s| book.position(s, day).is_ok_and(|p| p.quantity > 0))
                })
                .collect(),
            currencies: foreign
                .into_iter()
                .filter(|&c| show_rates || needs(c))
                .collect(),
            has_records: !book.trades.is_empty() || !finance::transactions_snapshot().is_empty(),
        }
    }
}

const INTERVAL: Duration = Duration::from_secs(300);

#[derive(Clone, Default, PartialEq)]
struct Attempts {
    epoch: u64,
    times: BTreeMap<String, i64>,
}
impl Attempts {
    fn take_due(&mut self, plan: &mut Plan, now: i64) {
        if self.epoch != plan.epoch {
            self.times.clear();
            self.epoch = plan.epoch;
        }
        self.times
            .retain(|_, at| (0..INTERVAL.as_millis() as i64).contains(&(now - *at)));
        let mut due = |key| {
            if let std::collections::btree_map::Entry::Vacant(entry) = self.times.entry(key) {
                entry.insert(now);
                true
            } else {
                false
            }
        };
        plan.quotes.retain(|b| {
            due(format!(
                "{}:{}:{}:{}",
                b.market, b.symbol, b.currency, b.security
            ))
        });
        plan.currencies.retain(|c| due(c.code().to_owned()));
    }
}

pub fn start() {
    start_with(super::fetch_fx);
}

fn start_with(fetch_rates: super::FetchRates) {
    let plan = computed(Plan::current);
    let pending = signal(None::<Plan>);
    let running = signal(false);
    let attempts = signal(Attempts::default());
    let schedule = move || {
        if lifecycle() != Lifecycle::Active {
            return;
        }
        pending.set(Some(plan.get()));
        if running.get_untracked() {
            return;
        }
        running.set(true);
        tasks::spawn_app(async move {
            while let Some(mut work) = pending.get_untracked() {
                pending.set(None);
                if lifecycle() != Lifecycle::Active {
                    break;
                }
                let history_currencies = work.currencies.clone();
                attempts.update(|cache| cache.take_due(&mut work, clock::now_ms()));
                super::update(
                    fetch_rates,
                    work.quotes,
                    work.currencies,
                    work.day,
                    work.epoch,
                )
                .await;
                if generation() != work.epoch || lifecycle() != Lifecycle::Active {
                    continue;
                }
                if work.has_records
                    && let Err(e) = valuation::capture()
                {
                    log::warn!("daily valuation: {e}");
                }
                if work.history
                    && super::LIVE.load(super::Ordering::Relaxed)
                    && lifecycle() == Lifecycle::Active
                {
                    let from = work
                        .day
                        .checked_sub(jiff::Span::new().days(30))
                        .unwrap_or(work.day);
                    history::backfill(from, work.day, work.epoch, &history_currencies).await;
                }
            }
            running.set(false);
        });
    };
    effect(schedule);
    set_interval(INTERVAL, schedule);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[component]
    fn ForeignAccountProbe() -> impl IntoElement {
        use crate::data::{db, market};
        use navi_finance::{
            account::{Account, AccountKind},
            currency::FxRate,
        };
        db::open().unwrap();
        finance::load().unwrap();
        catalog::load().unwrap();
        market::load().unwrap();
        market::disable_live();
        start_with(|currencies, day| {
            Ok(currencies
                .into_iter()
                .map(|currency| {
                    (
                        currency,
                        Ok(FxRate {
                            currency,
                            day,
                            rate: 7_250_000,
                            source: "frankfurter:ecb".into(),
                        }),
                    )
                })
                .collect())
        });
        view()
            .child(text("Add dollar account").on_press(|| {
                finance::create_account(
                    Account::new_in(AccountKind::Assets, "Cash", Currency::USD).unwrap(),
                )
                .unwrap();
            }))
            .child(text("View rates").on_press(|| nav::push(nav::Route::PricesAndRates(None))))
            .child(text(|| {
                let published = finance::rates_snapshot();
                db::with(|c| {
                    let stored = navi_finance::currency::rates(c).unwrap();
                    assert_eq!(*published, stored);
                    assert!(
                        stored
                            .iter()
                            .all(|r| r.rate == 7_250_000 && r.source == "frankfurter:ecb")
                    );
                    let changes = navi_finance::history::audit_rows(c, None, 10).unwrap();
                    format!("{} rates · {} changes", published.len(), changes.len())
                })
                .unwrap()
            }))
    }

    #[test]
    fn new_foreign_account_and_rates_page_fetch_and_publish_without_refresh() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<ForeignAccountProbe>())).unwrap();
        app.wait_for("0 rates · 0 changes").unwrap();
        app.press("Add dollar account").unwrap();
        app.wait_for("1 rates · 1 changes").unwrap();
        app.press("View rates").unwrap();
        app.wait_for("2 rates · 2 changes").unwrap();
    }

    #[test]
    fn new_currencies_and_relinked_securities_do_not_wait_for_the_next_poll() {
        let mut cache = Attempts::default();
        let mut plan = Plan {
            epoch: 0,
            day: jiff::civil::date(2026, 11, 21),
            quotes: vec![SecurityBinding {
                security: "fund".into(),
                market: "cn_a".into(),
                symbol: "510300".into(),
                currency: "CNY".into(),
            }],
            currencies: vec![Currency::USD],
            history: true,
            has_records: true,
        };
        cache.take_due(&mut plan.clone(), 0);
        plan.quotes[0].symbol = "510500".into();
        plan.currencies.push(Currency::HKD);
        let mut next = plan.clone();
        cache.take_due(&mut next, 100);
        assert_eq!(next.quotes, plan.quotes);
        assert_eq!(next.currencies, [Currency::HKD]);
        next = plan.clone();
        cache.take_due(&mut next, 299999);
        assert!(next.quotes.is_empty() && next.currencies.is_empty());
        next = plan.clone();
        cache.take_due(&mut next, 300100);
        assert_eq!(next.quotes, plan.quotes);
        assert_eq!(next.currencies, plan.currencies);
        next.epoch += 1;
        cache.take_due(&mut next, 300101);
        assert_eq!(next.quotes, plan.quotes);
    }
}
