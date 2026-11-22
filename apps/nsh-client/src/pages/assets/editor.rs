use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Type, Typo, color,
        field::{field, note, text_input},
        segmented::{Segment, segmented},
        sheet::{fitted_task_sheet, initial_focus, retained, task_sheet},
        surface::row_button,
        toast::show_toast,
    },
};
use navi_finance::{
    account::{Account, AccountKind},
    assets,
    currency::Currency,
    journal, money,
    repository::{BalanceCheck, Error},
};
use nsh_core::prelude::*;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn message(error: &Error) -> &'static str {
    match error {
        Error::AccountExists => s().account_exists,
        Error::BalanceChanged => s().balance_changed,
        Error::Invalid("recognition running") => s().rename_running,
        _ => s().error_transaction_storage,
    }
}

fn guarded_close(
    open: Signal<bool>,
    dirty: impl Fn() -> bool + Copy + 'static,
) -> impl Fn() + Copy {
    guarded(dirty, move || open.set(false))
}

/// Runs `close` at once when nothing changed; otherwise only after the owner
/// confirms discarding the edit.
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

pub fn account_editor(open: Signal<bool>, own: Option<Signal<Account>>) -> impl IntoElement {
    account_task(open, own, || {})
}

pub fn account_task(
    open: Signal<bool>,
    own: Option<Signal<Account>>,
    saved: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    retained(
        move || open.get().then_some(()),
        move |_| {
            crate::ui::toast::clear_notice();
            untracked(move || {
                let initial = own.map(|a| a.get());
                let name = signal(
                    initial
                        .as_ref()
                        .map(|a| a.name().to_owned())
                        .unwrap_or_default(),
                );
                let original = stored((
                    name.get(),
                    initial.as_ref().map_or(AccountKind::Assets, Account::kind),
                    initial.as_ref().map_or(Currency::CNY, Account::currency),
                ));
                let focus = initial_focus();
                let embedded = crate::ui::sheet::is_task_panel();
                let kind = signal(
                    initial
                        .as_ref()
                        .map(|a| a.kind())
                        .unwrap_or(AccountKind::Assets),
                );
                let currency = signal(initial.as_ref().map_or(Currency::CNY, Account::currency));
                let error = signal(None::<String>);
                let selector = signal(0u8);
                let dirty = move || {
                    (
                        name.get_untracked(),
                        kind.get_untracked(),
                        currency.get_untracked(),
                    ) != original.with(|v| v.clone())
                };
                let discard = guarded_close(open, dirty);
                // Swipe or backdrop leaves the whole task, not just this panel.
                crate::ui::sheet::task_dismiss(guarded(dirty, move || {
                    saved();
                    open.set(false);
                }));
                let close = move || {
                    if selector.get_untracked() != 0 {
                        selector.set(0);
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
                        text(if own.is_some() {
                            s().rename_account
                        } else {
                            s().add_account
                        })
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .flex_1(),
                    )
                    .child(
                        Btn::ghost()
                            .label(move || if embedded { s().back } else { s().cancel }.into())
                            .on_press(close),
                    );
                let body = view()
                    .gap_3()
                    .child(field(
                        || s().account_name,
                        text_input(name)
                            .label(|| s().account_name)
                            .element_ref(&focus),
                    ))
                    .child(own.is_none().then(|| {
                        view()
                            .gap_2()
                            .child(
                                view()
                                    .flex_row()
                                    .gap_3()
                                    .child(
                                        view().flex_1().min_w(px(0.0)).child(
                                            row_button(move || {
                                                dismiss_keyboard();
                                                selector.set(if selector.get_untracked() == 1 {
                                                    0
                                                } else {
                                                    1
                                                });
                                            })
                                            .accessibility_label(|| Some(s().account_type.into()))
                                            .px_0()
                                            .min_h(px(44.0))
                                            .child(
                                                text(move || {
                                                    if kind.get() == AccountKind::Liabilities {
                                                        s().liability_account
                                                    } else {
                                                        s().asset_account
                                                    }
                                                })
                                                .typo(Type::Subhead)
                                                .text_color(color::INK)
                                                .flex_1(),
                                            )
                                            .child(
                                                crate::ui::icon(
                                                    crate::ui::Icon::ChevronDown,
                                                    16.0,
                                                    color::MUTED,
                                                ),
                                            ),
                                        ),
                                    )
                                    .child(
                                        view().min_w(px(80.0)).child(
                                            row_button(move || {
                                                dismiss_keyboard();
                                                selector.set(if selector.get_untracked() == 2 {
                                                    0
                                                } else {
                                                    2
                                                });
                                            })
                                            .accessibility_label(|| Some(s().currency_label.into()))
                                            .px_0()
                                            .min_h(px(44.0))
                                            .child(
                                                text(move || currency.get().code())
                                                    .typo(Type::Subhead)
                                                    .text_color(color::INK),
                                            )
                                            .child(
                                                crate::ui::icon(
                                                    crate::ui::Icon::ChevronDown,
                                                    16.0,
                                                    color::MUTED,
                                                ),
                                            ),
                                        ),
                                    ),
                            )
                            .child(when(
                                move || selector.get() == 1,
                                move || {
                                    segmented(
                                        vec![
                                            Segment::new(AccountKind::Assets, || {
                                                s().asset_account.into()
                                            }),
                                            Segment::new(AccountKind::Liabilities, || {
                                                s().liability_account.into()
                                            }),
                                        ],
                                        move || kind.get(),
                                        move |k| {
                                            kind.set(k);
                                            selector.set(0);
                                        },
                                    )
                                },
                            ))
                            .child(when(
                                move || selector.get() == 2,
                                move || {
                                    segmented(
                                        Currency::ALL
                                            .into_iter()
                                            .map(|c| Segment::new(c, move || c.code().into()))
                                            .collect(),
                                        move || currency.get(),
                                        move |c| {
                                            currency.set(c);
                                            selector.set(0);
                                        },
                                    )
                                },
                            ))
                    }));
                let action = view()
                    .gap_2()
                    .child(note(move || error.get().map(Into::into), || true))
                    .child(
                        Btn::primary()
                            .label(move || {
                                if own.is_some() {
                                    s().save_account_name.into()
                                } else {
                                    s().create_account.into()
                                }
                            })
                            .on_press(move || {
                                let Ok(account) = Account::new_in(
                                    kind.get_untracked(),
                                    &name.get_untracked(),
                                    currency.get_untracked(),
                                ) else {
                                    error.set(Some(s().error_account.into()));
                                    return;
                                };
                                let result = if let Some(own) = own {
                                    finance::rename_account(&own.get_untracked(), &account)
                                } else {
                                    finance::create_account(account.clone())
                                };
                                match result {
                                    Err(cause) => {
                                        log::error!("assets: account write failed: {cause}");
                                        error.set(Some(message(&cause).into()));
                                    }
                                    Ok(()) => {
                                        if let Some(own) = own {
                                            own.set(account.clone());
                                        }
                                        dismiss_keyboard();
                                        // Close the host first: clearing this
                                        // panel while the host is open would
                                        // swap the menu in during the exit.
                                        saved();
                                        open.set(false);
                                        if own.is_some() {
                                            show_toast(s().account_renamed, None);
                                        } else {
                                            let route = account.to_string();
                                            crate::ui::toast::show_receipt(
                                                s().account_created,
                                                (
                                                    s().check_balance.into(),
                                                    std::rc::Rc::new(move || {
                                                        CHECK_CREATED.with(|v| {
                                                            *v.borrow_mut() = Some(route.clone())
                                                        });
                                                        nav::push(Route::Account(route.clone()));
                                                    }),
                                                ),
                                            );
                                        }
                                    }
                                }
                            }),
                    );
                fitted_task_sheet(move || open.get(), close, header, body, action).into_element()
            })
        },
    )
}

#[derive(Clone, PartialEq)]
struct Preview {
    day: Day,
    book: i64,
    actual: i64,
}

pub fn balance_editor(open: Signal<bool>, own: Signal<Account>) -> impl IntoElement {
    retained(
        move || open.get().then_some(()),
        move |_| {
            untracked(move || {
                let value = signal(String::new());
                let focus = initial_focus();
                let day = signal(clock::today().to_string());
                let date_panel = signal(false);
                let preview = signal(None::<Preview>);
                #[cfg(not(any(target_os = "android", target_os = "ios")))]
                if let Some(actual) = crate::preview::balance_value() {
                    value.set(money::format(actual));
                    let a = own.get_untracked();
                    preview.set(Some(Preview {
                        day: clock::today(),
                        book: journal::balance_on(&finance::transactions(), &a, clock::today().0),
                        actual,
                    }));
                }
                let error = signal(None::<String>);
                let discard = guarded_close(open, move || !value.get_untracked().trim().is_empty());
                let close = move || {
                    if date_panel.get_untracked() {
                        date_panel.set(false);
                    } else if preview.get_untracked().is_some() {
                        preview.set(None);
                    } else {
                        discard();
                    }
                };
                let header = view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text(|| s().check_balance)
                            .typo(Type::Title)
                            .text_color(color::INK)
                            .flex_1(),
                    )
                    .child(
                        Btn::ghost()
                            .label(move || {
                                if date_panel.get() || preview.get().is_some() {
                                    s().back.into()
                                } else {
                                    s().cancel.into()
                                }
                            })
                            .on_press(close),
                    );
                let body = dynamic(move || {
                    let selecting_date = date_panel.get();
                    let proposed = preview.get();
                    let a = own.get();
                    untracked(move || {
                        if selecting_date {
                            return super::super::finance::date_picker(day, move || {
                                date_panel.set(false)
                            })
                            .into_element();
                        }
                        let title = if a.kind() == AccountKind::Liabilities {
                            s().actual_debt
                        } else {
                            s().actual_balance
                        };
                        if let Some(p) = proposed {
                            let difference = p
                                .actual
                                .checked_sub(p.book)
                                .expect("preview checked exact difference");
                            return view()
                                .gap_4()
                                .child(
                                    text(crate::ui::currency::account_label(&a))
                                        .typo(Type::Headline)
                                        .text_color(color::INK),
                                )
                                .child(
                                    text(s().long_date(p.day))
                                        .typo(Type::Subhead)
                                        .text_color(color::MUTED),
                                )
                                .child(pair(
                                    if a.kind() == AccountKind::Liabilities {
                                        s().account_debt
                                    } else {
                                        s().account_balance
                                    },
                                    assets::displayed(&a, p.book),
                                    a.currency(),
                                ))
                                .child(pair(title, assets::displayed(&a, p.actual), a.currency()))
                                .child(pair(
                                    s().balance_difference,
                                    assets::displayed(&a, difference),
                                    a.currency(),
                                ))
                                .child(
                                    text(if difference == 0 {
                                        s().balance_equal
                                    } else {
                                        s().balance_explanation
                                    })
                                    .typo(Type::Body)
                                    .text_color(color::BODY),
                                )
                                .into_element();
                        }
                        view()
                            .gap_4()
                            .child(
                                text(crate::ui::currency::account_label(&a))
                                    .typo(Type::Headline)
                                    .text_color(color::INK),
                            )
                            // Default keyboard permits a leading minus for credit/overdrawn balances.
                            .child(field(
                                title,
                                text_input(value)
                                    .label(title)
                                    .placeholder("0.00")
                                    .element_ref(&focus)
                                    .tabular_nums(),
                            ))
                            .child((a.kind() == AccountKind::Liabilities).then(|| {
                                text(|| s().debt_hint)
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED)
                            }))
                            .child(
                                row_button(move || {
                                    dismiss_keyboard();
                                    date_panel.set(true);
                                })
                                .accessibility_label(|| Some(s().transaction_date.into()))
                                .py_2()
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
                                            .map(|d| s().long_date(d))
                                            .unwrap_or_default()
                                    })
                                    .typo(Type::Body)
                                    .text_color(color::INK),
                                ),
                            )
                            .child(
                                text(|| s().balance_date_hint)
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED),
                            )
                            .into_element()
                    })
                });
                let actions = view()
                    .gap_2()
                    .child(note(move || error.get().map(Into::into), || true))
                    .child(
                        Btn::primary()
                            .label(move || {
                                if date_panel.get() {
                                    s().done.into()
                                } else if preview.get().is_some() {
                                    s().balance_confirm.into()
                                } else {
                                    s().balance_preview.into()
                                }
                            })
                            .on_press(move || {
                                if date_panel.get_untracked() {
                                    date_panel.set(false);
                                    return;
                                }
                                error.set(None);
                                let a = own.get_untracked();
                                if let Some(p) = preview.get_untracked() {
                                    let check = BalanceCheck {
                                        id: format!(
                                            "balance:{}:{}",
                                            clock::now_ms(),
                                            NEXT.fetch_add(1, Ordering::Relaxed)
                                        ),
                                        account: a,
                                        day: p.day.0,
                                        actual: p.actual,
                                        checked_at: clock::zoned(clock::now_ms()).datetime(),
                                    };
                                    match finance::confirm_balance(check, p.book) {
                                        Ok(()) => {
                                            dismiss_keyboard();
                                            open.set(false);
                                            show_toast(s().balance_saved, None);
                                        }
                                        Err(cause) => {
                                            log::error!("assets: balance check failed: {cause}");
                                            if matches!(cause, Error::BalanceChanged) {
                                                preview.set(None);
                                            }
                                            error.set(Some(message(&cause).into()));
                                        }
                                    }
                                    return;
                                }
                                let Some(actual) = money::parse(&value.get_untracked(), true)
                                    .and_then(|v| assets::book_value(&a, v))
                                else {
                                    error.set(Some(s().error_money.into()));
                                    return;
                                };
                                let Ok(selected) = day.get_untracked().parse::<Day>() else {
                                    error.set(Some(s().error_transaction_date.into()));
                                    return;
                                };
                                if selected > clock::today() {
                                    error.set(Some(s().error_transaction_date.into()));
                                    return;
                                }
                                let book =
                                    journal::balance_on(&finance::transactions(), &a, selected.0);
                                if actual.checked_sub(book).is_none_or(|d| d == i64::MIN) {
                                    error.set(Some(s().error_money.into()));
                                    return;
                                }
                                dismiss_keyboard();
                                preview.set(Some(Preview {
                                    day: selected,
                                    book,
                                    actual,
                                }));
                            }),
                    );
                task_sheet(move || open.get(), close, header, body, actions).into_element()
            })
        },
    )
}

fn pair(label: &'static str, value: i64, currency: Currency) -> impl IntoElement {
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
        .child(super::amount_in(value, Type::Figure, currency))
}

thread_local! { static CHECK_CREATED: std::cell::RefCell<Option<String>> = const { std::cell::RefCell::new(None) }; }

pub(super) fn take_created_check(account: &str) -> bool {
    CHECK_CREATED.with(|v| {
        let mut next = v.borrow_mut();
        if next.as_deref() == Some(account) {
            next.take();
            true
        } else {
            false
        }
    })
}
