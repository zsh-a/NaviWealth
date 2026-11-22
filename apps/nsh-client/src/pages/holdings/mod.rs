//! A compact portfolio inside Assets: one list, one detail, short editors.
mod editor;
mod list;
mod receipt;
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
pub use list::{closed_page, section};
use navi_finance::{
    currency::Currency,
    holdings::{self, Kind, Security},
    money,
};
use nsh_base::{alert_dialog, nav_page};
use nsh_core::{element::Screen, prelude::*};
pub(super) use receipt::trade_receipt;

/// Identify the observation used for this holding's value.
fn quote_caption(
    q: &holdings::Quote,
    sources: &crate::data::market::PriceSources,
    show_observed_time: bool,
) -> String {
    use crate::{data::market::PriceSource, i18n::market::source_label};
    let mut date = s().short_date(Day(q.day));
    let observed = sources.source(q);
    let source = match observed {
        Some(PriceSource::Manual) => source_label("manual"),
        Some(PriceSource::Close(ref provider)) => source_label(provider),
        Some(PriceSource::Sampled {
            observed_at,
            previous_close,
        }) => {
            if show_observed_time {
                date = clock::zoned(observed_at.as_millisecond())
                    .strftime("%Y-%m-%d %H:%M %Z")
                    .to_string();
                if q.day < clock::today().0 {
                    date.push_str(" · ");
                    date.push_str(crate::i18n::catalog::stale());
                }
            }
            if previous_close {
                crate::i18n::catalog::previous_close()
            } else {
                source_label("tencent")
            }
        }
        None => source_label(""),
    };
    format!("{source} · {date}")
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

pub fn holding_page(id: &str) -> Screen {
    holding_page_with_receipt(id, None)
}

pub(crate) fn holding_page_with_receipt(id: &str, initial_trade: Option<String>) -> Screen {
    let id = stored(id.to_owned());
    let trade = signal(None::<String>);
    let price = signal(false);
    let chart_window = signal(crate::ui::trend::Window::Month);
    let picker = signal(false);
    let binding_error = signal(None::<String>);
    let from_receipt = initial_trade.is_some();
    let receipt = signal(initial_trade);
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
                                // Rebuild formatted quote and listing metadata when the language changes.
                                let _ = locale();
                                let sources = crate::data::market::PriceSources::current();
                                untracked(move || {
                                    let Some(sec) = sec else {
                                        return view().into_element();
                                    };
                                    let currency = sec.currency();
                                    let binding = sources.binding(&sec.id);
                                    let p =
                                        book.position(&sec, today.0).expect("validated holdings");
                                    let value = crate::ui::currency::format(
                                        p.value.unwrap_or(p.cost),
                                        currency,
                                    );
                                    let quote =
                                        p.quote.as_ref().map(|q| quote_caption(q, &sources, true));
                                    let prices = book.dated_prices(&sec, today.0);
                                    let single_price =
                                        p.quote.as_ref().filter(|_| prices.len() == 1).map(|q| {
                                            crate::ui::currency::unit_price(q.price, currency)
                                        });
                                    view()
                                        .gap_3()
                                        .pt_3()
                                        .child(valuation_header(
                                            value,
                                            p.value.is_none() && p.quantity > 0,
                                            move || trade.set(Some(id.get())),
                                        ))
                                        .child(
                                            view()
                                                .gap_2()
                                                .py_2()
                                                .child(pair(
                                                    s().unrealized,
                                                    unrealized_display(&p, currency),
                                                ))
                                                .child(pair(
                                                    s().quantity,
                                                    holdings::format_units(p.quantity),
                                                ))
                                                .child(pair(
                                                    s().unit_cost,
                                                    p.average()
                                                        .map(|v| {
                                                            crate::ui::currency::unit_price(
                                                                v, currency,
                                                            )
                                                        })
                                                        .unwrap_or_else(|| "—".into()),
                                                ))
                                                .child(pair(
                                                    s().holding_cost,
                                                    crate::ui::currency::format(p.cost, currency),
                                                ))
                                                .child((p.realized != 0).then(|| {
                                                    pair(
                                                        s().realized,
                                                        crate::ui::currency::signed(
                                                            p.realized, currency,
                                                        ),
                                                    )
                                                }))
                                                .child((p.dividends != 0).then(|| {
                                                    pair(
                                                        s().dividends,
                                                        crate::ui::currency::format(
                                                            p.dividends,
                                                            currency,
                                                        ),
                                                    )
                                                })),
                                        )
                                        .child(hairline(0.0))
                                        .child(
                                            view()
                                                .gap_1()
                                                .child(listing_link(binding, picker))
                                                .child(note(
                                                    move || binding_error.get().map(Into::into),
                                                    || true,
                                                ))
                                                .child(price_controls(
                                                    single_price,
                                                    quote,
                                                    (binding.is_none() && p.quantity > 0)
                                                        .then_some(price),
                                                    move || {
                                                        nav::push(Route::PricesAndRates(Some(
                                                            id.get(),
                                                        )))
                                                    },
                                                ))
                                                .child((prices.len() > 1).then(|| {
                                                    crate::ui::trend::chart(
                                                        crate::i18n::catalog::copy(
                                                            "Unit price",
                                                            "单位价格",
                                                        )
                                                        .into(),
                                                        prices
                                                            .into_iter()
                                                            .map(|(day, price)| (day, Some(price)))
                                                            .collect(),
                                                        crate::ui::trend::Unit::Price(currency),
                                                        chart_window,
                                                        today.0,
                                                    )
                                                })),
                                        )
                                        .into_element()
                                })
                            }))
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
                                                "{} × {}",
                                                holdings::format_units(t.quantity),
                                                crate::ui::currency::unit_price(t.price, currency)
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
                    move |chosen| {
                        trade_receipt(&chosen, move || {
                            receipt.set(None);
                            if from_receipt {
                                nav::pop();
                            }
                        })
                    },
                )),
        )
}

fn unrealized_display(position: &holdings::Position, currency: Currency) -> String {
    let Some(gain) = position.unrealized() else {
        return "—".into();
    };
    let amount = crate::ui::currency::signed(gain, currency);
    if position.cost <= 0 {
        return amount;
    }
    let cost = i128::from(position.cost);
    let tenths = (i128::from(gain).abs() * 1000 + cost / 2) / cost;
    let sign = if gain < 0 {
        "−"
    } else if gain > 0 {
        "+"
    } else {
        ""
    };
    format!("{amount} · {sign}{}.{:01}%", tenths / 10, tenths % 10)
}

fn valuation_header(
    value: String,
    at_cost: bool,
    record_trade: impl Fn() + 'static,
) -> impl IntoElement {
    view()
        .gap_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(|| s().market_value)
                        .typo(Type::Headline)
                        .text_color(color::BODY)
                        .flex_1(),
                )
                .child(
                    Btn::primary()
                        .size(crate::ui::Size::Small)
                        .icon(Icon::Plus)
                        .label(|| s().holding_trade_action.into())
                        .on_press(record_trade)
                        .min_h(px(48.0))
                        .accessibility_label(|| Some(s().record_trade.into())),
                ),
        )
        .child(
            text(value)
                .typo(Type::Display)
                .text_color(color::INK)
                .tabular_nums()
                .number_of_lines(1)
                .shrink_to_fit(0.55),
        )
        .child(at_cost.then(|| {
            text(|| s().unpriced)
                .typo(Type::Subhead)
                .text_color(color::MUTED)
        }))
}

fn price_controls(
    single_price: Option<String>,
    quote: Option<String>,
    editor: Option<Signal<bool>>,
    history: impl Fn() + 'static,
) -> impl IntoElement {
    view()
        .gap_1()
        .child(
            single_price
                .map(|value| pair(crate::i18n::catalog::copy("Unit price", "单位价格"), value)),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .style_when(|| font_scale() > 1.2, |s| s.flex_col().items_start())
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
                        .child(price_line(quote, editor)),
                )
                .child(
                    Btn::ghost()
                        .size(crate::ui::Size::Small)
                        .label(|| s().holding_prices_action.into())
                        .on_press(history)
                        .min_h(px(48.0))
                        .accessibility_label(|| Some(s().price_history.into())),
                ),
        )
}

fn price_line(caption: Option<String>, editor: Option<Signal<bool>>) -> AnyElement {
    let Some(editor) = editor else {
        return caption
            .map(|caption| {
                text(caption)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
                    .into_element()
            })
            .unwrap_or_else(|| view().into_element());
    };
    let caption =
        caption.unwrap_or_else(|| crate::i18n::catalog::copy("Add price", "录入价格").into());
    row_button(move || editor.set(true))
        .accessibility_label(|| Some(s().update_price.into()))
        .px_0()
        .min_h(px(48.0))
        .gap_2()
        .child(
            text(caption)
                .typo(Type::Subhead)
                .text_color(color::BODY)
                .flex_shrink(1.0),
        )
        .child(crate::ui::icon(Icon::Pencil, 16.0, color::MUTED))
        .into_element()
}

fn listing_link(
    binding: Option<&navi_finance::catalog::SecurityBinding>,
    picker: Signal<bool>,
) -> AnyElement {
    let identity = binding.map(|b| {
        format!(
            "{} · {} · {}",
            crate::i18n::catalog::market(&b.market),
            b.symbol,
            b.currency
        )
    });
    let label = identity
        .clone()
        .unwrap_or_else(|| s().holding_link_action.into());
    row_button(move || picker.set(true))
        .accessibility_label(move || {
            Some(match &identity {
                Some(name) => format!("{name}, {}", crate::i18n::catalog::bind()).into(),
                None => crate::i18n::catalog::bind().into(),
            })
        })
        .self_start()
        .justify_start()
        .px_0()
        .min_h(px(48.0))
        .gap_2()
        .child(crate::ui::icon(Icon::Link, 16.0, color::MUTED))
        .child(
            text(label)
                .typo(Type::Subhead)
                .text_color(color::BODY)
                .flex_shrink(1.0),
        )
        .child(crate::ui::icon(Icon::ChevronRight, 14.0, color::MUTED))
        .into_element()
}
