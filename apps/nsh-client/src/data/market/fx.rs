//! Only publish a fetch result for the generation and currency that requested it.
use super::{client, clock, finance, generation, reload_prices};
use jiff::civil::Date;
use navi_finance::{
    currency::{Currency, FxRate},
    market,
};
use nsh_core::prelude::*;
use std::{collections::BTreeMap, time::Duration};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum RateStatus {
    Loading,
    Ready,
    Empty,
    Failed(i64),
}

type Period = (Date, Date);

#[derive(Clone, Default, PartialEq)]
struct Requests {
    current: BTreeMap<Currency, RateStatus>,
    history: BTreeMap<Currency, Vec<(Period, RateStatus)>>,
}

pub(super) fn reset() {
    global::<Requests>().set(Requests::default());
}

pub(crate) fn rate_status(currency: Currency, period: Option<Period>) -> Option<RateStatus> {
    global::<Requests>().with(|requests| match period {
        None => requests.current.get(&currency).copied(),
        Some(period) => history_status(requests.history.get(&currency)?, period),
    })
}

/// Segments remain sorted and disjoint. A newer request supersedes only its dates.
fn mark_period(records: &mut Vec<(Period, RateStatus)>, (from, to): Period, status: RateStatus) {
    let mut next = Vec::new();
    for &((start, end), previous) in records.iter() {
        if end < from || start > to {
            next.push(((start, end), previous));
            continue;
        }
        if start < from {
            next.push(((start, from.yesterday().unwrap()), previous));
        }
        if end > to {
            next.push(((to.tomorrow().unwrap(), end), previous));
        }
    }
    next.push(((from, to), status));
    next.sort_unstable_by_key(|r| r.0);
    records.clear();
    for (period, state) in next {
        if let Some(((.., end), previous)) = records.last_mut()
            && *previous == state
            && end.tomorrow().ok() == Some(period.0)
        {
            *end = period.1;
        } else {
            records.push((period, state));
        }
    }
}

fn history_status(records: &[(Period, RateStatus)], (from, to): Period) -> Option<RateStatus> {
    let mut cursor = from;
    let mut complete = false;
    let mut gap = false;
    let mut result = RateStatus::Empty;
    for &((start, end), status) in records
        .iter()
        .filter(|((start, end), _)| *start <= to && from <= *end)
    {
        gap |= start > cursor;
        complete = end >= to;
        cursor = end.tomorrow().unwrap_or(end);
        match (status, result) {
            (RateStatus::Loading, _) => return Some(RateStatus::Loading),
            (RateStatus::Failed(at), RateStatus::Failed(previous)) => {
                result = RateStatus::Failed(at.max(previous))
            }
            (RateStatus::Failed(_), _) | (RateStatus::Ready, RateStatus::Empty) => result = status,
            _ => {}
        }
    }
    (matches!(result, RateStatus::Failed(_)) || (complete && !gap)).then_some(result)
}

pub(in crate::data) fn set_rate_status(
    currency: Currency,
    period: Option<Period>,
    state: RateStatus,
) {
    global::<Requests>().update(|requests| match period {
        Some(period) => {
            mark_period(requests.history.entry(currency).or_default(), period, state);
        }
        None => {
            requests.current.insert(currency, state);
        }
    });
}

type FxResult = (Currency, Result<Option<FxRate>, String>);
pub(super) type FetchRates = fn(Vec<Currency>, Date) -> Result<Vec<FxResult>, String>;

fn provider_rate(raw: &str, currency: Currency, day: Date) -> Result<Option<FxRate>, String> {
    match market::parse_fx(raw, currency, day) {
        Ok(rate) => Ok(Some(rate)),
        Err(_) if matches!(serde_json::from_str(raw), Ok(serde_json::Value::Array(rows)) if rows.is_empty()) => {
            Ok(None)
        }
        Err(_) => Err("invalid FX response".into()),
    }
}

pub(super) fn fetch_fx(currencies: Vec<Currency>, today: Date) -> Result<Vec<FxResult>, String> {
    let client = client()?;
    client.runtime.block_on(async {
        let mut rows = Vec::new();
        for currency in currencies {
            let result = async {
                let response = client.http.get(format!("https://api.frankfurter.dev/v2/providers/ecb/rates?base={currency}&quotes=CNY"))
                    .timeout(Duration::from_secs(12)).send().await.map_err(|_| "FX request failed")?
                    .error_for_status().map_err(|_| "FX request rejected")?;
                let bytes = response.bytes().await.map_err(|_| "FX response failed")?;
                if bytes.len() > 16384 { return Err("FX response too large".into()); }
                provider_rate(std::str::from_utf8(&bytes).map_err(|_| "invalid FX response")?, currency, today)
            }.await;
            rows.push((currency, result));
        }
        Ok(rows)
    })
}

pub(super) async fn refresh(
    fetch: FetchRates,
    currencies: Vec<Currency>,
    day: Date,
    epoch: u64,
    mut changed: bool,
) {
    for &currency in &currencies {
        set_rate_status(currency, None, RateStatus::Loading);
    }
    let requested = currencies.clone();
    let results = blocking(move || fetch(requested, day)).await;
    if generation() != epoch {
        return;
    }
    let failed = RateStatus::Failed(clock::now_ms());
    let mut statuses: BTreeMap<_, _> = currencies.into_iter().map(|c| (c, failed)).collect();
    if let Ok(Ok(rows)) = results {
        for (currency, result) in rows {
            let Some(status) = statuses.get_mut(&currency) else {
                continue;
            };
            match result.and_then(|rate| rate.map(|r| finance::store_rates(&[r])).transpose()) {
                Ok(Some(n)) => {
                    changed |= n > 0;
                    *status = RateStatus::Ready;
                }
                Ok(None) => *status = RateStatus::Empty,
                Err(e) => log::warn!("FX {currency}: {e}"),
            }
        }
    }
    let published = !changed
        || reload_prices()
            .inspect_err(|e| log::warn!("market: cannot publish prices: {e}"))
            .is_ok();
    for (currency, status) in statuses {
        let status = if !published && status == RateStatus::Ready {
            failed
        } else {
            status
        };
        set_rate_status(currency, None, status);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::data::db;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use std::sync::{Mutex, mpsc};
    static RESPONSE: Mutex<Option<mpsc::Receiver<()>>> = Mutex::new(None);

    fn empty_and_offline(_: Vec<Currency>, _: Date) -> Result<Vec<FxResult>, String> {
        let response = RESPONSE.lock().unwrap().take().unwrap();
        response.recv_timeout(Duration::from_secs(10)).unwrap();
        Ok(vec![
            (Currency::USD, Ok(None)),
            (Currency::HKD, Err("offline".into())),
        ])
    }

    #[component]
    fn StatusProbe() -> impl IntoElement {
        db::open().unwrap();
        finance::load().unwrap();
        let today = clock::today().0;
        let previous = today.yesterday().unwrap();
        let saved =
            [(Currency::USD, 7_000_000), (Currency::HKD, 900_000)].map(|(currency, rate)| FxRate {
                currency,
                day: previous,
                rate,
                source: "manual".into(),
            });
        finance::store_rates(&saved).unwrap();
        reload_prices().unwrap();
        let completed = signal(0);
        view()
            .child(text("Fetch rates").on_press(move || {
                spawn(async move {
                    refresh(
                        empty_and_offline,
                        vec![Currency::HKD, Currency::USD],
                        today,
                        generation(),
                        false,
                    )
                    .await;
                    completed.update(|n| *n += 1);
                });
            }))
            .child(text(move || format!("Completed {}", completed.get())))
            .child(text("Restore").on_press(|| {
                super::super::load().unwrap();
            }))
            .child(text(move || {
                let earliest = previous.yesterday().unwrap();
                status_label(
                    rate_status(Currency::USD, None),
                    rate_status(Currency::HKD, None),
                    rate_status(Currency::USD, Some((earliest, previous))).is_some(),
                )
            }))
            .child(text(move || {
                format!("stored rates {}", finance::rates_snapshot().len())
            }))
    }

    fn status_label(usd: Option<RateStatus>, hkd: Option<RateStatus>, historic: bool) -> String {
        let state = |s| match s {
            None => "idle",
            Some(RateStatus::Loading) => "loading",
            Some(RateStatus::Empty) => "empty",
            Some(RateStatus::Ready) => "ready",
            Some(RateStatus::Failed(_)) => "failed",
        };
        format!(
            "USD {} / HKD {} / history {historic}",
            state(usd),
            state(hkd)
        )
    }

    #[test]
    fn empty_and_failed_pairs_keep_cached_observations_and_do_not_leak_into_history() {
        let (send, receive) = mpsc::channel();
        *RESPONSE.lock().unwrap() = Some(receive);
        let mut app = Headless::start(EngineConfig::new(Root::of::<StatusProbe>())).unwrap();
        app.wait_for("Fetch rates").unwrap();
        app.press("Fetch rates").unwrap();
        app.wait_for("USD loading / HKD loading / history false")
            .unwrap();
        send.send(()).unwrap();
        app.wait_for("USD empty / HKD failed / history false")
            .unwrap();
        app.wait_for("stored rates 2").unwrap();
        let (send, receive) = mpsc::channel();
        *RESPONSE.lock().unwrap() = Some(receive);
        app.press("Fetch rates").unwrap();
        app.wait_for("USD loading / HKD loading / history false")
            .unwrap();
        app.press("Restore").unwrap();
        send.send(()).unwrap();
        app.wait_for("Completed 2").unwrap();
        app.wait_for("USD idle / HKD idle / history false").unwrap();
        app.wait_for("stored rates 2").unwrap();
    }

    #[test]
    fn completed_and_pending_historical_chunks_only_change_their_own_dates() {
        let day = |n| jiff::civil::date(2026, 1, n);
        let mut history = Vec::new();
        mark_period(&mut history, (day(1), day(12)), RateStatus::Failed(5));
        mark_period(&mut history, (day(13), day(22)), RateStatus::Ready);
        assert!(matches!(
            history_status(&history, (day(1), day(22))),
            Some(RateStatus::Failed(5))
        ));
        mark_period(&mut history, (day(5), day(8)), RateStatus::Loading);
        assert!(matches!(
            history_status(&history, (day(2), day(7))),
            Some(RateStatus::Loading)
        ));
        assert!(matches!(
            history_status(&history, (day(9), day(10))),
            Some(RateStatus::Failed(5))
        ));
        assert!(history_status(&history, (day(18), day(23))).is_none());
        mark_period(&mut history, (day(1), day(12)), RateStatus::Ready);
        assert!(matches!(
            history_status(&history, (day(1), day(22))),
            Some(RateStatus::Ready)
        ));
        assert_eq!(history.len(), 1);
    }

    #[test]
    fn only_an_empty_provider_array_is_a_successful_empty_result() {
        let day = jiff::civil::date(2026, 11, 22);
        assert!(provider_rate("[ ]", Currency::HKD, day).unwrap().is_none());
        assert!(provider_rate("{}", Currency::HKD, day).is_err());
        assert!(provider_rate("[null]", Currency::HKD, day).is_err());
    }
}
