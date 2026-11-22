use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::{catalog::copy, s},
    ui::{
        Btn, Type, Typo, account_purpose, color,
        field::{field, note, text_input},
        segmented::{Segment, segmented},
        sheet::{fitted_task_sheet, initial_focus, retained, task_sheet},
        surface::row_button,
        toast::show_toast,
    },
};
use navi_finance::{
    account::{Account, AccountKind, AccountPurpose},
    assets,
    currency::Currency,
    journal, money,
    repository::{BalanceCheck, Error},
};
use nsh_core::prelude::*;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn balance_check(account: Account, day: Day, actual: i64) -> BalanceCheck {
    let now = clock::now_ms();
    BalanceCheck {
        id: format!("balance:{now}:{}", NEXT.fetch_add(1, Ordering::Relaxed)),
        account,
        day: day.0,
        actual,
        checked_at: clock::zoned(now).datetime(),
    }
}

pub(super) fn opening_date(account: &Account) -> Option<Day> {
    navi_finance::repository::opening::latest_day(
        account,
        &finance::transactions_snapshot(),
        &finance::checks_snapshot(),
        clock::today().0,
    )
    .map(Day)
}

fn book_amount(account: &Account, value: &str) -> Option<i64> {
    money::parse(value, true)
        .and_then(|v| assets::book_value(account, v))
        .filter(|&v| v != i64::MIN)
}

fn amount_error() -> &'static str {
    copy(
        "Enter a balance with up to two decimal places.",
        "请输入余额，最多保留两位小数。",
    )
}

fn date_row(
    day: Signal<String>,
    label: &'static str,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    let value = move || {
        day.get()
            .parse::<Day>()
            .map(|d| s().axis_date(d, true))
            .unwrap_or_default()
    };
    account_value_row(move || label, value, press)
}

fn account_value_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    value: impl Fn() -> String + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .accessibility_label(move || Some(format!("{}, {}", label(), value()).into()))
        .px_0()
        .min_h(px(48.0))
        .child(text(label).typo(Type::Body).text_color(color::INK).flex_1())
        .child(text(value).typo(Type::Body).text_color(color::INK))
        .child(crate::ui::icon(
            crate::ui::Icon::ChevronRight,
            16.0,
            color::MUTED,
        ))
}

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

#[derive(Clone, Copy, PartialEq)]
enum AccountPanel {
    Details,
    Purpose,
    Currency,
    Opening,
    Date,
}

impl AccountPanel {
    fn editing_opening(self) -> bool {
        matches!(self, Self::Opening | Self::Date)
    }
}

pub fn account_editor(open: Signal<bool>, own: Option<Signal<Account>>) -> impl IntoElement {
    account_task(open, own, signal(true), || {})
}

pub fn account_task(
    open: Signal<bool>,
    own: Option<Signal<Account>>,
    typing: Signal<bool>,
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
                let existing_kind = initial.as_ref().map(Account::kind);
                let original_purpose = initial
                    .as_ref()
                    .map_or(Some(AccountPurpose::Bank), finance::account_purpose);
                let purpose = signal(original_purpose);
                let original_currency = initial.as_ref().map_or(Currency::CNY, Account::currency);
                let original_name = stored(name.get());
                let currency = signal(original_currency);
                let kind = computed(move || {
                    purpose
                        .get()
                        .map(AccountPurpose::kind)
                        .or(existing_kind)
                        .unwrap_or(AccountKind::Assets)
                });
                let purpose_label = move || match own {
                    Some(own) => account_purpose::description(&own.get(), purpose.get()),
                    None => account_purpose::label(purpose.get().unwrap_or(AccountPurpose::Bank)),
                };
                let focus = initial_focus();
                let embedded = crate::ui::sheet::is_task_panel();
                let opening_amount = signal(String::new());
                let day = signal(clock::today().to_string());
                let error = signal(None::<String>);
                use AccountPanel::{Currency as CurrencyPanel, Date, Details, Opening, Purpose};
                let selector = signal(Details);
                effect(move || typing.set(!matches!(selector.get(), Purpose | Date)));
                crate::ui::sheet::reserve_keyboard_when(move || typing.get());
                let opening_label = move || {
                    if kind.get() == AccountKind::Liabilities {
                        copy("Opening debt", "起始欠款")
                    } else {
                        copy("Opening balance", "起始余额")
                    }
                };
                let dirty = move || {
                    original_name.with(|saved| saved != name.get_untracked().trim())
                        || purpose.get_untracked() != original_purpose
                        || currency.get_untracked() != original_currency
                        || !opening_amount.get_untracked().trim().is_empty()
                };
                let discard = guarded_close(open, dirty);
                // Swipe or backdrop leaves the whole task, not just this panel.
                crate::ui::sheet::task_dismiss(guarded(dirty, move || {
                    saved();
                    open.set(false);
                }));
                let close = move || {
                    if selector.get_untracked() != Details {
                        let next = if selector.get_untracked() == Date {
                            Opening
                        } else {
                            Details
                        };
                        selector.set(next);
                        error.set(None);
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
                        text(move || match selector.get() {
                            Purpose => s().account_type,
                            Opening => opening_label(),
                            Date => copy("As of date", "截至日期"),
                            _ if own.is_some() => s().edit_account,
                            _ => s().add_account,
                        })
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .flex_1(),
                    )
                    .child(
                        Btn::ghost()
                            .label(move || {
                                if embedded || !matches!(selector.get(), Details | CurrencyPanel) {
                                    s().back
                                } else {
                                    s().cancel
                                }
                                .into()
                            })
                            .on_press(close),
                    );
                let compact =
                    move || own.is_none() && window().height.0 <= 700.0 && font_scale() <= 1.1;
                let body = view()
                    .gap_3()
                    .style_when(compact, |s| s.gap_1())
                    .child(
                        field(
                            || s().account_name,
                            text_input(name)
                                .label(|| s().account_name)
                                .element_ref(&focus)
                                .style_when(compact, |s| s.flex_1().min_w(px(0.0))),
                        )
                        .style_when(compact, |s| s.flex_row().items_center().gap_3()),
                    )
                    .child(
                        view()
                            .gap_1()
                            .child(
                                view()
                                    .flex_row()
                                    .items_center()
                                    .gap_3()
                                    .child(
                                        row_button(move || {
                                            dismiss_keyboard();
                                            error.set(None);
                                            selector.set(Purpose);
                                        })
                                        .px_0()
                                        .min_h(px(48.0))
                                        .flex_1()
                                        .min_w(px(0.0))
                                        .accessibility_label(move || {
                                            Some(
                                                format!(
                                                    "{}, {}",
                                                    s().account_type,
                                                    purpose_label()
                                                )
                                                .into(),
                                            )
                                        })
                                        .child(
                                            text(purpose_label)
                                                .typo(Type::Body)
                                                .text_color(color::INK)
                                                .flex_1(),
                                        )
                                        .child(
                                            crate::ui::icon(
                                                crate::ui::Icon::ChevronRight,
                                                16.0,
                                                color::MUTED,
                                            ),
                                        ),
                                    )
                                    .child(if own.is_none() {
                                        row_button(move || {
                                            dismiss_keyboard();
                                            selector.set(
                                                if selector.get_untracked() == CurrencyPanel {
                                                    Details
                                                } else {
                                                    CurrencyPanel
                                                },
                                            );
                                        })
                                        .accessibility_label(|| Some(s().currency_label.into()))
                                        .px_0()
                                        .min_h(px(48.0))
                                        .min_w(px(80.0))
                                        .child(
                                            text(move || currency.get().code())
                                                .typo(Type::Subhead)
                                                .text_color(color::INK),
                                        )
                                        .child(crate::ui::icon(
                                            crate::ui::Icon::ChevronDown,
                                            16.0,
                                            color::MUTED,
                                        ))
                                        .into_element()
                                    } else {
                                        text(original_currency.code())
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED)
                                            .into_element()
                                    }),
                            )
                            .child(when(
                                move || selector.get() == CurrencyPanel,
                                move || {
                                    segmented(
                                        Currency::ALL
                                            .into_iter()
                                            .map(|c| Segment::new(c, move || c.code().into()))
                                            .collect(),
                                        move || currency.get(),
                                        move |c| {
                                            currency.set(c);
                                            selector.set(Details);
                                        },
                                    )
                                },
                            ))
                            .child(own.is_none().then(|| {
                                account_value_row(
                                    opening_label,
                                    move || {
                                        let input = opening_amount.get();
                                        if input.trim().is_empty() {
                                            copy("Optional", "选填").into()
                                        } else {
                                            money::parse(&input, true)
                                                .map(|v| {
                                                    crate::ui::currency::format(v, currency.get())
                                                })
                                                .unwrap_or(input)
                                        }
                                    },
                                    move || {
                                        error.set(None);
                                        dismiss_keyboard();
                                        selector.set(Opening);
                                    },
                                )
                            })),
                    )
                    .child(own.map(|own| {
                        when(
                            move || {
                                name.get().trim() == own.get().name()
                                    && purpose.get() == original_purpose
                            },
                            move || super::lifecycle::account_action(own, move || open.set(false)),
                        )
                    }))
                    .style_when(
                        move || !matches!(selector.get(), Details | CurrencyPanel),
                        |s| s.hidden(),
                    );
                let body = view()
                    .child(body)
                    .child(when(
                        move || selector.get() == Purpose,
                        move || {
                            account_purpose::picker(
                                purpose.get_untracked(),
                                existing_kind,
                                move |selected| {
                                    purpose.set(Some(selected));
                                    selector.set(Details);
                                },
                            )
                        },
                    ))
                    .child(when(
                        move || selector.get().editing_opening(),
                        move || {
                            view()
                                .style_when(move || selector.get() == Date, |s| s.hidden())
                                .gap_3()
                                .child(field(
                                    move || {
                                        format!("{} · {}", s().money_amount, currency.get().code())
                                    },
                                    text_input(opening_amount)
                                        .label(opening_label)
                                        .element_ref(&initial_focus())
                                        .placeholder("0.00")
                                        .tabular_nums(),
                                ))
                                .child(date_row(
                                    day,
                                    copy("As of date", "截至日期"),
                                    move || {
                                        dismiss_keyboard();
                                        selector.set(Date);
                                    },
                                ))
                        },
                    ))
                    .child(when(
                        move || selector.get() == Date,
                        move || {
                            super::super::finance::date_picker_through(
                                day,
                                Some(clock::today()),
                                move || selector.set(Opening),
                            )
                        },
                    ));
                let action = view()
                    .style_when(move || selector.get() == Purpose, |s| s.hidden())
                    .gap_2()
                    .child(note(move || error.get().map(Into::into), || true))
                    .child(
                        Btn::primary()
                            .label(move || {
                                if selector.get().editing_opening() {
                                    s().done.into()
                                } else if own.is_some() {
                                    s().save_account_changes.into()
                                } else {
                                    s().create_account.into()
                                }
                            })
                            .disabled(move || {
                                let name = name.get();
                                let name = name.trim();
                                !selector.get().editing_opening()
                                    && (name.is_empty()
                                        || own.is_some_and(|a| {
                                            a.get().name() == name
                                                && purpose.get() == original_purpose
                                        }))
                            })
                            .on_press(move || {
                                match selector.get_untracked() {
                                    Date => {
                                        selector.set(Opening);
                                        return;
                                    }
                                    Opening => {
                                        let input = opening_amount.get_untracked();
                                        if !input.trim().is_empty()
                                            && money::parse(&input, true)
                                                .is_none_or(|v| v == i64::MIN)
                                        {
                                            error.set(Some(amount_error().into()));
                                            return;
                                        }
                                        close();
                                        return;
                                    }
                                    _ => {}
                                }
                                let Ok(account) = Account::new_in(
                                    kind.get_untracked(),
                                    &name.get_untracked(),
                                    currency.get_untracked(),
                                ) else {
                                    error.set(Some(s().error_account.into()));
                                    return;
                                };
                                let selected = purpose.get_untracked();
                                let new_purpose = selected.unwrap_or(AccountPurpose::Bank);
                                let result = if let Some(own) = own {
                                    finance::edit_account(&own.get_untracked(), &account, selected)
                                } else if !opening_amount.get_untracked().trim().is_empty() {
                                    let Some(actual) =
                                        book_amount(&account, &opening_amount.get_untracked())
                                    else {
                                        error.set(Some(amount_error().into()));
                                        selector.set(Opening);
                                        return;
                                    };
                                    let Ok(as_of) = day.get_untracked().parse::<Day>() else {
                                        error.set(Some(s().error_transaction_date.into()));
                                        return;
                                    };
                                    finance::create_account_with_opening_and_purpose(
                                        balance_check(account.clone(), as_of, actual),
                                        new_purpose,
                                    )
                                } else {
                                    finance::create_account_with_purpose(
                                        account.clone(),
                                        new_purpose,
                                    )
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
                                            show_toast(s().account_updated, None);
                                        } else {
                                            show_toast(s().account_created, None);
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

pub fn balance_editor(
    open: Signal<bool>,
    own: Signal<Account>,
    opening: Signal<bool>,
) -> impl IntoElement {
    retained(
        move || open.get().then_some(()),
        move |_| {
            untracked(move || {
                let value = signal(String::new());
                let focus = initial_focus();
                let today = clock::today();
                let latest = if opening.get_untracked() {
                    opening_date(&own.get_untracked()).unwrap_or(today)
                } else {
                    today
                };
                let day = signal(latest.to_string());
                let date_panel = signal(false);
                let preview = signal(None::<Preview>);
                #[cfg(not(any(target_os = "android", target_os = "ios")))]
                if let Some(actual) = crate::preview::balance_value() {
                    value.set(money::format(actual));
                    let a = own.get_untracked();
                    preview.set(Some(Preview {
                        day: latest,
                        book: journal::balance_on(&finance::transactions(), &a, latest.0),
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
                        text(move || {
                            if opening.get() {
                                s().opening_balance
                            } else {
                                s().check_balance
                            }
                        })
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
                            return super::super::finance::date_picker_through(
                                day,
                                Some(latest),
                                move || date_panel.set(false),
                            )
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
                                    text(s().axis_date(p.day, true))
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
                            .child(date_row(day, s().transaction_date, move || {
                                dismiss_keyboard();
                                date_panel.set(true);
                            }))
                            .child(
                                text(if opening.get_untracked() && latest < today {
                                    copy(
                                        "Use the balance before the first transaction.",
                                        "填写首笔流水之前的日终余额。",
                                    )
                                } else {
                                    s().balance_date_hint
                                })
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
                                    let check = balance_check(a, p.day, p.actual);
                                    let result = if opening.get_untracked() {
                                        finance::confirm_opening(check)
                                    } else {
                                        finance::confirm_balance(check, p.book)
                                    };
                                    match result {
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
                                let Some(actual) = book_amount(&a, &value.get_untracked()) else {
                                    error.set(Some(amount_error().into()));
                                    return;
                                };
                                let Ok(selected) = day.get_untracked().parse::<Day>() else {
                                    error.set(Some(s().error_transaction_date.into()));
                                    return;
                                };
                                if selected > latest {
                                    error.set(Some(s().error_transaction_date.into()));
                                    return;
                                }
                                let book =
                                    journal::balance_on(&finance::transactions(), &a, selected.0);
                                if actual.checked_sub(book).is_none_or(|d| d == i64::MIN) {
                                    error.set(Some(amount_error().into()));
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
