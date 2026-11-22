//! Selected ranges and the automatic recent window share a foreground worker.
use super::{
    range::{self, HistoryScope, Instrument, Job, Period},
    *,
};
use crate::data::{clock, tasks};
use nsh_core::platform::Lifecycle;
use std::collections::VecDeque;

#[derive(Clone, Default, PartialEq)]
struct Queue {
    running: bool,
    needs_publish: bool,
    active: Option<Job>,
    pending: VecDeque<Job>,
}

impl Queue {
    fn retire_binding(&mut self, security: &str) {
        let belongs =
            |j: &Job| matches!(&j.instrument, Instrument::Security(b) if b.security == security);
        self.pending.retain(|j| !belongs(j));
        if self.active.as_ref().is_some_and(belongs) {
            self.active = None;
        }
    }

    fn enqueue(&mut self, jobs: Vec<Job>, recent: &[Attempt], now: i64, interactive: bool) {
        for job in jobs {
            let key = job.instrument.key();
            if interactive {
                // Promote an already queued overlap ahead of unrelated default/older work.
                let mut rest = VecDeque::new();
                for queued in self.pending.drain(..) {
                    if queued.epoch == job.epoch && queued.instrument == job.instrument {
                        rest.extend(queued.period.uncovered(vec![job.period]).into_iter().map(
                            |period| Job {
                                period,
                                ..queued.clone()
                            },
                        ));
                    } else {
                        rest.push_back(queued);
                    }
                }
                self.pending = rest;
            }
            let mut covered: Vec<_> = recent
                .iter()
                .filter(|a| a.key == key && !a.failed && a.fresh(now))
                .map(|a| Period {
                    from: a.from,
                    to: a.to,
                })
                .collect();
            covered.extend(
                self.active
                    .iter()
                    .chain(&self.pending)
                    .filter(|other| other.instrument == job.instrument && other.epoch == job.epoch)
                    .map(|other| other.period),
            );
            for period in job.period.uncovered(covered) {
                let new = Job {
                    period,
                    ..job.clone()
                };
                if interactive {
                    self.pending.push_front(new);
                } else {
                    self.pending.push_back(new);
                }
            }
        }
    }

    fn next(&mut self, epoch: u64, recent: &[Attempt], now: i64) -> Option<Job> {
        for _ in 0..self.pending.len() {
            let job = self.pending.pop_front()?;
            if job.epoch != epoch {
                continue;
            }
            // Two distinct holdings can share the same market listing and therefore the same bars.
            let key = job.instrument.key();
            if recent
                .iter()
                .any(|a| a.key == key && a.failed && a.fresh(now))
            {
                self.pending.push_back(job);
                continue;
            }
            let covered = recent
                .iter()
                .filter(|a| a.key == key && !a.failed && a.fresh(now))
                .map(|a| Period {
                    from: a.from,
                    to: a.to,
                })
                .collect();
            let mut gaps = job.period.uncovered(covered);
            let Some(newest) = gaps.pop() else {
                continue;
            };
            let (chunk, remainder) = newest.newest_chunk();
            self.pending
                .extend(gaps.into_iter().chain(remainder).map(|period| Job {
                    period,
                    ..job.clone()
                }));
            let active = Job {
                period: chunk,
                ..job
            };
            self.active = Some(active.clone());
            return Some(active);
        }
        None
    }
}

pub(in crate::data) fn reset() {
    global::<Queue>().update(|q| {
        q.pending.clear();
        q.active = None;
        q.needs_publish = false;
    });
}

pub(in crate::data) fn binding_changed(security: &str) {
    global::<Queue>().update(|q| q.retire_binding(security));
}

/// User-selected chart dates. All data already on disk stays immediately available.
pub(crate) fn request_range(scope: HistoryScope, from: Date, to: Date) {
    submit(from, to, true, |period, epoch| {
        range::resolve(scope, period, epoch)
    });
}

/// A valuation gap can use the most recent published rate before its first date.
pub(crate) fn request_gap(currency: Currency, from: Date, to: Date) {
    submit(from, to, true, |period, epoch| {
        range::resolve(HistoryScope::Rate(currency), period.previous_close(), epoch)
    });
}

pub(in crate::data) fn request_default(from: Date, to: Date, rates: &[Currency]) {
    submit(from, to, false, |period, epoch| {
        range::default_jobs(period, rates, epoch)
    });
}

fn submit(from: Date, to: Date, interactive: bool, plan: impl FnOnce(Period, u64) -> Vec<Job>) {
    untracked(|| {
        if !market::live_enabled() {
            return;
        }
        let today = clock::today().0;
        let Ok(yesterday) = today.yesterday() else {
            return;
        };
        let to = to.min(today);
        if from > to {
            return;
        }
        let mut jobs = plan(Period { from, to }, market::generation());
        let now = Timestamp::now();
        jobs.retain_mut(|job| {
            job.period.to = job.period.to.min(yesterday);
            if let Instrument::Security(b) = &job.instrument {
                let Some(closed) = last_finished_day(b, now) else {
                    return false;
                };
                job.period.to = job.period.to.min(closed);
            }
            job.period.from <= job.period.to
        });
        let recent = attempts();
        global::<Queue>().update(|q| q.enqueue(jobs, &recent, now.as_second(), interactive));
        resume();
    });
}

pub(in crate::data) fn resume() {
    let queue = global::<Queue>();
    if !market::live_enabled()
        || lifecycle() != Lifecycle::Active
        || queue.with_untracked(|q| q.running || q.pending.is_empty())
    {
        return;
    }
    queue.update(|q| q.running = true);
    tasks::spawn_app(async move {
        while lifecycle() == Lifecycle::Active && market::live_enabled() {
            let epoch = market::generation();
            let recent = attempts();
            let mut next = None;
            queue.update(|q| next = q.next(epoch, &recent, Timestamp::now().as_second()));
            let Some(job) = next else {
                break;
            };
            run_job(&job, download).await;
            queue.update(|q| q.active = None);
            if queue.with_untracked(|q| !q.pending.is_empty()) {
                timer(Duration::from_millis(300)).await;
            }
        }
        queue.update(|q| q.running = false);
    });
}

enum Observations {
    Bars(Vec<store::DailyBar>),
    Rates(Vec<currency::FxRate>),
}

fn download(job: &Job, today: Date) -> Result<Observations, String> {
    let Period { from, to } = job.period;
    match &job.instrument {
        Instrument::Security(b) => fetch_bar(b, from, to).map(Observations::Bars),
        Instrument::Rate(c) => fetch_fx(*c, from, to, today).map(Observations::Rates),
    }
}

async fn run_job(job: &Job, fetch: fn(&Job, Date) -> Result<Observations, String>) {
    let Period { from, to } = job.period;
    let query = job.clone();
    let today = clock::today().0;
    if let Instrument::Rate(c) = job.instrument {
        market::set_rate_status(c, Some((from, to)), market::RateStatus::Loading);
    }
    let result = blocking(move || fetch(&query, today)).await;
    if market::generation() != job.epoch
        || !global::<Queue>().with_untracked(|q| q.active.as_ref() == Some(job))
    {
        return;
    }
    let saved = match (result, &job.instrument) {
        (Ok(Ok(Observations::Bars(rows))), Instrument::Security(binding)) => {
            db::with(|c| store::save_bars(c, binding, &rows, Timestamp::now()))
                .and_then(Result::ok)
                .map(|n| (rows.len(), n))
        }
        (Ok(Ok(Observations::Rates(rows))), Instrument::Rate(_)) => {
            finance::store_rates(&rows).ok().map(|n| (rows.len(), n))
        }
        _ => None,
    };
    let queue = global::<Queue>();
    if saved.is_some_and(|(_, n)| n > 0) {
        queue.update(|q| q.needs_publish = true);
    }
    if queue.with_untracked(|q| q.needs_publish) && market::reload_prices().is_ok() {
        queue.update(|q| q.needs_publish = false);
        invalidate();
    }
    let (rows, status) = match saved {
        Some((n, _)) if !queue.with_untracked(|q| q.needs_publish) => (
            n,
            if n == 0 {
                market::RateStatus::Empty
            } else {
                market::RateStatus::Ready
            },
        ),
        _ => (0, market::RateStatus::Failed(clock::now_ms())),
    };
    let key = job.instrument.key();
    let failed = matches!(status, market::RateStatus::Failed(_));
    if failed {
        global::<Queue>().update(|q| q.pending.push_back(job.clone()));
        log::warn!("history: {key} {from}–{to} update failed");
    }
    record_fetch(&key, from, to, rows, failed);
    if let Instrument::Rate(c) = job.instrument {
        market::set_rate_status(c, Some((from, to)), status);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn interval(from: &str, to: &str) -> Period {
        Period {
            from: from.parse().unwrap(),
            to: to.parse().unwrap(),
        }
    }
    fn rate(currency: Currency, period: Period) -> Job {
        Job {
            instrument: Instrument::Rate(currency),
            period,
            epoch: 1,
        }
    }
    fn rates_fixture(job: &Job, _: Date) -> Result<Observations, String> {
        Ok(Observations::Rates(
            [job.period.from, job.period.to]
                .map(|day| currency::FxRate {
                    currency: Currency::USD,
                    day,
                    rate: 7_100_000,
                    source: "frankfurter:ecb".into(),
                })
                .into(),
        ))
    }

    #[component]
    fn HistoricalDataProbe() -> impl IntoElement {
        db::open().unwrap();
        finance::load().unwrap();
        market::load().unwrap();
        let today = clock::today().0;
        let period = Period {
            from: today.checked_sub(jiff::Span::new().days(8)).unwrap(),
            to: today.yesterday().unwrap(),
        };
        finance::store_rates(&[currency::FxRate {
            currency: Currency::USD,
            day: period.from,
            rate: 7_000_000,
            source: "manual".into(),
        }])
        .unwrap();
        market::reload_prices().unwrap();
        let exact = range::resolve(
            HistoryScope::Rate(Currency::USD),
            period,
            market::generation(),
        );
        assert_eq!(
            exact[0].period, period,
            "the rate chart never requests an earlier boundary"
        );
        assert!(range::resolve(HistoryScope::Rate(Currency::CNY), period, 0).is_empty());
        let job = exact[0].clone();
        let completed = signal(false);
        view()
            .child(text("Load range").on_press(move || {
                let job = job.clone();
                global::<Queue>().update(|q| q.active = Some(job.clone()));
                tasks::spawn_app(async move {
                    run_job(&job, rates_fixture).await;
                    completed.set(true);
                });
            }))
            .child(text(move || {
                let rates = finance::rates_snapshot();
                let snapshots: i64 = db::with(|c| {
                    c.query_row(
                        "SELECT count(*) FROM finance_valuation_snapshots",
                        [],
                        |r| r.get(0),
                    )
                })
                .unwrap()
                .unwrap();
                format!(
                    "{} rates, {} manual, {snapshots} snapshots, {}",
                    rates.len(),
                    rates
                        .iter()
                        .filter(|r| r.source == "manual" && r.rate == 7_000_000)
                        .count(),
                    completed.get()
                )
            }))
    }

    #[test]
    fn backfilled_rates_publish_in_place_and_preserve_manual_rates_and_snapshots() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<HistoricalDataProbe>())).unwrap();
        app.wait_for("1 rates, 1 manual, 0 snapshots, false")
            .unwrap();
        app.press("Load range").unwrap();
        app.wait_for("2 rates, 1 manual, 0 snapshots, true")
            .unwrap();
    }

    #[test]
    fn interactive_and_automatic_ranges_share_overlap_and_finish_all_years() {
        let entire = interval("2019-03-01", "2026-11-21");
        let recent = interval("2026-10-12", "2026-11-21");
        let mut q = Queue::default();
        q.enqueue(vec![rate(Currency::USD, recent)], &[], 0, false);
        let first = q.next(1, &[], 0).unwrap();
        assert_eq!(first.period, recent);
        q.enqueue(vec![rate(Currency::USD, entire)], &[], 0, true);
        q.enqueue(vec![rate(Currency::USD, entire)], &[], 0, false);
        let mut spans = vec![first.period];
        while let Some(next) = q.next(1, &[], 0) {
            assert!(
                crate::domain::meal::Day(next.period.to)
                    .days_since(crate::domain::meal::Day(next.period.from))
                    < 365
            );
            spans.push(next.period);
        }
        spans.sort();
        assert_eq!(spans[0].from, entire.from);
        assert_eq!(spans.last().unwrap().to, entire.to);
        assert!(
            spans
                .windows(2)
                .all(|p| p[0].to.tomorrow().unwrap() == p[1].from)
        );
    }

    #[test]
    fn cached_ranges_skip_only_covered_dates_and_failure_pauses_one_pair() {
        let mut q = Queue::default();
        let entire = interval("2026-01-01", "2026-05-31");
        let recent = [
            Attempt {
                key: "fx:USD".into(),
                from: "2026-02-01".parse().unwrap(),
                to: "2026-02-28".parse().unwrap(),
                at: 500,
                failed: false,
                rows: 8,
            },
            Attempt {
                key: "fx:HKD".into(),
                from: entire.from,
                to: entire.to,
                at: 500,
                failed: true,
                rows: 0,
            },
        ];
        q.enqueue(
            vec![rate(Currency::USD, entire), rate(Currency::HKD, entire)],
            &recent,
            510,
            true,
        );
        let mut usd = Vec::new();
        while let Some(job) = q.next(1, &recent, 510) {
            usd.push(job.period);
        }
        usd.sort();
        assert_eq!(
            usd,
            [
                interval("2026-01-01", "2026-01-31"),
                interval("2026-03-01", "2026-05-31")
            ]
        );
        assert_eq!(q.next(1, &recent, 801), Some(rate(Currency::HKD, entire)));
        assert!(q.next(1, &recent, 801).is_none());
    }

    #[test]
    fn binding_and_restore_retire_only_work_owned_by_the_old_identity() {
        let period = interval("2026-01-01", "2026-05-31");
        let binding = catalog::SecurityBinding {
            security: "ABC".into(),
            market: "us_stock".into(),
            symbol: "ABC".into(),
            currency: "USD".into(),
        };
        let original = Job {
            instrument: Instrument::Security(binding.clone()),
            period,
            epoch: 1,
        };
        let fx = rate(Currency::USD, period);
        let mut q = Queue::default();
        q.enqueue(vec![original.clone(), fx.clone()], &[], 500, false);
        assert_eq!(q.next(1, &[], 500), Some(original));
        q.retire_binding("ABC");
        assert!(q.active.is_none());
        let new = Job {
            instrument: Instrument::Security(catalog::SecurityBinding {
                symbol: "DEF".into(),
                ..binding
            }),
            period,
            epoch: 1,
        };
        q.enqueue(vec![new.clone()], &[], 500, true);
        assert_eq!(q.next(1, &[], 500), Some(new));
        assert_eq!(q.next(2, &[], 500), None);
    }
}
