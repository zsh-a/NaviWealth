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
        surface::{card, hairline, row_button},
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

/// The list uses source and date; details also show the native price and observation time.
fn quote_caption(
    q: &holdings::Quote,
    sources: &crate::data::market::PriceSources,
    detail_currency: Option<Currency>,
) -> String {
    use crate::data::market::PriceSource;
    let mut date = s().short_date(Day(q.day));
    let source = match sources.source(q) {
        Some(PriceSource::Manual) => s().manual_price,
        Some(PriceSource::Close) => crate::i18n::statement_import::copy("Daily close", "日线收盘"),
        Some(PriceSource::Sampled {
            observed_at,
            previous_close,
        }) => {
            if detail_currency.is_some() {
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
                crate::i18n::catalog::market_price()
            }
        }
        None => s().price_date,
    };
    match detail_currency {
        Some(cur) => format!(
            "{source} {} · {date}",
            crate::ui::currency::unit_price(q.price, cur)
        ),
        None => format!("{source} · {date}"),
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
                                let sources = crate::data::market::PriceSources::current();
                                untracked(move || {
                                    let Some(sec) = sec else {
                                        return view().into_element();
                                    };
                                    let currency = sec.currency();
                                    let binding = sources.binding(&sec.id);
                                    let trade_style = if binding.is_some() { Variant::Primary } else { Variant::Secondary };
                                    let p =
                                        book.position(&sec, today.0).expect("validated holdings");
                                    let caption = p
                                        .quote
                                        .as_ref()
                                        .map(|q| quote_caption(q, &sources, Some(currency)))
                                        .unwrap_or_else(|| s().unpriced.into());
                                    view()
                                        .gap_3()
                                        .pt_4()
                                        .child(
                                            card()
                                                .p_5()
                                                .gap_3()
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
                                                        .child(
                                                            (p.quote.is_none() && p.quantity > 0)
                                                                .then(|| {
                                                                    text(crate::i18n::statement_import::copy("Add price", "录入价格"))
                                                                        .typo(Type::Subhead)
                                                                        .text_color(color::INK)
                                                                }),
                                                        )
                                                        .child(crate::ui::icon(
                                                            Icon::Pencil,
                                                            18.0,
                                                            color::INK,
                                                        )),
                                                )
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
                                                .child(pair(
                                                    s().unrealized,
                                                    unrealized_display(&p, currency),
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
                                        .child(
                                            view()
                                                .flex_row()
                                                .gap_2()
                                                .style_when(|| font_scale() > 1.2, |s| s.flex_col())
                                                .child(detail_action(
                                                    trade_style, Icon::Plus,
                                                    || s().holding_trade_action,
                                                    || s().record_trade,
                                                    move || trade.set(Some(sec.id.clone())),
                                                ))
                                                .child(detail_action(
                                                    Variant::Secondary, Icon::Link,
                                                    || s().holding_link_action,
                                                    crate::i18n::catalog::bind,
                                                    move || picker.set(true),
                                                ))
                                                .child(detail_action(
                                                    Variant::Secondary, Icon::Chart,
                                                    || s().holding_prices_action,
                                                    || s().price_history,
                                                    move || {
                                                        nav::push(Route::PriceHistory(Some(
                                                            id.get(),
                                                        )))
                                                    },
                                                )),
                                        )
                                        .child(binding.map(binding_caption))
                                        .child(note(
                                            move || binding_error.get().map(Into::into),
                                            || true,
                                        ))
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
                    move |chosen| trade_receipt(&chosen, move || receipt.set(None)),
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

fn detail_action(
    style: Variant,
    glyph: Icon,
    label: fn() -> &'static str,
    accessible: fn() -> &'static str,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    Btn::new(style)
        .icon(glyph)
        .on_press(press)
        .accessibility_label(move || Some(accessible().into()))
        .flex_col()
        .flex_1()
        .basis(px(0.0))
        .min_w(px(0.0))
        .min_h(px(64.0))
        .px_2()
        .py_2()
        .gap_1()
        .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
        .child(
            text(label)
                .typo(Type::Subhead)
                .text_color(if style == Variant::Primary {
                    color::ON_ACTION
                } else {
                    color::INK
                })
                .text_center(),
        )
}

fn binding_caption(b: &navi_finance::catalog::SecurityBinding) -> AnyElement {
    text(format!(
        "{} · {} · {}",
        crate::i18n::catalog::market(&b.market),
        b.symbol,
        b.currency
    ))
    .typo(Type::Caption)
    .text_color(color::MUTED)
    .into_element()
}
