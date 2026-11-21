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

pub(super) fn panel() -> impl IntoElement {
    let choice = signal(None::<Currency>);
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
                    row_button(move || choice.set(Some(c)))
                        .selected(move || selected.get() == c)
                        .selected_style(|s| s.border_color(color::INK))
                        .border_b(px(2.0))
                        .border_color(color::LINE)
                        .px_0()
                        .py_2()
                        .flex_1()
                        .child(
                            view()
                                .gap_1()
                                .child(text(format!("{c} → CNY")).typo(Type::Headline).text_color(
                                    move || {
                                        if selected.get() == c {
                                            color::INK
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
}
