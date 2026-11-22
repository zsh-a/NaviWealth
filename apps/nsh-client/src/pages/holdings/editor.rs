use super::*;
use crate::i18n::catalog::copy;
use crate::ui::{
    field::{field, text_input},
    segmented::{Segment, segmented},
    sheet::{initial_focus, retained, task_sheet},
    surface::disclosure,
};
use navi_finance::{
    account::{Account, AccountKind},
    currency::Currency,
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
        crate::ui::feedback::confirm_discard(asking, close);
    }
}

/// Deleting a holding's last trade keeps its security, quotes and listing.
/// It can still be opened from the new-holding picker.
fn saved_securities(query: Signal<String>) -> Vec<(Security, Option<String>)> {
    let book = finance::holdings_snapshot();
    let traded: std::collections::HashSet<_> = book.trades.iter().map(|t| &t.security).collect();
    let mut unused = book
        .securities
        .iter()
        .filter(|s| !traded.contains(&s.id))
        .peekable();
    if unused.peek().is_none() {
        return Vec::new();
    }
    let bindings = catalog::bindings();
    let q = query.get().trim().to_lowercase();
    unused
        .filter_map(|sec| {
            let code = bindings
                .iter()
                .find(|b| b.security == sec.id)
                .map(|b| &b.symbol);
            (sec.name.to_lowercase().contains(&q)
                || code.is_some_and(|s| s.to_lowercase().contains(&q)))
            .then(|| (sec.clone(), code.cloned()))
        })
        .collect()
}

fn saved_security_rows(
    matches: Vec<(Security, Option<String>)>,
    dirty: impl Fn() -> bool + Copy + 'static,
    visit: impl Fn(String) + Copy + 'static,
) -> AnyElement {
    if matches.is_empty() {
        return view().into_element();
    }
    view()
        .child(super::super::assets::asset_group_title(|| {
            copy("Saved securities", "已保存的证券")
        }))
        .children(matches.into_iter().map(|(security, code)| {
            let id = stored(security.id);
            row_button(guarded(dirty, move || visit(id.get())))
                .px_0()
                .child(
                    text(security.name)
                        .typo(Type::Body)
                        .text_color(color::INK)
                        .min_w(px(0.0))
                        .flex_1(),
                )
                .child(code.map(|code| text(code).typo(Type::Caption).text_color(color::MUTED)))
                .child(crate::ui::icon(Icon::ChevronRight, 16.0, color::MUTED))
        }))
        .into_element()
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
    NewCash,
    Security,
}
#[derive(Clone, PartialEq)]
struct Values {
    kind: Kind,
    currency: Currency,
    name: String,
    quantity: String,
    price: String,
    dividend: String,
    fee: String,
    cash: Option<Account>,
    day: String,
}

struct TradeAmounts {
    quantity: i64,
    price: i64,
    amount: i64,
    fee: i64,
}

impl TradeAmounts {
    fn parse(
        kind: Kind,
        quantity: &str,
        price: &str,
        dividend: &str,
        fee: &str,
    ) -> Result<Self, &'static str> {
        let (quantity, price, amount) = if kind == Kind::Dividend {
            let amount = money::parse(dividend, false)
                .filter(|v| *v > 0)
                .ok_or_else(|| copy("Enter a positive dividend amount.", "分红金额须大于零。"))?;
            (0, 0, amount)
        } else {
            let units = |s: &str| holdings::parse_units(s).filter(|v| *v > 0);
            let (Some(quantity), Some(price)) = (units(quantity), units(price)) else {
                return Err(copy(
                    "Enter a positive quantity and price per unit.",
                    "数量和单价须大于零，最多保留六位小数。",
                ));
            };
            (quantity, price, 0)
        };
        let fee = if kind == Kind::Opening || fee.trim().is_empty() {
            0
        } else {
            money::parse(fee, false).ok_or_else(|| {
                copy(
                    "Enter a nonnegative fee with up to two decimal places.",
                    "手续费须为非负数，最多保留两位小数。",
                )
            })?
        };
        Ok(Self {
            quantity,
            price,
            amount,
            fee,
        })
    }
}

fn cash_preview(
    kind: Signal<Kind>,
    currency: Signal<Currency>,
    quantity: Signal<String>,
    price: Signal<String>,
    dividend: Signal<String>,
    fee: Signal<String>,
    cash: Signal<Option<Account>>,
) -> impl IntoElement {
    dynamic(move || {
        let kind = kind.get();
        let currency = currency.get();
        let direction = if kind == Kind::Buy {
            copy("Cash out", "将扣款")
        } else {
            copy("Cash in", "将入账")
        };
        let amount_pending = if kind == Kind::Dividend {
            dividend.get().trim().is_empty()
        } else {
            quantity.get().trim().is_empty() || price.get().trim().is_empty()
        };
        if amount_pending {
            return pair(direction, "—").into_element();
        }
        let preview = TradeAmounts::parse(
            kind,
            &quantity.get(),
            &price.get(),
            &dividend.get(),
            &fee.get(),
        )
        .and_then(|v| {
            kind.settlement(v.quantity, v.price, v.amount, v.fee)
                .map(|total| (total, v.fee))
                .map_err(|error| match (error, kind) {
                    (holdings::Error::Invalid, Kind::Dividend) => copy(
                        "The dividend must exceed the fee.",
                        "分红金额须大于手续费。",
                    ),
                    (holdings::Error::Invalid, Kind::Sell) => copy(
                        "The fee exceeds the sale proceeds.",
                        "手续费已超过卖出金额。",
                    ),
                    _ => copy(
                        "Check the quantity, price and fee.",
                        "请检查数量、单价和手续费。",
                    ),
                })
        });
        match preview {
            Err(hint) => text(hint)
                .typo(Type::Subhead)
                .text_color(color::MUTED)
                .into_element(),
            Ok((total, fee)) => {
                let signed = if kind == Kind::Buy { -total } else { total };
                let label = cash.get().map_or_else(
                    || copy("Choose a cash account", "请选择现金账户").to_owned(),
                    |account| format!("{} · {direction}", account.name()),
                );
                let mut row = view().gap_1().child(
                    view()
                        .w_full()
                        .min_w(px(0.0))
                        .flex_row()
                        .flex_wrap()
                        .items_baseline()
                        .justify_between()
                        .gap_x(px(12.0))
                        .gap_y(px(2.0))
                        .child(
                            text(label)
                                .min_w(px(0.0))
                                .max_w(relative(1.0))
                                .typo(Type::Body)
                                .text_color(color::MUTED),
                        )
                        .child(
                            text(crate::ui::currency::signed(signed, currency))
                                .min_w(px(0.0))
                                .max_w(relative(1.0))
                                .typo(Type::Headline)
                                .tabular_nums()
                                .text_color(color::INK),
                        ),
                );
                if fee > 0 {
                    row = row.child(
                        text(format!(
                            "{} {}",
                            copy("Includes fee of", "已计入手续费"),
                            crate::ui::currency::format(fee, currency),
                        ))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                    );
                }
                row.into_element()
            }
        }
    })
}

fn cash_accounts(currency: Currency) -> Vec<Account> {
    finance::accounts()
        .into_iter()
        .filter(|a| a.is_cash() && a.kind() == AccountKind::Assets && a.currency() == currency)
        .collect()
}

fn only_cash_account(currency: Currency) -> Option<Account> {
    match cash_accounts(currency).as_slice() {
        [only] => Some(only.clone()),
        _ => None,
    }
}

fn new_cash_label(currency: Currency) -> &'static str {
    match currency {
        Currency::CNY => copy("New CNY cash account", "新建人民币现金账户"),
        Currency::HKD => copy("New HKD cash account", "新建港元现金账户"),
        Currency::USD => copy("New USD cash account", "新建美元现金账户"),
    }
}

fn create_cash_account(name: &str, currency: Currency) -> Result<Account, &'static str> {
    let account = Account::new_in(AccountKind::Assets, name, currency)
        .ok()
        .filter(Account::is_cash)
        .ok_or_else(|| s().error_account)?;
    finance::create_account(account.clone()).map_err(|error| {
        log::debug!("holdings: creating cash account: {error}");
        match error {
            navi_finance::repository::Error::AccountExists => s().account_exists,
            _ => s().error_transaction_storage,
        }
    })?;
    Ok(account)
}

pub fn trade_editor(open: Signal<Option<String>>) -> impl IntoElement {
    trade_task(open, || {})
}

pub fn trade_task(
    open: Signal<Option<String>>,
    saved: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    retained(
        move || open.get(),
        move |chosen| {
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
                let currency = signal(
                    existing
                        .as_ref()
                        .map(Security::currency)
                        .unwrap_or(Currency::CNY),
                );
                let listing = signal(None::<navi_finance::catalog::Entry>);
                let embedded = crate::ui::sheet::is_task_panel();
                let search = crate::pages::security_picker::Search::new();
                let manual = signal(false);
                let quantity = signal(String::new());
                let price = signal(String::new());
                let dividend = signal(String::new());
                let fee = signal(String::new());
                let cash = signal(only_cash_account(currency.get_untracked()));
                let new_cash_name = signal(String::new());
                let set_currency = move |c| {
                    if currency.get_untracked() != c {
                        currency.set(c);
                        cash.set(only_cash_account(c));
                        new_cash_name.set(String::new());
                    }
                };
                let day = signal(clock::today().to_string());
                let details = signal(false);
                let panel = signal(if new { Panel::Security } else { Panel::Main });
                crate::ui::sheet::reserve_keyboard_when(move || {
                    matches!(panel.get(), Panel::Security | Panel::NewCash)
                });
                let error = signal(None::<String>);
                let open_cash = move || {
                    error.set(None);
                    dismiss_keyboard();
                    panel.set(if cash_accounts(currency.get_untracked()).is_empty() {
                        Panel::NewCash
                    } else {
                        Panel::Cash
                    });
                };
                let values = move || Values {
                    kind: kind.get_untracked(),
                    currency: currency.get_untracked(),
                    name: name.get_untracked(),
                    quantity: quantity.get_untracked(),
                    price: price.get_untracked(),
                    dividend: dividend.get_untracked(),
                    fee: fee.get_untracked(),
                    cash: cash.get_untracked(),
                    day: day.get_untracked(),
                };
                let initial = stored(values());
                let dirty = move || {
                    initial.with(|v| v != &values()) || !new_cash_name.get_untracked().is_empty()
                };
                let discard = guarded(dirty, move || open.set(None));
                // Swipe or backdrop leaves the whole task, not just this panel.
                crate::ui::sheet::task_dismiss(guarded(dirty, move || {
                    saved();
                    open.set(None);
                }));
                let close = move || {
                    if panel.get_untracked() == Panel::Security
                        && name.get_untracked().is_empty()
                        && quantity.get_untracked().is_empty()
                        && price.get_untracked().is_empty()
                        && !manual.get_untracked()
                    {
                        discard();
                    } else if panel.get_untracked() != Panel::Main {
                        let back = if panel.get_untracked() == Panel::NewCash
                            && !cash_accounts(currency.get_untracked()).is_empty()
                        {
                            Panel::Cash
                        } else {
                            Panel::Main
                        };
                        error.set(None);
                        panel.set(back);
                        dismiss_keyboard();
                    } else {
                        discard();
                    }
                };
                let heading = view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text(move || match panel.get() {
                            Panel::Cash => s().cash_account,
                            Panel::NewCash => new_cash_label(currency.get()),
                            _ if new => s().add_holding,
                            _ => s().record_trade,
                        })
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .flex_1(),
                    )
                    .child(
                        Btn::ghost()
                            .label(move || {
                                if panel.get() != Panel::Main || embedded {
                                    s().back.into()
                                } else {
                                    s().cancel.into()
                                }
                            })
                            .on_press(close),
                    );
                let header = view().gap_3().child(heading).child(when(
                    move || panel.get() == Panel::Security,
                    move || search.input(),
                ));
                let body = dynamic(move || {
                    let current_panel = panel.get();
                    let current_kind = kind.get();
                    let current_currency = currency.get();
                    untracked(move || {
                        if current_panel == Panel::Security {
                            let local = computed(move || saved_securities(search.query));
                            let catalog_results = search.results(
                                move || !local.with(Vec::is_empty),
                                move |entry| {
                                    if let Some(c) = Currency::parse(&entry.currency) {
                                        set_currency(c);
                                    }
                                    name.set(entry.name().to_owned());
                                    listing.set(Some(entry));
                                    manual.set(false);
                                    dismiss_keyboard();
                                    panel.set(Panel::Main);
                                },
                            );
                            return view()
                                .child(dynamic(move || {
                                    saved_security_rows(local.get(), dirty, move |id| {
                                        saved();
                                        open.set(None);
                                        nav::push(Route::Holding(id));
                                    })
                                }))
                                .child(catalog_results)
                                .into_element();
                        }
                        if current_panel == Panel::Date {
                            return super::super::finance::date_picker(day, move || {
                                panel.set(Panel::Main)
                            })
                            .into_element();
                        }
                        if current_panel == Panel::Cash {
                            return view()
                                .children(cash_accounts(current_currency).into_iter().map(
                                    move |a| {
                                        let selected = cash.get_untracked().as_ref() == Some(&a);
                                        let label = a.name().to_owned();
                                        row_button(move || {
                                            cash.set(Some(a.clone()));
                                            panel.set(Panel::Main);
                                        })
                                        .px_0()
                                        .selected(move || selected)
                                        .child(
                                            text(label)
                                                .typo(Type::Body)
                                                .text_color(color::INK)
                                                .flex_1(),
                                        )
                                        .child(
                                            selected.then(|| {
                                                crate::ui::icon(Icon::Check, 18.0, color::INK)
                                            }),
                                        )
                                    },
                                ))
                                .into_element();
                        }
                        if current_panel == Panel::NewCash {
                            return view()
                                .gap_2()
                                .child(field(
                                    || s().account_name,
                                    text_input(new_cash_name)
                                        .label(|| s().account_name)
                                        .on_change(move |value: &str| {
                                            new_cash_name.set(value.to_owned());
                                            error.set(None);
                                        })
                                        .element_ref(&initial_focus()),
                                ))
                                .child(note(move || error.get().map(Into::into), || true))
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
                                view()
                                    .gap_2()
                                    .child(
                                        row_button(move || {
                                            dismiss_keyboard();
                                            panel.set(Panel::Security);
                                        })
                                        .accessibility_label(|| {
                                            Some(crate::i18n::catalog::choose().into())
                                        })
                                        .px_0()
                                        .min_h(px(56.0))
                                        .child(
                                            view()
                                                .flex_1()
                                                .min_w(px(0.0))
                                                .gap_1()
                                                .child(
                                                    text(move || {
                                                        if name.get().is_empty() {
                                                            s().security_name.to_owned()
                                                        } else {
                                                            name.get()
                                                        }
                                                    })
                                                    .typo(Type::Headline)
                                                    .text_color(color::INK),
                                                )
                                                .child(
                                                    text(move || {
                                                        listing.get().map_or_else(
                                                            || {
                                                                crate::i18n::catalog::search()
                                                                    .to_owned()
                                                            },
                                                            |entry| {
                                                                format!(
                                                                    "{} · {} · {}",
                                                                    crate::i18n::catalog::market(
                                                                        &entry.market
                                                                    ),
                                                                    entry.symbol,
                                                                    entry.currency,
                                                                )
                                                            },
                                                        )
                                                    })
                                                    .typo(Type::Caption)
                                                    .text_color(color::MUTED),
                                                ),
                                        )
                                        .child(
                                            crate::ui::icon(Icon::ChevronRight, 20.0, color::MUTED),
                                        ),
                                    )
                                    .child(when(
                                        move || manual.get(),
                                        move || {
                                            view()
                                                .gap_3()
                                                .child(field(
                                                    || s().security_name,
                                                    text_input(name)
                                                        .label(|| s().security_name)
                                                        .placeholder(|| s().security_hint),
                                                ))
                                                .child(segmented(
                                                    [Currency::CNY, Currency::HKD, Currency::USD]
                                                        .into_iter()
                                                        .map(|c| {
                                                            Segment::new(c, move || {
                                                                c.to_string().into()
                                                            })
                                                        })
                                                        .collect(),
                                                    move || currency.get(),
                                                    move |c| {
                                                        set_currency(c);
                                                        listing.set(None);
                                                    },
                                                ))
                                        },
                                    ))
                                    .child(when(
                                        move || !manual.get() && listing.get().is_none(),
                                        move || {
                                            Btn::ghost()
                                                .size(crate::ui::Size::Small)
                                                .label(|| crate::i18n::catalog::manual().into())
                                                .on_press(move || {
                                                    manual.set(true);
                                                    listing.set(None);
                                                })
                                        },
                                    ))
                                    .into_element()
                            } else {
                                text(move || format!("{} · {}", name.get(), current_currency))
                                    .typo(Type::Headline)
                                    .text_color(color::INK)
                                    .into_element()
                            })
                            .child(if current_kind == Kind::Dividend {
                                decimal(dividend, || s().dividend_amount).into_element()
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
                                row_button(open_cash)
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
                            .child((current_kind == Kind::Opening).then(|| {
                                text(s().opening_hint)
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED)
                            }))
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
                                            .accessibility_label(|| {
                                                Some(s().transaction_date.into())
                                            })
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
                            .into_element()
                    })
                });
                let trade_action = move || {
                    view()
                        .gap_2()
                        .child(note(move || error.get().map(Into::into), || true))
                        .child(when(
                            move || panel.get() == Panel::Main && kind.get() != Kind::Opening,
                            move || {
                                cash_preview(kind, currency, quantity, price, dividend, fee, cash)
                            },
                        ))
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
                                .disabled(move || {
                                    panel.get() == Panel::Main
                                        && (name.get().trim().is_empty()
                                            || if kind.get() == Kind::Dividend {
                                                dividend.get().trim().is_empty()
                                            } else {
                                                quantity.get().trim().is_empty()
                                                    || price.get().trim().is_empty()
                                            })
                                })
                                .on_press(move || {
                                    if panel.get_untracked() != Panel::Main {
                                        panel.set(Panel::Main);
                                        return;
                                    }
                                    let form = values();
                                    let build = || -> Result<(Security, Trade), holdings::Error> {
                                        let security = Security::new_in(
                                            &security_id.with(|v| v.clone()),
                                            &form.name,
                                            form.currency,
                                        )?;
                                        let day = form
                                            .day
                                            .parse::<Day>()
                                            .map_err(|_| holdings::Error::Invalid)?;
                                        let v = TradeAmounts::parse(
                                            form.kind,
                                            &form.quantity,
                                            &form.price,
                                            &form.dividend,
                                            &form.fee,
                                        )
                                        .map_err(|_| holdings::Error::Invalid)?;
                                        Ok((
                                            security,
                                            Trade {
                                                id: trade_id.with(|v| v.clone()),
                                                security: security_id.with(|v| v.clone()),
                                                at: day.0.to_datetime(
                                                    clock::zoned(clock::now_ms()).datetime().time(),
                                                ),
                                                kind: form.kind,
                                                quantity: v.quantity,
                                                price: v.price,
                                                amount: v.amount,
                                                fee: v.fee,
                                                cash: if form.kind == Kind::Opening {
                                                    None
                                                } else {
                                                    form.cash.clone()
                                                },
                                            },
                                        ))
                                    };
                                    match build().and_then(|(sec, t)| {
                                        let binding =
                                            listing.get_untracked().map(|e| e.binding(&sec.id));
                                        finance::add_trade_bound(
                                            new.then_some(&sec),
                                            &t,
                                            binding.as_ref(),
                                        )?;
                                        Ok(sec)
                                    }) {
                                        Ok(sec) => {
                                            dismiss_keyboard();
                                            // Close the host first so the menu is
                                            // never swapped in during the exit.
                                            saved();
                                            open.set(None);
                                            show_toast(s().trade_saved, None);
                                            if new {
                                                nav::push(Route::Holding(sec.id));
                                            }
                                        }
                                        Err(holdings::Error::Cash) => open_cash(),
                                        Err(cause) => {
                                            log::error!("holdings: save failed: {cause}");
                                            error.set(Some(failure(&cause).into()));
                                        }
                                    }
                                }),
                        )
                };
                let action = dynamic(move || match panel.get() {
                    Panel::Security => crate::pages::security_picker::search_actions(move || {
                        manual.set(true);
                        listing.set(None);
                        dismiss_keyboard();
                        panel.set(Panel::Main);
                    })
                    .into_element(),
                    Panel::Cash => Btn::secondary()
                        .icon(Icon::Plus)
                        .label(move || new_cash_label(currency.get()).into())
                        .on_press(move || panel.set(Panel::NewCash))
                        .into_element(),
                    Panel::NewCash => Btn::primary()
                        .label(|| s().create_account.into())
                        .disabled(move || new_cash_name.get().trim().is_empty())
                        .on_press(move || {
                            match create_cash_account(
                                &new_cash_name.get_untracked(),
                                currency.get_untracked(),
                            ) {
                                Ok(account) => {
                                    cash.set(Some(account));
                                    new_cash_name.set(String::new());
                                    error.set(None);
                                    dismiss_keyboard();
                                    panel.set(Panel::Main);
                                }
                                Err(message) => error.set(Some(message.to_owned())),
                            }
                        })
                        .into_element(),
                    Panel::Main | Panel::Date => trade_action().into_element(),
                });
                task_sheet(move || open.get().is_some(), close, header, body, action).into_element()
            })
        },
    )
}

pub fn price_editor(
    open: Signal<bool>,
    security: impl Fn() -> Option<Security> + Copy + 'static,
) -> impl IntoElement {
    retained(
        move || open.get().then_some(()),
        move |_| {
            untracked(move || {
                let Some(sec) = security() else {
                    return view().into_element();
                };
                let value = signal(String::new());
                let focus = initial_focus();
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
                let title = stored(format!("{} · {}", sec.name, sec.currency()));
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
                            .child(field(
                                || s().holding_price,
                                text_input(value)
                                    .element_ref(&focus)
                                    .keyboard_type(KeyboardType::Decimal)
                                    .label(|| s().holding_price)
                                    .placeholder("0")
                                    .tabular_nums(),
                            ))
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
        },
    )
}
