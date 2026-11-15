//! A compact portfolio inside Assets: one list, one detail, short editors.
mod editor;
use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, Type, Typo, Variant, color,
        field::note,
        surface::{hairline, row_button},
        toast::{show_toast, toast_view},
    },
};
pub use editor::{trade_editor, trade_task};
use navi_finance::{
    currency::Currency,
    holdings::{self, Kind, Security},
    money,
};
use nsh_base::{alert_dialog, nav_page};
use nsh_core::{element::Screen, prelude::*};

fn quote_caption(q: &holdings::Quote, currency: Currency) -> String {
    if let Some(bar) = crate::data::db::with(|c| navi_finance::history::effective_bar(c, q))
        .and_then(Result::ok)
        .flatten()
    {
        format!(
            "{} {} {} · {}",
            crate::i18n::statement_import::copy("Daily close", "日线收盘"),
            currency,
            holdings::format_units(bar.close),
            bar.day
        )
    } else if let Some(network) = crate::data::market::effective_quote(q) {
        let label = if network.previous_close_only {
            crate::i18n::catalog::previous_close()
        } else {
            crate::i18n::catalog::market_price()
        };
        format!(
            "{} {} {} · {}{}",
            label,
            currency,
            holdings::format_units(q.price),
            network.observed_at,
            if q.day < clock::today().0 {
                format!(" · {}", crate::i18n::catalog::stale())
            } else {
                String::new()
            }
        )
    } else {
        format!(
            "{} {} {} · {}",
            s().manual_price,
            currency,
            holdings::format_units(q.price),
            s().short_date(Day(q.day))
        )
    }
}

pub(super) fn kind_label(kind: Kind) -> &'static str {
    match kind {
        Kind::Opening => s().opening_holding,
        Kind::Buy => s().buy,
        Kind::Sell => s().sell,
        Kind::Dividend => s().dividend,
    }
}
pub(super) fn failure(error: &holdings::Error) -> &'static str {
    match error {
        holdings::Error::Oversell => s().holding_oversell,
        holdings::Error::Cash => s().holding_cash_error,
        holdings::Error::Duplicate => s().holding_duplicate,
        holdings::Error::Invalid | holdings::Error::Overflow => s().holding_error,
        _ => s().error_transaction_storage,
    }
}
pub(super) fn amount(value: i64, currency: Currency, style: Type) -> impl IntoElement {
    text(crate::ui::currency::format(value, currency))
        .typo(style)
        .tabular_nums()
        .text_color(color::INK)
}
pub(super) fn pair(
    label: impl IntoReactive<SharedString>,
    value: impl IntoReactive<SharedString>,
) -> impl IntoElement {
    view()
        .flex_row()
        .items_baseline()
        .gap_3()
        .child(
            text(label)
                .typo(Type::Body)
                .text_color(color::MUTED)
                .flex_1(),
        )
        .child(
            text(value)
                .typo(Type::Headline)
                .tabular_nums()
                .text_color(color::INK),
        )
}

pub fn section(closed: bool) -> impl IntoElement {
    dynamic(move || {
        let book = finance::holdings();
        let day = clock::today();
        untracked(move || {
            let positions: Vec<_> = book
                .securities
                .iter()
                .filter_map(|sec| {
                    let p = book.position(sec, day.0).expect("validated holdings");
                    ((p.quantity == 0) == closed).then_some((sec, p))
                })
                .collect();
            if positions.is_empty() {
                return if closed {
                    text(|| s().no_closed_holdings)
                        .typo(Type::Body)
                        .text_color(color::MUTED)
                        .into_element()
                } else {
                    view().into_element()
                };
            }
            view()
                .gap_1()
                .child((!closed).then(|| {
                    text(|| s().holdings)
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(color::MUTED)
                        .role(AccessibilityRole::Header)
                }))
                .children(positions.into_iter().map(|(sec, p)| {
                    let id = sec.id.clone();
                    let status = if closed {
                        s().holding_closed.into()
                    } else {
                        p.quote
                            .as_ref()
                            .map(|q| quote_caption(q, sec.currency()))
                            .unwrap_or_else(|| s().unpriced.into())
                    };
                    let value = p.value.unwrap_or(p.cost);
                    let label = format!(
                        "{}, {} {}, {}",
                        sec.name,
                        money::format(value),
                        sec.currency(),
                        status
                    );
                    view().child(
                        row_button(move || nav::push(Route::Holding(id.clone())))
                            .accessibility_label(move || Some(label.clone().into()))
                            .px_0()
                            .py_3()
                            .gap_3()
                            .min_h(px(56.0))
                            .child(crate::ui::icon(Icon::Chart, 22.0, color::MUTED))
                            .child(
                                view()
                                    .flex_1()
                                    .min_w(px(0.0))
                                    .gap_1()
                                    .child(
                                        text(sec.name.clone())
                                            .typo(Type::Headline)
                                            .text_color(color::INK)
                                            .number_of_lines(1),
                                    )
                                    .child(
                                        text(status).typo(Type::Caption).text_color(color::MUTED),
                                    ),
                            )
                            .child(amount(value, sec.currency(), Type::Headline))
                            .child(crate::ui::icon(Icon::ChevronRight, 16.0, color::MUTED)),
                    )
                }))
                .into_element()
        })
    })
}

pub fn closed_page() -> Screen {
    nav_page()
        .title(|| s().closed_holdings)
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    || s().closed_holdings.into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(crate::ui::space::GUTTER))
                            .pt_4()
                            .pb_safe_area_plus(px(24.0))
                            .child(section(true)),
                    ),
                ),
        )
}

pub fn holding_page(id: &str) -> Screen {
    let id = stored(id.to_owned());
    let trade = signal(None::<String>);
    let price = signal(false);
    let picker = signal(false);
    let binding_error = signal(None::<String>);
    let receipt = signal(None::<String>);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::holding_detail_opened(trade, price);
    let security = move || {
        id.with(|id| {
            finance::holdings()
                .securities
                .into_iter()
                .find(|s| s.id == *id)
        })
    };
    let title = move || {
        security()
            .map(|s| s.name)
            .unwrap_or_else(|| s().holdings.into())
    };
    nav_page()
        .title(title)
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || title().into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px_5()
                            .pb_safe_area_plus(px(80.0))
                            .gap_5()
                            .child(dynamic(move || {
                                let book = finance::holdings();
                                let sec = id.with(|id| {
                                    book.securities.iter().find(|s| s.id == *id).cloned()
                                });
                                let today = clock::today();
                                untracked(move || {
                                    let Some(sec) = sec else {
                                        return view().into_element();
                                    };
                                    let currency = sec.currency();
                                    let p =
                                        book.position(&sec, today.0).expect("validated holdings");
                                    let caption = p
                                        .quote
                                        .as_ref()
                                        .map(|q| quote_caption(q, currency))
                                        .unwrap_or_else(|| s().unpriced.into());
                                    view()
                                        .gap_3()
                                        .pt_4()
                                        .child(
                                            text(|| s().market_value)
                                                .typo(Type::Headline)
                                                .text_color(color::BODY),
                                        )
                                        .child(amount(
                                            p.value.unwrap_or(p.cost),
                                            currency,
                                            Type::Display,
                                        ))
                                        .child(
                                            row_button(move || price.set(true))
                                                .accessibility_label(|| {
                                                    Some(s().update_price.into())
                                                })
                                                .px_0()
                                                .min_h(px(48.0))
                                                .child(
                                                    text(caption)
                                                        .typo(Type::Subhead)
                                                        .text_color(color::MUTED)
                                                        .flex_1(),
                                                )
                                                .child(crate::ui::icon(
                                                    Icon::Pencil,
                                                    18.0,
                                                    color::INK,
                                                )),
                                        )
                                        .child(
                                            Btn::ghost()
                                                .label(move || {
                                                    crate::data::catalog::bindings()
                                                        .into_iter()
                                                        .find(|b| id.with(|v| *v == b.security))
                                                        .map(|b| {
                                                            format!(
                                                                "{} · {} · {}",
                                                                crate::i18n::catalog::market(
                                                                    &b.market
                                                                ),
                                                                b.symbol,
                                                                b.currency
                                                            )
                                                            .into()
                                                        })
                                                        .unwrap_or_else(|| {
                                                            crate::i18n::catalog::bind().into()
                                                        })
                                                })
                                                .on_press(move || picker.set(true)),
                                        )
                                        .child(note(
                                            move || binding_error.get().map(Into::into),
                                            || true,
                                        ))
                                        .child(pair(
                                            s().quantity,
                                            holdings::format_units(p.quantity),
                                        ))
                                        .child(pair(
                                            s().unit_cost,
                                            p.average()
                                                .map(|v| {
                                                    format!(
                                                        "{} {}",
                                                        currency,
                                                        holdings::format_units(v)
                                                    )
                                                })
                                                .unwrap_or_else(|| "—".into()),
                                        ))
                                        .child(pair(
                                            s().holding_cost,
                                            crate::ui::currency::format(p.cost, currency),
                                        ))
                                        .child(pair(
                                            s().unrealized,
                                            p.unrealized()
                                                .map(|v| crate::ui::currency::format(v, currency))
                                                .unwrap_or_else(|| "—".into()),
                                        ))
                                        .child(
                                            Btn::tonal()
                                                .label(|| s().record_trade.into())
                                                .on_press(move || trade.set(Some(sec.id.clone()))),
                                        )
                                        .child((p.realized != 0).then(|| {
                                            pair(
                                                s().realized,
                                                crate::ui::currency::format(p.realized, currency),
                                            )
                                        }))
                                        .child((p.dividends != 0).then(|| {
                                            pair(
                                                s().dividends,
                                                crate::ui::currency::format(p.dividends, currency),
                                            )
                                        }))
                                        .into_element()
                                })
                            }))
                            .child(
                                Btn::ghost()
                                    .label(|| {
                                        crate::i18n::statement_import::copy(
                                            "Price history",
                                            "价格记录",
                                        )
                                        .into()
                                    })
                                    .on_press(move || {
                                        nav::push(Route::PriceHistory(Some(id.get())))
                                    }),
                            )
                            .child(
                                text(|| s().holding_history)
                                    .typo(Type::Title)
                                    .text_color(color::INK),
                            )
                            .child(dynamic(move || {
                                let book = finance::holdings();
                                let currency = book
                                    .securities
                                    .iter()
                                    .find(|s| id.with(|id| *id == s.id))
                                    .map(Security::currency)
                                    .unwrap_or(Currency::CNY);
                                let mut history: Vec<_> = book
                                    .trades
                                    .iter()
                                    .filter(|t| id.with(|id| *id == t.security))
                                    .cloned()
                                    .collect();
                                history.reverse();
                                untracked(move || {
                                    view().children(history.into_iter().map(|t| {
                                        let label = kind_label(t.kind);
                                        let detail = if t.kind == Kind::Dividend {
                                            crate::ui::currency::format(t.amount, currency)
                                        } else {
                                            format!(
                                                "{} × {} {}",
                                                holdings::format_units(t.quantity),
                                                currency,
                                                holdings::format_units(t.price)
                                            )
                                        };
                                        let accessibility = format!("{label}, {detail}");
                                        view()
                                            .child(
                                                row_button(move || receipt.set(Some(t.id.clone())))
                                                    .accessibility_label(move || {
                                                        Some(accessibility.clone().into())
                                                    })
                                                    .px_0()
                                                    .child(
                                                        view()
                                                            .flex_1()
                                                            .gap_1()
                                                            .child(
                                                                text(label)
                                                                    .typo(Type::Headline)
                                                                    .text_color(color::INK),
                                                            )
                                                            .child(
                                                                text(
                                                                    s().short_date(Day(t
                                                                        .at
                                                                        .date())),
                                                                )
                                                                .typo(Type::Subhead)
                                                                .text_color(color::MUTED),
                                                            ),
                                                    )
                                                    .child(
                                                        text(detail)
                                                            .typo(Type::Body)
                                                            .text_color(color::INK)
                                                            .tabular_nums(),
                                                    ),
                                            )
                                            .child(hairline(0.0))
                                    }))
                                })
                            })),
                    ),
                )
                .child(
                    view()
                        .absolute()
                        .inset_0()
                        .pointer_events(PointerEvents::BoxNone)
                        .style_when(
                            move || trade.get().is_some() || price.get() || receipt.get().is_some(),
                            |s| s.hidden(),
                        )
                        .child(toast_view(|| 24.0)),
                )
                .child(crate::pages::security_picker::selector(
                    picker,
                    move |entry| {
                        let Some(sec) = security() else {
                            return;
                        };
                        let binding = entry.binding(&sec.id);
                        let answer = alert_dialog()
                            .title(crate::i18n::catalog::confirm())
                            .description(format!(
                                "{} · {} · {} · {}\n{}",
                                entry.name(),
                                crate::i18n::catalog::market(&entry.market),
                                entry.symbol,
                                entry.currency,
                                crate::i18n::catalog::body()
                            ))
                            .cancel("cancel", s().cancel)
                            .action("bind", crate::i18n::catalog::confirm())
                            .show();
                        crate::data::tasks::spawn_app(async move {
                            if answer
                                .await
                                .is_ok_and(|r| r.action.as_deref() == Some("bind"))
                            {
                                match crate::data::catalog::bind(&binding) {
                                    Ok(()) => binding_error.set(None),
                                    Err(e) => {
                                        log::warn!("holding binding failed: {e}");
                                        binding_error
                                            .set(Some(crate::i18n::catalog::bind_failed().into()));
                                    }
                                }
                            }
                        });
                    },
                ))
                .child(trade_editor(trade))
                .child(editor::price_editor(price, security))
                .child(crate::ui::sheet::retained(
                    move || receipt.get(),
                    move |chosen| trade_receipt(&chosen, move || receipt.set(None)),
                )),
        )
}

pub(super) fn trade_receipt(id: &str, close: impl Fn() + Copy + 'static) -> AnyElement {
    let book = finance::holdings();
    let Some(t) = book.trades.iter().find(|t| t.id == id).cloned() else {
        return view().into_element();
    };
    let sec = book.securities.iter().find(|s| s.id == t.security).unwrap();
    let error = signal(None::<String>);
    let open = signal(true);
    let close = move || {
        open.set(false);
        close();
    };
    let header = view()
        .flex_row()
        .items_center()
        .child(
            text(format!("{} · {}", kind_label(t.kind), sec.name))
                .typo(Type::Title)
                .text_color(color::INK)
                .flex_1(),
        )
        .child(Btn::ghost().label(|| s().close.into()).on_press(close));
    let body = view()
        .gap_3()
        .child(
            text(s().long_date(Day(t.at.date())))
                .typo(Type::Body)
                .text_color(color::MUTED),
        )
        .child(if t.kind == Kind::Dividend {
            pair(
                s().dividend_amount,
                crate::ui::currency::format(t.amount, sec.currency()),
            )
            .into_element()
        } else {
            view()
                .gap_3()
                .child(pair(s().quantity, holdings::format_units(t.quantity)))
                .child(pair(
                    s().trade_price,
                    format!("{} {}", sec.currency(), holdings::format_units(t.price)),
                ))
                .into_element()
        })
        .child(pair(
            s().fee,
            crate::ui::currency::format(t.fee, sec.currency()),
        ))
        .child(
            t.cash
                .as_ref()
                .map(|a| pair(s().cash_account, a.name().to_owned())),
        );
    let action = view()
        .gap_2()
        .child(note(move || error.get().map(Into::into), || true))
        .child(
            Btn::new(Variant::Danger)
                .label(|| s().remove_trade.into())
                .on_press(move || {
                    let id = t.id.clone();
                    let answer = alert_dialog()
                        .title(s().holding_delete_title)
                        .description(s().holding_delete_body)
                        .cancel("keep", s().cancel)
                        .destructive("delete", s().remove_trade)
                        .show();
                    spawn(async move {
                        if answer
                            .await
                            .is_ok_and(|r| r.action.as_deref() == Some("delete"))
                        {
                            match finance::remove_trade(&id) {
                                Ok(()) => {
                                    close();
                                    show_toast(s().trade_deleted, None);
                                }
                                Err(e) => {
                                    log::error!("holdings: delete failed: {e}");
                                    error.set(Some(failure(&e).into()));
                                }
                            }
                        }
                    });
                }),
        );
    crate::ui::sheet::task_sheet(move || open.get(), close, header, body, action).into_element()
}
