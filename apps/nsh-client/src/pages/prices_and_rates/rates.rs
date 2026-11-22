//! Inspect one dated currency pair at a time.
use crate::{
    data::{clock, finance},
    i18n::statement_import::copy,
    ui::{
        Type, Typo, color,
        surface::row_button,
        trend::{self, Unit, Window},
    },
};
use navi_finance::currency::{self, Currency};
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
                                .child(
                                    text(move || {
                                        currency::rate_in(
                                            &finance::rates_snapshot(),
                                            c,
                                            clock::today().0,
                                        )
                                        .map(|r| {
                                            format!(
                                                "{} · {}",
                                                r.day,
                                                crate::i18n::market::source_label(&r.source)
                                            )
                                        })
                                        .unwrap_or_else(
                                            || copy("No rate available", "暂无汇率").into(),
                                        )
                                    })
                                    .typo(Type::Caption)
                                    .text_color(color::MUTED),
                                )
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
            let points = finance::rates_snapshot()
                .iter()
                .filter(|r| r.currency == c && r.day <= today)
                .map(|r| (r.day, Some(r.rate)))
                .collect();
            let title = if c == Currency::USD {
                copy("CNY per US dollar", "1 美元兑人民币")
            } else {
                copy("CNY per HK dollar", "1 港元兑人民币")
            };
            untracked(|| trend::chart(title.into(), points, Unit::Rate, window, today))
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
