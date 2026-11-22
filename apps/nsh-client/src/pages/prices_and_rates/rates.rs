//! Inspect one dated currency pair at a time.
use crate::{
    data::{
        clock, finance,
        market::{RateStatus, rate_status},
    },
    domain::meal::Day,
    i18n::{market::source_label, statement_import::copy},
    nav,
    ui::{
        Btn, Type, Typo, color, space,
        surface::row_button,
        trend::{self, Unit, Window},
    },
};
use navi_finance::{
    currency::{self, Currency, FxRate},
    holdings::format_units,
};
use nsh_core::prelude::*;

pub(super) fn panel(choice: Signal<Option<Currency>>) -> impl IntoElement {
    let from_overview = matches!(
        crate::nav::open().last(),
        Some(crate::nav::Route::ExchangeRate(_))
    );
    let window = signal(Window::Month);
    let selected = computed(move || {
        choice.get().unwrap_or_else(|| {
            if currency::rate_in(&finance::rates_snapshot(), Currency::HKD, clock::today().0)
                .is_some()
                && currency::rate_in(&finance::rates_snapshot(), Currency::USD, clock::today().0)
                    .is_none()
            {
                Currency::HKD
            } else {
                Currency::USD
            }
        })
    });
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .gap_3()
                .children([Currency::USD, Currency::HKD].map(move |c| {
                    let is_selected = move || selected.get() == c;
                    row_button(move || choice.set(Some(c)))
                        .selected(is_selected)
                        .px_0()
                        .py_2()
                        .flex_1()
                        .child(
                            view()
                                .flex_1()
                                .min_w(px(0.0))
                                .gap_1()
                                .child(text(format!("{c} → CNY")).typo(Type::Headline).text_color(
                                    move || {
                                        if is_selected() {
                                            color::ACCENT_INK
                                        } else {
                                            color::MUTED
                                        }
                                    },
                                ))
                                .child(dynamic(move || {
                                    currency::rate_in(
                                        &finance::rates_snapshot(),
                                        c,
                                        clock::today().0,
                                    )
                                    .map(|r| {
                                        text(format!("{} · {}", r.day, source_label(&r.source)))
                                            .typo(Type::Caption)
                                            .text_color(color::MUTED)
                                            .into_element()
                                    })
                                    .unwrap_or_else(|| view().into_element())
                                }))
                                .child(
                                    view()
                                        .w(relative(1.0 / 3.0))
                                        .h(px(2.0))
                                        .rounded_full()
                                        .bg(color::ACCENT)
                                        .opacity(move || if is_selected() { 1.0_f32 } else { 0.0 })
                                        .accessibility_elements_hidden(true),
                                ),
                        )
                })),
        )
        .child(dynamic(move || {
            let c = selected.get();
            let today = clock::today().0;
            let points: Vec<_> = finance::rates_snapshot()
                .iter()
                .filter(|r| r.currency == c && r.day <= today)
                .map(|r| (r.day, Some(r.rate)))
                .collect();
            let title = if c == Currency::USD {
                copy("CNY per US dollar", "1 美元兑人民币")
            } else {
                copy("CNY per HK dollar", "1 港元兑人民币")
            };
            if points.is_empty() {
                text(title)
                    .typo(Type::Headline)
                    .text_color(color::BODY)
                    .into_element()
            } else {
                untracked(|| trend::chart(title.into(), points, Unit::Rate, window, today))
            }
        }))
        .child(dynamic(move || {
            let c = selected.get();
            let message = attempt_label(rate_status(c, None)).or_else(|| {
                currency::rate_in(&finance::rates_snapshot(), c, clock::today().0)
                    .is_none()
                    .then(|| copy("No rate available", "暂无汇率").into())
            });
            message
                .map(|label| {
                    text(label)
                        .typo(Type::Caption)
                        .text_color(color::BODY)
                        .into_element()
                })
                .unwrap_or_else(|| view().into_element())
        }))
        .child(from_overview.then(|| {
            dynamic(move || {
                let currency = selected.get();
                let valuation = crate::pages::assets::current::get();
                let Some(group) = valuation.as_ref().and_then(|v| v.excluded.get(&currency)) else {
                    return view().into_element();
                };
                view()
                    .test_id("excluded-fx-items")
                    .pt_2()
                    .gap_3()
                    .child(
                        text(copy("Excluded from net worth", "未计入净资产"))
                            .typo(Type::Headline)
                            .text_color(color::INK)
                            .role(AccessibilityRole::Header),
                    )
                    .children(group.groups().map(|(label, names)| {
                        view()
                            .gap_1()
                            .child(text(label).typo(Type::Caption).text_color(color::MUTED))
                            .children(
                                names
                                    .iter()
                                    .cloned()
                                    .map(|name| text(name).typo(Type::Body).text_color(color::INK)),
                            )
                    }))
                    .into_element()
            })
        }))
}

fn attempt_label(status: Option<RateStatus>) -> Option<String> {
    match status? {
        RateStatus::Ready => None,
        RateStatus::Loading => Some(copy("Updating rates…", "正在获取汇率…").into()),
        RateStatus::Empty => Some(copy("No rate published", "数据源暂无报价").into()),
        RateStatus::Failed(at) => {
            let mut time = clock::time_label(at);
            if clock::day_of(at) != clock::today() {
                time = format!("{} {time}", clock::day_of(at));
            }
            Some(format!("{} · {time}", copy("Update failed", "更新失败")))
        }
    }
}

pub(crate) fn historical_rate(currency: Currency, from: Day, to: Day) -> nsh_core::element::Screen {
    let shown = signal(30usize);
    nsh_base::nav_page()
        .header_visible(false)
        .status_bar(super::super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::super::parts::top_bar(
                    move || format!("{currency} → CNY").into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_4()
                            .pb_safe_area_plus(px(24.0))
                            .gap_4()
                            .child(
                                text(if from == to {
                                    from.to_string()
                                } else {
                                    format!("{from} – {to}")
                                })
                                .typo(Type::Headline)
                                .text_color(color::INK)
                                .tabular_nums(),
                            )
                            .child(dynamic(move || {
                                historical_records(currency, from, to, shown)
                            })),
                    ),
                ),
        )
}

fn historical_records(currency: Currency, from: Day, to: Day, shown: Signal<usize>) -> AnyElement {
    let rates = finance::rates_snapshot();
    let status = rate_status(currency, Some((from.0, to.0)));
    let start = currency::rate_in(&rates, currency, from.0);
    let mut observations: Vec<_> = rates
        .iter()
        .filter(|r| r.currency == currency && r.day > from.0 && r.day <= to.0)
        .collect();
    let mut content = view().gap_3();
    if let Some(initial) = start.as_ref() {
        observations.insert(0, initial);
    } else if let Some(first) = observations.first() {
        let end = first.day.yesterday().unwrap_or(from.0);
        content = content.child(
            text(format!(
                "{} · {} – {end}",
                copy("Missing rate", "缺汇率"),
                from.0
            ))
            .typo(Type::Subhead)
            .text_color(color::BODY),
        );
    }
    if observations.is_empty() {
        content = content.child(
            text(copy("No rate for this period", "区间内暂无汇率"))
                .typo(Type::Body)
                .text_color(color::BODY),
        );
    }
    if let Some(message) = attempt_label(status) {
        content = content.child(text(message).typo(Type::Caption).text_color(color::BODY));
    }
    if observations.is_empty() {
        if let Some(next) = rates
            .iter()
            .find(|r| r.currency == currency && r.day > to.0 && r.day <= clock::today().0)
        {
            content = content
                .child(
                    text(copy("Next recorded rate", "下一条汇率记录"))
                        .pt_4()
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(rate_row(next));
        }
    } else {
        let count = shown.get();
        content = content.children(observations.iter().rev().take(count).map(|r| {
            if r.day < from.0 {
                view()
                    .gap_1()
                    .child(
                        text(copy("Opening rate", "期初汇率"))
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                    )
                    .child(rate_row(r))
                    .into_element()
            } else {
                rate_row(r)
            }
        }));
        if observations.len() > count {
            content = content.child(
                Btn::ghost()
                    .label(|| copy("Show more", "查看更多").into())
                    .on_press(move || shown.update(|n| *n += 30)),
            );
        }
    }
    content.into_element()
}

fn rate_row(rate: &FxRate) -> AnyElement {
    view()
        .flex_row()
        .flex_wrap()
        .gap_2()
        .items_baseline()
        .justify_between()
        .child(
            text(format!("{} · {}", rate.day, source_label(&rate.source)))
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        )
        .child(
            text(format_units(rate.rate))
                .typo(Type::Body)
                .text_color(color::INK)
                .tabular_nums(),
        )
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{db, market};
    use navi_finance::{account::Account, journal};
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn RateRefresh() -> impl IntoElement {
        db::open().unwrap();
        finance::load().unwrap();
        let bank = Account::parse("资产/USD:Dollar bank").unwrap();
        finance::create_account(bank.clone()).unwrap();
        let entry = journal::Entry {
            id: "balance".into(),
            at: clock::today().0.at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: journal::Source::Manual,
        };
        finance::save(journal::opening(entry, &bank, 100).unwrap()).unwrap();
        crate::pages::assets::current::provide();
        crate::nav::push(crate::nav::Route::ExchangeRate(Currency::USD));
        view()
            .child(text("Receive rate").on_press(|| {
                finance::store_rates(&[currency::FxRate {
                    currency: Currency::USD,
                    day: clock::today().0,
                    rate: 7_000_000,
                    source: "frankfurter:ecb".into(),
                }])
                .unwrap();
                market::reload_prices().unwrap();
            }))
            .child(panel(signal(Some(Currency::USD))))
    }

    #[component]
    fn RatePeriod() -> impl IntoElement {
        db::open().unwrap();
        finance::load().unwrap();
        let from = clock::today().plus_days(-12);
        let to = from.plus_days(4);
        let save = move |day: Day, rate| {
            finance::store_rates(&[FxRate {
                currency: Currency::USD,
                day: day.0,
                rate,
                source: "manual".into(),
            }])
            .unwrap();
            market::reload_prices().unwrap();
        };
        save(to.plus_days(1), 7_028_000);
        let shown = signal(30);
        view()
            .child(text("Midperiod rate").on_press(move || save(from.plus_days(1), 7_123_000)))
            .child(
                text("Opening rate arrives").on_press(move || save(from.plus_days(-1), 7_109_000)),
            )
            .child(dynamic(move || {
                historical_records(Currency::USD, from, to, shown)
            }))
    }

    #[test]
    fn historical_gap_uses_only_rates_available_on_the_selected_dates() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RatePeriod>())).unwrap();
        app.wait_for("No rate for this period").unwrap();
        app.wait_for("Next recorded rate").unwrap();
        app.wait_for("text:7.028").unwrap();
        app.press("Midperiod rate").unwrap();
        app.wait_for("text:/^Missing rate/").unwrap();
        app.wait_for("text:7.123").unwrap();
        assert!(!app.shows("text:7.028"));
        app.press("Opening rate arrives").unwrap();
        app.wait_for("text:Opening rate").unwrap();
        app.wait_for("text:7.109").unwrap();
        assert!(!app.shows("text:/^Missing rate/"));
    }

    #[test]
    fn excluded_list_disappears_on_an_open_pair_when_the_rate_arrives() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RateRefresh>())).unwrap();
        app.wait_for("id:excluded-fx-items >> text:Dollar bank")
            .unwrap();
        app.press("Receive rate").unwrap();
        app.wait_for_gone("id:excluded-fx-items", std::time::Duration::from_secs(2))
            .unwrap();
        app.wait_for("CNY per US dollar").unwrap();
    }
}
