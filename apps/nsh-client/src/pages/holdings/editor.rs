use super::*;
use crate::ui::{
    field::{field, text_input},
    segmented::{Segment, segmented},
    sheet::task_sheet,
    surface::disclosure,
};
use finance_core::{
    account::{Account, AccountKind},
    holdings::{Quote, Trade},
};
use nsh_core::element::KeyboardType;
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);
fn id() -> String {
    format!(
        "{}-{}",
        clock::now_ms(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    )
}

fn guarded(
    dirty: impl Fn() -> bool + Copy + 'static,
    close: impl Fn() + Copy + 'static,
) -> impl Fn() + Copy {
    let asking = signal(false);
    move || {
        dismiss_keyboard();
        if !dirty() {
            close();
            return;
        }
        if asking.get_untracked() {
            return;
        }
        asking.set(true);
        let answer = alert_dialog()
            .title(s().discard_title)
            .description(s().finance_discard_body)
            .cancel("keep", s().keep_editing)
            .destructive("discard", s().discard)
            .show();
        spawn(async move {
            let discard = answer
                .await
                .is_ok_and(|r| r.action.as_deref() == Some("discard"));
            asking.set(false);
            if discard {
                close();
            }
        });
    }
}
fn decimal(
    value: Signal<String>,
    label: impl Fn() -> &'static str + Copy + 'static,
) -> impl IntoElement {
    field(
        label,
        text_input(value)
            .keyboard_type(KeyboardType::Decimal)
            .label(label)
            .placeholder("0")
            .tabular_nums(),
    )
}
#[derive(Clone, Copy, PartialEq)]
enum Panel {
    Main,
    Date,
    Cash,
}
#[derive(Clone, PartialEq)]
struct Values {
    kind: Kind,
    name: String,
    quantity: String,
    price: String,
    fee: String,
    cash: Option<Account>,
    day: String,
}

pub fn trade_editor(open: Signal<Option<String>>) -> impl IntoElement {
    dynamic(move || {
        let Some(chosen) = open.get() else {
            return view().into_element();
        };
        untracked(move || {
            let book = finance::holdings();
            let existing = book.securities.iter().find(|s| s.id == chosen).cloned();
            let new = chosen.is_empty();
            if !new && existing.is_none() {
                return view().into_element();
            }
            let security_id = stored(
                existing
                    .as_ref()
                    .map(|s| s.id.clone())
                    .unwrap_or_else(|| format!("s{}", id())),
            );
            let trade_id = stored(id());
            let empty_history = new || !book.trades.iter().any(|t| t.security == chosen);
            let kind = signal(if empty_history {
                Kind::Opening
            } else {
                Kind::Buy
            });
            let name = signal(
                existing
                    .as_ref()
                    .map(|s| s.name.clone())
                    .unwrap_or_default(),
            );
            let quantity = signal(String::new());
            let price = signal(String::new());
            let fee = signal(String::new());
            let accounts: Vec<_> = finance::accounts()
                .into_iter()
                .filter(|a| a.is_cash() && a.kind() == AccountKind::Assets)
                .collect();
            let cash = signal((accounts.len() == 1).then(|| accounts[0].clone()));
            let day = signal(clock::today().to_string());
            let details = signal(false);
            let panel = signal(Panel::Main);
            let error = signal(None::<String>);
            let values = move || Values {
                kind: kind.get_untracked(),
                name: name.get_untracked(),
                quantity: quantity.get_untracked(),
                price: price.get_untracked(),
                fee: fee.get_untracked(),
                cash: cash.get_untracked(),
                day: day.get_untracked(),
            };
            let initial = stored(values());
            let discard = guarded(
                move || initial.with(|v| v != &values()),
                move || open.set(None),
            );
            let close = move || {
                if panel.get_untracked() != Panel::Main {
                    panel.set(Panel::Main);
                    dismiss_keyboard();
                } else {
                    discard();
                }
            };
            let header = view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(if new {
                        s().add_holding
                    } else {
                        s().record_trade
                    })
                    .typo(Type::Title)
                    .text_color(color::INK)
                    .flex_1(),
                )
                .child(
                    Btn::ghost()
                        .label(move || {
                            if panel.get() != Panel::Main {
                                s().back.into()
                            } else {
                                s().cancel.into()
                            }
                        })
                        .on_press(close),
                );
            let body = dynamic(move || {
                let current_panel = panel.get();
                let current_kind = kind.get();
                untracked(move || {
                    if current_panel == Panel::Date {
                        return super::super::finance::date_picker(day, move || {
                            panel.set(Panel::Main)
                        })
                        .into_element();
                    }
                    if current_panel == Panel::Cash {
                        let accounts: Vec<_> = finance::accounts()
                            .into_iter()
                            .filter(|a| a.is_cash() && a.kind() == AccountKind::Assets)
                            .collect();
                        if accounts.is_empty() {
                            return text(|| s().holding_cash_error)
                                .typo(Type::Body)
                                .text_color(color::MUTED)
                                .into_element();
                        }
                        return view()
                            .children(accounts.into_iter().map(move |a| {
                                let label = a.name().to_owned();
                                row_button(move || {
                                    cash.set(Some(a.clone()));
                                    panel.set(Panel::Main);
                                })
                                .px_0()
                                .child(text(label).typo(Type::Body).text_color(color::INK))
                            }))
                            .into_element();
                    }
                    let options = if empty_history {
                        vec![
                            Segment::new(Kind::Opening, || s().opening_holding.into()),
                            Segment::new(Kind::Buy, || s().buy.into()),
                        ]
                    } else {
                        vec![
                            Segment::new(Kind::Buy, || s().buy.into()),
                            Segment::new(Kind::Sell, || s().sell.into()),
                            Segment::new(Kind::Dividend, || s().dividend.into()),
                        ]
                    };
                    view()
                        .gap_3()
                        .child(segmented(
                            options,
                            move || kind.get(),
                            move |v| {
                                kind.set(v);
                                error.set(None);
                            },
                        ))
                        .child(if new {
                            field(
                                || s().security_name,
                                text_input(name)
                                    .label(|| s().security_name)
                                    .placeholder(|| s().security_hint),
                            )
                            .into_element()
                        } else {
                            text(move || name.get())
                                .typo(Type::Headline)
                                .text_color(color::INK)
                                .into_element()
                        })
                        .child(if current_kind == Kind::Dividend {
                            decimal(price, || s().dividend_amount).into_element()
                        } else {
                            view()
                                .flex_row()
                                .gap_3()
                                .child(
                                    view()
                                        .flex_1()
                                        .min_w(px(0.0))
                                        .child(decimal(quantity, || s().quantity)),
                                )
                                .child(view().flex_1().min_w(px(0.0)).child(decimal(
                                    price,
                                    move || {
                                        if current_kind == Kind::Opening {
                                            s().unit_cost
                                        } else {
                                            s().trade_price
                                        }
                                    },
                                )))
                                .into_element()
                        })
                        .child((current_kind != Kind::Opening).then(|| {
                            row_button(move || {
                                dismiss_keyboard();
                                panel.set(Panel::Cash);
                            })
                            .accessibility_label(|| Some(s().cash_account.into()))
                            .px_0()
                            .min_h(px(48.0))
                            .child(
                                text(|| s().cash_account)
                                    .typo(Type::Body)
                                    .text_color(color::MUTED)
                                    .flex_1(),
                            )
                            .child(
                                text(move || {
                                    cash.get()
                                        .map(|a| a.name().to_owned())
                                        .unwrap_or_else(|| s().choose_account.into())
                                })
                                .typo(Type::Body)
                                .text_color(color::INK),
                            )
                        }))
                        .child(
                            text(if current_kind == Kind::Opening {
                                s().opening_hint
                            } else {
                                s().holding_cash_effect
                            })
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                        )
                        .child(disclosure(details, || s().trade_details.into()))
                        .child(when(
                            move || details.get(),
                            move || {
                                view()
                                    .gap_3()
                                    .child(
                                        (current_kind != Kind::Opening)
                                            .then(|| decimal(fee, || s().fee)),
                                    )
                                    .child(
                                        row_button(move || {
                                            dismiss_keyboard();
                                            panel.set(Panel::Date);
                                        })
                                        .accessibility_label(|| Some(s().transaction_date.into()))
                                        .px_0()
                                        .child(
                                            text(|| s().transaction_date)
                                                .typo(Type::Body)
                                                .text_color(color::MUTED)
                                                .flex_1(),
                                        )
                                        .child(
                                            text(move || {
                                                day.get()
                                                    .parse::<Day>()
                                                    .map(|d| s().short_date(d))
                                                    .unwrap_or_default()
                                            })
                                            .typo(Type::Body)
                                            .text_color(color::INK),
                                        ),
                                    )
                            },
                        ))
                        .child(new.then(|| {
                            text(|| s().holding_scope)
                                .typo(Type::Caption)
                                .text_color(color::MUTED)
                        }))
                        .into_element()
                })
            });
            let action = view()
                .gap_2()
                .child(note(move || error.get().map(Into::into), || true))
                .child(
                    Btn::primary()
                        .label(move || {
                            if panel.get() != Panel::Main {
                                s().done.into()
                            } else if new {
                                s().save_holding.into()
                            } else {
                                s().save_trade.into()
                            }
                        })
                        .on_press(move || {
                            if panel.get_untracked() != Panel::Main {
                                panel.set(Panel::Main);
                                return;
                            }
                            let form = values();
                            let build = || -> Result<(Security, Trade), holdings::Error> {
                                let security =
                                    Security::new(&security_id.with(|v| v.clone()), &form.name)?;
                                let day = form
                                    .day
                                    .parse::<Day>()
                                    .map_err(|_| holdings::Error::Invalid)?;
                                let fee =
                                    if form.kind == Kind::Opening || form.fee.trim().is_empty() {
                                        0
                                    } else {
                                        money::parse(&form.fee, false)
                                            .ok_or(holdings::Error::Invalid)?
                                    };
                                let quantity = if form.kind == Kind::Dividend {
                                    0
                                } else {
                                    holdings::parse_units(&form.quantity)
                                        .filter(|q| *q > 0)
                                        .ok_or(holdings::Error::Invalid)?
                                };
                                let price = if form.kind == Kind::Dividend {
                                    0
                                } else {
                                    holdings::parse_units(&form.price)
                                        .filter(|q| *q > 0)
                                        .ok_or(holdings::Error::Invalid)?
                                };
                                let amount = if form.kind == Kind::Dividend {
                                    money::parse(&form.price, false)
                                        .filter(|v| *v > 0)
                                        .ok_or(holdings::Error::Invalid)?
                                } else {
                                    0
                                };
                                Ok((
                                    security,
                                    Trade {
                                        id: trade_id.with(|v| v.clone()),
                                        security: security_id.with(|v| v.clone()),
                                        at: day.0.to_datetime(
                                            clock::zoned(clock::now_ms()).datetime().time(),
                                        ),
                                        kind: form.kind,
                                        quantity,
                                        price,
                                        amount,
                                        fee,
                                        cash: if form.kind == Kind::Opening {
                                            None
                                        } else {
                                            form.cash.clone()
                                        },
                                    },
                                ))
                            };
                            match build().and_then(|(sec, t)| {
                                finance::add_trade(new.then_some(&sec), &t)?;
                                Ok(sec)
                            }) {
                                Ok(sec) => {
                                    dismiss_keyboard();
                                    open.set(None);
                                    show_toast(s().trade_saved, None);
                                    if new {
                                        nav::push(Route::Holding(sec.id));
                                    }
                                }
                                Err(cause) => {
                                    log::error!("holdings: save failed: {cause}");
                                    error.set(Some(failure(&cause).into()));
                                }
                            }
                        }),
                );
            task_sheet(move || open.get().is_some(), close, header, body, action).into_element()
        })
    })
}

pub fn price_editor(
    open: Signal<bool>,
    security: impl Fn() -> Option<Security> + Copy + 'static,
) -> impl IntoElement {
    dynamic(move || {
        if !open.get() {
            return view().into_element();
        }
        untracked(move || {
            let Some(sec) = security() else {
                return view().into_element();
            };
            let value = signal(String::new());
            let day = signal(clock::today().to_string());
            let calendar = signal(false);
            let error = signal(None::<String>);
            let discard = guarded(
                move || !value.get_untracked().is_empty(),
                move || open.set(false),
            );
            let close = move || {
                if calendar.get_untracked() {
                    calendar.set(false);
                } else {
                    discard();
                }
            };
            let header = view()
                .flex_row()
                .items_center()
                .child(
                    text(|| s().update_price)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .flex_1(),
                )
                .child(
                    Btn::ghost()
                        .label(move || {
                            if calendar.get() {
                                s().back.into()
                            } else {
                                s().cancel.into()
                            }
                        })
                        .on_press(close),
                );
            let title = stored(sec.name.clone());
            let body = dynamic(move || {
                let show = calendar.get();
                untracked(move || {
                    if show {
                        return super::super::finance::date_picker(day, move || {
                            calendar.set(false)
                        })
                        .into_element();
                    }
                    view()
                        .gap_4()
                        .child(
                            text(title.with(|v| v.clone()))
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(decimal(value, || s().holding_price))
                        .child(
                            row_button(move || {
                                dismiss_keyboard();
                                calendar.set(true);
                            })
                            .accessibility_label(|| Some(s().price_date.into()))
                            .px_0()
                            .child(
                                text(|| s().price_date)
                                    .typo(Type::Body)
                                    .text_color(color::MUTED)
                                    .flex_1(),
                            )
                            .child(
                                text(move || {
                                    day.get()
                                        .parse::<Day>()
                                        .map(|d| s().short_date(d))
                                        .unwrap_or_default()
                                })
                                .typo(Type::Body)
                                .text_color(color::INK),
                            ),
                        )
                        .child(
                            text(|| s().holding_scope)
                                .typo(Type::Subhead)
                                .text_color(color::MUTED),
                        )
                        .into_element()
                })
            });
            let action = view()
                .gap_2()
                .child(note(move || error.get().map(Into::into), || true))
                .child(
                    Btn::primary()
                        .label(move || {
                            if calendar.get() {
                                s().done.into()
                            } else {
                                s().update_price.into()
                            }
                        })
                        .on_press(move || {
                            if calendar.get_untracked() {
                                calendar.set(false);
                                return;
                            }
                            let proposal = || -> Result<Quote, holdings::Error> {
                                Ok(Quote {
                                    security: sec.id.clone(),
                                    day: day
                                        .get_untracked()
                                        .parse::<Day>()
                                        .map_err(|_| holdings::Error::Invalid)?
                                        .0,
                                    price: holdings::parse_units(&value.get_untracked())
                                        .ok_or(holdings::Error::Invalid)?,
                                })
                            };
                            match proposal().and_then(|q| finance::set_quote(&q)) {
                                Ok(()) => {
                                    dismiss_keyboard();
                                    open.set(false);
                                    show_toast(s().price_saved, None);
                                }
                                Err(cause) => {
                                    log::error!("holdings: price failed: {cause}");
                                    error.set(Some(failure(&cause).into()));
                                }
                            }
                        }),
                );
            task_sheet(move || open.get(), close, header, body, action).into_element()
        })
    })
}
