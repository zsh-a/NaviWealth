//! Confirmed manual ledger entries. Account creation stays in the draft until
//! the whole transaction has passed the domain's validation and is saved.

use std::{
    rc::Rc,
    sync::atomic::{AtomicU64, Ordering},
};

use jiff::civil::{Date, Time};
use navi_finance::{
    account::{Account, AccountKind, defaults},
    currency::Currency,
    journal::{self, Entry, Source, Transaction},
    money,
};
use nsh_base::{CalendarEntry, CalendarItemKind, alert_dialog, calendar};
use nsh_core::prelude::*;

use crate::{
    data::{clock, finance, settings},
    i18n::{Strings, s},
    ui::{
        Btn, Icon, Size, Type, Typo, Variant, color,
        field::{field, note, text_input},
        icon,
        segmented::{Segment, segmented},
        sheet::{initial_focus, retained, task_sheet},
        surface::{hairline, row_button},
        toast::show_toast,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Expense,
    Income,
    Transfer,
}

impl Kind {
    fn label(self, strings: &Strings) -> &'static str {
        match self {
            Self::Expense => strings.spending,
            Self::Income => strings.income,
            Self::Transfer => strings.transfer,
        }
    }
}

#[derive(Clone, Copy)]
struct Own {
    selected: Signal<String>,
    creating: Signal<bool>,
    kind: Signal<AccountKind>,
    name: Signal<String>,
    currency: Signal<Currency>,
}

impl Own {
    fn new(account: Option<Account>) -> Self {
        let currency = account.as_ref().map_or(Currency::CNY, Account::currency);
        Self {
            currency: signal(currency),
            selected: signal(account.map(|a| a.to_string()).unwrap_or_default()),
            creating: signal(false),
            kind: signal(AccountKind::Assets),
            name: signal(String::new()),
        }
    }

    fn account(self) -> Option<Account> {
        if self.creating.get() {
            Account::new_in(self.kind.get(), &self.name.get(), self.currency.get()).ok()
        } else {
            Account::parse(&self.selected.get())
                .ok()
                .filter(|a| a.is_cash())
        }
    }

    fn snapshot(self) -> (String, bool, AccountKind, String, Currency) {
        (
            self.selected.get(),
            self.creating.get(),
            self.kind.get(),
            self.name.get(),
            self.currency.get(),
        )
    }
}

#[derive(Clone, Copy)]
struct Form {
    kind: Signal<Kind>,
    amount: Signal<String>,
    received: Signal<String>,
    day: Signal<String>,
    time: Signal<String>,
    own: Own,
    other: Own,
    category: Signal<String>,
    payee: Signal<String>,
    memo: Signal<String>,
}

#[derive(PartialEq)]
struct Values {
    kind: Kind,
    amount: String,
    received: String,
    day: String,
    time: String,
    own: (String, bool, AccountKind, String, Currency),
    other: (String, bool, AccountKind, String, Currency),
    category: String,
    payee: String,
    memo: String,
}

impl Form {
    fn values(self) -> Values {
        Values {
            kind: self.kind.get(),
            amount: self.amount.get(),
            received: self.received.get(),
            day: self.day.get(),
            time: self.time.get(),
            own: self.own.snapshot(),
            other: self.other.snapshot(),
            category: self.category.get(),
            payee: self.payee.get(),
            memo: self.memo.get(),
        }
    }

    fn build(self, id: String, source: Source) -> Result<Transaction, &'static str> {
        let amount = money::parse(&self.amount.get(), false)
            .filter(|n| *n > 0)
            .ok_or(s().error_money)?;
        let day: Date = self
            .day
            .get()
            .trim()
            .parse()
            .map_err(|_| s().error_transaction_date)?;
        let time: Time = self
            .time
            .get()
            .trim()
            .parse()
            .map_err(|_| s().error_transaction_date)?;
        let own = self.own.account().ok_or(s().error_account)?;
        let entry = Entry {
            id,
            at: day.to_datetime(time),
            payee: self.payee.get().trim().to_owned(),
            note: self.memo.get().trim().to_owned(),
            source,
        };
        match self.kind.get() {
            Kind::Expense => {
                let category =
                    Account::parse(&self.category.get()).map_err(|_| s().error_account)?;
                journal::spend(entry, &own, &category.in_currency(own.currency()), amount)
                    .map_err(|_| s().error_account)
            }
            Kind::Income => {
                let category =
                    Account::parse(&self.category.get()).map_err(|_| s().error_account)?;
                journal::receive(entry, &own, &category.in_currency(own.currency()), amount)
                    .map_err(|_| s().error_account)
            }
            Kind::Transfer => {
                let other = self.other.account().ok_or(s().error_account)?;
                if own.currency() == other.currency() {
                    journal::transfer(entry, &own, &other, amount)
                } else {
                    let received = money::parse(&self.received.get(), false)
                        .filter(|v| *v > 0)
                        .ok_or(s().error_money)?;
                    journal::exchange(entry, &own, &other, amount, received)
                }
                .map_err(|_| s().error_transfer)
            }
        }
    }
}

/// The supported two-posting forms. Split postings and equity entries are never
/// flattened into a two-posting transaction by merely opening the editor.
fn parts(t: &Transaction) -> Option<(Kind, Account, Account, i64)> {
    if t.validate().is_ok() && t.postings.len() == 4 {
        let from = t.own_postings().find(|p| p.amount < 0)?;
        let to = t.own_postings().find(|p| p.amount > 0)?;
        let amount = from.amount.checked_neg()?;
        let expected = journal::exchange(
            Entry {
                id: t.id.clone(),
                at: t.at,
                payee: t.payee.clone(),
                note: t.note.clone(),
                source: t.source.clone(),
            },
            &from.account,
            &to.account,
            amount,
            to.amount,
        )
        .ok()?;
        let sorted = |postings: &[journal::Posting]| {
            let mut values: Vec<_> = postings
                .iter()
                .map(|p| (p.account.clone(), p.amount))
                .collect();
            values.sort();
            values
        };
        if sorted(&expected.postings) == sorted(&t.postings) {
            return Some((
                Kind::Transfer,
                from.account.clone(),
                to.account.clone(),
                amount,
            ));
        }
    }
    if t.postings.len() != 2 || t.validate().is_err() {
        return None;
    }
    let positive = t.postings.iter().find(|p| p.amount > 0)?;
    let negative = t.postings.iter().find(|p| p.amount < 0)?;
    match (positive.account.kind(), negative.account.kind()) {
        (AccountKind::Expenses, own) if own.is_own() => Some((
            Kind::Expense,
            negative.account.clone(),
            positive.account.clone(),
            positive.amount,
        )),
        (own, AccountKind::Income) if own.is_own() => Some((
            Kind::Income,
            positive.account.clone(),
            negative.account.clone(),
            positive.amount,
        )),
        (a, b) if a.is_own() && b.is_own() => Some((
            Kind::Transfer,
            negative.account.clone(),
            positive.account.clone(),
            positive.amount,
        )),
        _ => None,
    }
}

/// Owns its sheet, including dirty dismissal. `Some("")` starts a new entry.
pub fn finance_editor(open: Signal<Option<String>>) -> impl IntoElement {
    retained(
        move || open.get(),
        move |id| editor(id, open).into_element(),
    )
}

static NEXT: AtomicU64 = AtomicU64::new(0);

fn editor(id: String, open: Signal<Option<String>>) -> impl IntoElement {
    let existing = finance::transactions().into_iter().find(|t| t.id == id);
    if let Some(Source::Investment { trade_id }) = existing.as_ref().map(|t| &t.source) {
        return super::holdings::trade_receipt(trade_id, move || open.set(None));
    }
    if let Some(entry) = existing
        .as_ref()
        .filter(|t| super::assets::balance_title(t).is_some())
    {
        return super::assets::balance_entry(entry.clone(), open);
    }
    let parsed = existing.as_ref().and_then(parts);
    let editable = id.is_empty() || parsed.is_some();
    let preferences = settings::current().ledger;
    let accounts = finance::accounts();
    let valid = |value: &Option<String>| {
        value
            .as_ref()
            .and_then(|v| Account::parse(v).ok())
            .filter(|a| accounts.contains(a))
    };
    let own_accounts: Vec<_> = accounts.iter().filter(|a| a.is_cash()).cloned().collect();
    let first_own = valid(&preferences.own)
        .filter(|a| a.is_cash())
        .or_else(|| (own_accounts.len() == 1).then(|| own_accounts[0].clone()));
    let now = clock::zoned(clock::now_ms()).datetime();
    let at = existing.as_ref().map_or(now, |t| t.at);
    let kind = parsed.as_ref().map_or(Kind::Expense, |p| p.0);
    let form = Form {
        kind: signal(kind),
        received: signal(
            existing
                .as_ref()
                .and_then(|t| t.own_postings().find(|p| p.amount > 0))
                .map(|p| money::format(p.amount))
                .unwrap_or_default(),
        ),
        amount: signal(
            parsed
                .as_ref()
                .map(|p| money::format(p.3))
                .unwrap_or_default(),
        ),
        day: signal(at.date().to_string()),
        time: signal(if existing.is_some() {
            at.time().to_string()
        } else {
            format!("{:02}:{:02}", at.hour(), at.minute())
        }),
        own: Own::new(parsed.as_ref().map(|p| p.1.clone()).or(first_own)),
        other: Own::new(
            parsed
                .as_ref()
                .filter(|p| p.0 == Kind::Transfer)
                .map(|p| p.2.clone())
                .or_else(|| valid(&preferences.other).filter(|a| a.is_cash())),
        ),
        category: signal(
            parsed
                .as_ref()
                .filter(|p| p.0 != Kind::Transfer)
                .map(|p| p.2.to_string())
                .unwrap_or_else(|| {
                    valid(&preferences.expense)
                        .filter(|a| a.kind() == AccountKind::Expenses)
                        .unwrap_or_else(defaults::other_expense)
                        .to_string()
                }),
        ),
        payee: signal(
            existing
                .as_ref()
                .map(|t| t.payee.clone())
                .unwrap_or_default(),
        ),
        memo: signal(
            existing
                .as_ref()
                .map(|t| t.note.clone())
                .unwrap_or_default(),
        ),
    };
    let last_expense = signal(if kind == Kind::Expense {
        form.category.get_untracked()
    } else {
        preferences
            .expense
            .clone()
            .unwrap_or_else(|| defaults::other_expense().to_string())
    });
    let last_income = signal(if kind == Kind::Income {
        form.category.get_untracked()
    } else {
        preferences
            .income
            .clone()
            .unwrap_or_else(|| defaults::other_income().to_string())
    });
    let panel = signal(Panel::Main);
    let autofocus = stored(id.is_empty());
    let initial = stored(form.values());
    let error = signal(None::<String>);
    let asking = signal(false);
    let close = move || {
        if panel.get_untracked() != Panel::Main {
            panel.set(match panel.get_untracked() {
                Panel::NewOwn => Panel::Own,
                Panel::NewOther => Panel::Other,
                _ => Panel::Main,
            });
            dismiss_keyboard();
            return;
        }
        if untracked(|| initial.with(|v| *v == form.values())) {
            open.set(None);
            return;
        }
        if asking.get() {
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
                .is_ok_and(|a| a.action.as_deref() == Some("discard"));
            asking.set(false);
            if discard {
                open.set(None);
            }
        });
    };
    let kept = stored(existing.clone());
    let save = move || {
        if !editable {
            return;
        }
        let id = kept
            .with(|t| t.as_ref().map(|t| t.id.clone()))
            .unwrap_or_else(|| {
                format!(
                    "manual:{}:{}",
                    clock::now_ms(),
                    NEXT.fetch_add(1, Ordering::Relaxed)
                )
            });
        let source = kept
            .with(|t| t.as_ref().map(|t| t.source.clone()))
            .unwrap_or(Source::Manual);
        match untracked(|| form.build(id, source)) {
            Err(message) => error.set(Some(message.to_owned())),
            Ok(t) => match finance::save(t) {
                Ok(()) => {
                    let mut defaults = settings::current().ledger;
                    defaults.own = form.own.account().map(|a| a.to_string());
                    match form.kind.get() {
                        Kind::Expense => defaults.expense = Some(form.category.get()),
                        Kind::Income => defaults.income = Some(form.category.get()),
                        Kind::Transfer => {
                            defaults.other = form.other.account().map(|a| a.to_string())
                        }
                    }
                    settings::save_ledger_defaults(defaults);
                    dismiss_keyboard();
                    open.set(None);
                }
                Err(cause) => {
                    log::error!("finance: save failed: {cause}");
                    error.set(Some(s().error_transaction_storage.to_owned()));
                }
            },
        }
    };
    let header = view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            text(move || match panel.get() {
                Panel::Main => {
                    if kept.with(|t| t.is_some()) {
                        s().edit_transaction
                    } else {
                        s().log_transaction
                    }
                }
                Panel::Own => s().own_account,
                Panel::Other => s().to_account,
                Panel::Category => s().category,
                Panel::Date => s().transaction_date,
                Panel::Details => s().transaction_details,
                Panel::NewOwn | Panel::NewOther => s().add_account,
            })
            .typo(Type::Title)
            .text_color(color::INK)
            .flex_1()
            .role(AccessibilityRole::Header),
        )
        .child(
            Btn::ghost()
                .size(Size::Small)
                .label(move || {
                    if panel.get() == Panel::Main {
                        s().cancel
                    } else {
                        s().back
                    }
                    .into()
                })
                .on_press(close),
        );
    let body = dynamic(move || {
        let selected = panel.get();
        untracked(move || match selected {
            Panel::Main => {
                let focus = if autofocus.replace(false) {
                    initial_focus()
                } else {
                    element_ref()
                };
                view()
                    .gap_3()
                    .child(segmented(
                        vec![
                            Segment::new(Kind::Expense, || s().spending.into()),
                            Segment::new(Kind::Income, || s().income.into()),
                            Segment::new(Kind::Transfer, || s().transfer.into()),
                        ],
                        move || form.kind.get(),
                        move |kind| {
                            match form.kind.get_untracked() {
                                Kind::Expense => last_expense.set(form.category.get_untracked()),
                                Kind::Income => last_income.set(form.category.get_untracked()),
                                _ => {}
                            }
                            form.kind.set(kind);
                            if kind != Kind::Transfer {
                                form.category.set(if kind == Kind::Expense {
                                    last_expense.get_untracked()
                                } else {
                                    last_income.get_untracked()
                                });
                            }
                        },
                    ))
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_2()
                            .child(
                                text(move || {
                                    form.own
                                        .account()
                                        .map_or(Currency::CNY, |a| a.currency())
                                        .code()
                                })
                                .typo(Type::Title)
                                .text_color(color::MUTED),
                            )
                            .child(
                                text_input(form.amount)
                                    .label(|| s().money_amount)
                                    .placeholder("0.00")
                                    .element_ref(&focus)
                                    .keyboard_type(nsh_core::element::KeyboardType::Decimal)
                                    .typo(Type::LargeTitle)
                                    .tabular_nums()
                                    .h(px(68.0))
                                    .flex_1()
                                    .min_w(px(0.0)),
                            ),
                    )
                    .child(
                        view()
                            .flex_row()
                            .gap_3()
                            .child(
                                choice(
                                    move || {
                                        if form.kind.get() == Kind::Transfer {
                                            s().from_account
                                        } else {
                                            s().own_account
                                        }
                                    },
                                    move || {
                                        form.own
                                            .account()
                                            .map(|a| crate::ui::currency::account_label(&a))
                                            .unwrap_or_else(|| s().choose_account.into())
                                    },
                                    move || {
                                        dismiss_keyboard();
                                        panel.set(Panel::Own);
                                    },
                                )
                                .flex_1()
                                .min_w(px(0.0)),
                            )
                            .child(
                                choice(
                                    move || {
                                        if form.kind.get() == Kind::Transfer {
                                            s().to_account
                                        } else {
                                            s().category
                                        }
                                    },
                                    move || {
                                        if form.kind.get() == Kind::Transfer {
                                            form.other
                                                .account()
                                                .map(|a| crate::ui::currency::account_label(&a))
                                                .unwrap_or_else(|| s().choose_account.into())
                                        } else {
                                            Account::parse(&form.category.get())
                                                .map(|a| category_label(&a))
                                                .unwrap_or_default()
                                        }
                                    },
                                    move || {
                                        dismiss_keyboard();
                                        panel.set(if form.kind.get() == Kind::Transfer {
                                            Panel::Other
                                        } else {
                                            Panel::Category
                                        });
                                    },
                                )
                                .flex_1()
                                .min_w(px(0.0)),
                            ),
                    )
                    .child(when(
                        move || {
                            form.kind.get() == Kind::Transfer
                                && form
                                    .own
                                    .account()
                                    .zip(form.other.account())
                                    .is_some_and(|(a, b)| a.currency() != b.currency())
                        },
                        move || {
                            field(
                                || {
                                    crate::i18n::statement_import::copy(
                                        "Amount received",
                                        "实际到账金额",
                                    )
                                },
                                text_input(form.received)
                                    .label(|| {
                                        crate::i18n::statement_import::copy(
                                            "Amount received",
                                            "实际到账金额",
                                        )
                                    })
                                    .keyboard_type(nsh_core::element::KeyboardType::Decimal),
                            )
                        },
                    ))
                    .child(choice(
                        || s().transaction_date,
                        move || {
                            form.day
                                .get()
                                .parse()
                                .ok()
                                .map(|d| s().day_title(crate::domain::meal::Day(d), clock::today()))
                                .unwrap_or_default()
                        },
                        move || {
                            dismiss_keyboard();
                            panel.set(Panel::Date);
                        },
                    ))
                    .child(choice(
                        || s().transaction_details,
                        move || {
                            let values = [form.payee.get(), form.memo.get()];
                            let text = values
                                .iter()
                                .filter(|v| !v.is_empty())
                                .cloned()
                                .collect::<Vec<_>>()
                                .join(" · ");
                            if text.is_empty() {
                                s().add_details.into()
                            } else {
                                text
                            }
                        },
                        move || {
                            dismiss_keyboard();
                            panel.set(Panel::Details);
                        },
                    ))
                    .child((!editable).then(|| {
                        text(|| s().error_transaction)
                            .typo(Type::Subhead)
                            .text_color(color::DANGER)
                    }))
                    .into_element()
            }
            Panel::Own | Panel::Other => accounts_panel(
                if selected == Panel::Own {
                    form.own
                } else {
                    form.other
                },
                panel,
                selected == Panel::Other,
            )
            .into_element(),
            Panel::NewOwn | Panel::NewOther => new_account(
                if selected == Panel::NewOwn {
                    form.own
                } else {
                    form.other
                },
                panel,
            )
            .into_element(),
            Panel::Category => view()
                .gap_1()
                .children(
                    finance::accounts()
                        .into_iter()
                        .filter(|a| {
                            a.kind()
                                == if form.kind.get() == Kind::Income {
                                    AccountKind::Income
                                } else {
                                    AccountKind::Expenses
                                }
                        })
                        .map(|a| {
                            a.in_currency(
                                form.own.account().map_or(Currency::CNY, |a| a.currency()),
                            )
                        })
                        .collect::<std::collections::BTreeSet<_>>()
                        .into_iter()
                        .map(move |a| {
                            let name = category_label(&a);
                            let chosen = form.category.get() == a.as_str();
                            row_button(move || {
                                form.category.set(a.to_string());
                                panel.set(Panel::Main);
                            })
                            .min_h(px(48.0))
                            .py_2()
                            .px_2()
                            .child(text(name).typo(Type::Body).text_color(color::INK).flex_1())
                            .child(chosen.then(|| icon(Icon::Check, 18.0, color::INK)))
                        }),
                )
                .into_element(),
            Panel::Date => date_picker(form.day, move || panel.set(Panel::Main)).into_element(),
            Panel::Details => view()
                .gap_4()
                .child(field(
                    || s().transaction_payee,
                    text_input(form.payee).label(|| s().transaction_payee),
                ))
                .child(field(
                    || s().transaction_note,
                    text_input(form.memo).label(|| s().transaction_note),
                ))
                .child(field(
                    || s().transaction_time,
                    text_input(form.time)
                        .label(|| s().transaction_time)
                        .placeholder("18:30"),
                ))
                .child(kept.with(|t| t.clone()).map(|t| {
                    Btn::new(Variant::Danger)
                        .label(|| s().delete_transaction.into())
                        .on_press(move || match finance::remove(&t.id) {
                            Ok(removed) => {
                                open.set(None);
                                show_toast(
                                    s().transaction_deleted,
                                    Some((
                                        s().undo.into(),
                                        Rc::new(move || {
                                            if let Err(cause) = finance::save(removed.clone()) {
                                                log::error!("finance: undo failed: {cause}");
                                                show_toast(s().error_transaction_storage, None);
                                            }
                                        }),
                                    )),
                                );
                            }
                            Err(cause) => {
                                log::error!("finance: delete failed: {cause}");
                                error.set(Some(s().error_transaction_storage.into()));
                            }
                        })
                }))
                .into_element(),
        })
    });
    let actions = view()
        .gap_2()
        .child(note(move || error.get().map(Into::into), || true))
        .child(
            when(
                move || panel.get() == Panel::Main,
                move || {
                    Btn::primary()
                        .label(|| s().save_transaction.into())
                        .disabled(move || !editable)
                        .on_press(save)
                },
            )
            .otherwise(move || {
                Btn::secondary()
                    .label(|| s().done.into())
                    .on_press(move || {
                        if panel.get() == Panel::Details && form.time.get().parse::<Time>().is_err()
                        {
                            error.set(Some(s().error_time.into()));
                            return;
                        }
                        error.set(None);
                        dismiss_keyboard();
                        panel.set(Panel::Main);
                    })
                    .style_when(
                        move || matches!(panel.get(), Panel::NewOwn | Panel::NewOther),
                        |s| s.hidden(),
                    )
            }),
        );
    task_sheet(move || open.get().is_some(), close, header, body, actions).into_element()
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Panel {
    Main,
    Own,
    Other,
    Category,
    Date,
    Details,
    NewOwn,
    NewOther,
}

fn choice(
    label: impl Fn() -> &'static str + Copy + 'static,
    value: impl Fn() -> String + 'static,
    press: impl Fn() + 'static,
) -> View {
    view()
        .child(
            row_button(press)
                .accessibility_label(move || Some(label().into()))
                .px_2()
                .py_2()
                .min_h(px(56.0))
                .child(
                    view()
                        .gap_1()
                        .flex_1()
                        .min_w(px(0.0))
                        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
                        .child(
                            text(value)
                                .typo(Type::Body)
                                .text_color(color::INK)
                                .number_of_lines(1),
                        ),
                )
                .child(icon(Icon::ChevronDown, 16.0, color::MUTED)),
        )
        .child(hairline(0.0))
}

fn accounts_panel(own: Own, panel: Signal<Panel>, other: bool) -> impl IntoElement {
    view()
        .gap_1()
        .children(
            finance::accounts()
                .into_iter()
                .filter(|a| a.is_cash())
                .map(move |a| {
                    let name = account_label(&a);
                    let chosen = own.account().as_ref() == Some(&a);
                    row_button(move || {
                        own.selected.set(a.to_string());
                        own.creating.set(false);
                        panel.set(Panel::Main);
                    })
                    .min_h(px(48.0))
                    .py_2()
                    .px_2()
                    .child(text(name).typo(Type::Body).text_color(color::INK).flex_1())
                    .child(chosen.then(|| icon(Icon::Check, 18.0, color::INK)))
                }),
        )
        .child(
            Btn::ghost()
                .icon(Icon::Plus)
                .label(|| s().add_account.into())
                .on_press(move || {
                    panel.set(if other {
                        Panel::NewOther
                    } else {
                        Panel::NewOwn
                    })
                }),
        )
}

fn new_account(own: Own, panel: Signal<Panel>) -> impl IntoElement {
    let name = signal(own.name.get_untracked());
    let kind = signal(own.kind.get_untracked());
    let currency = signal(own.currency.get_untracked());
    let invalid = signal(false);
    view()
        .gap_4()
        .child(segmented(
            vec![
                Segment::new(AccountKind::Assets, || s().asset_account.into()),
                Segment::new(AccountKind::Liabilities, || s().liability_account.into()),
            ],
            move || kind.get(),
            move |k| kind.set(k),
        ))
        .child(crate::ui::currency::picker(currency))
        .child(
            text_input(name)
                .auto_focus(true)
                .label(|| s().account_name)
                .placeholder(|| s().account_name),
        )
        .child(note(
            move || invalid.get().then(|| s().error_account.into()),
            || true,
        ))
        .child(Btn::primary().label(|| s().done.into()).on_press(move || {
            if Account::new_in(kind.get(), &name.get(), currency.get()).is_err() {
                invalid.set(true);
                return;
            }
            own.kind.set(kind.get());
            own.currency.set(currency.get());
            own.name.set(name.get());
            own.creating.set(true);
            dismiss_keyboard();
            panel.set(Panel::Main);
        }))
}

pub(super) fn date_picker(
    day: Signal<String>,
    selected: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .gap_2()
                .child(
                    Btn::tonal()
                        .label(|| s().today.into())
                        .on_press(move || {
                            day.set(clock::today().to_string());
                            selected();
                        })
                        .flex_1(),
                )
                .child(
                    Btn::tonal()
                        .label(|| s().yesterday.into())
                        .on_press(move || {
                            day.set(clock::today().plus_days(-1).to_string());
                            selected();
                        })
                        .flex_1(),
                ),
        )
        .child(
            calendar()
                .default_value(nsh_base::Date::Single(day.get().parse().ok()))
                .first_day_of_week(
                    if s().week_start() == crate::domain::review::WeekStart::Monday {
                        1
                    } else {
                        0
                    },
                )
                .previous_accessibility_label(|| Some(s().previous_month.into()))
                .next_accessibility_label(|| Some(s().next_month.into()))
                .header_style(|s| s.gap_2().pb_3())
                .row_style(|s| s.gap_1())
                .month_style(|s| s.gap_1())
                .item_style(|s| {
                    s.min_h(px(40.0))
                        .rounded(px(8.0))
                        .text_color(color::INK)
                        .selected(|s| s.bg(color::SURFACE_2))
                })
                .render_item(|item: &CalendarEntry| match item.kind {
                    CalendarItemKind::Previous => {
                        icon(Icon::ChevronLeft, 18.0, color::INK).into_element()
                    }
                    CalendarItemKind::Next => {
                        icon(Icon::ChevronRight, 18.0, color::INK).into_element()
                    }
                    CalendarItemKind::Weekday => text(
                        s().weekday_short(
                            crate::domain::meal::Day(jiff::civil::date(2026, 11, 1))
                                .plus_days(item.value),
                        ),
                    )
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .into_element(),
                    CalendarItemKind::MonthToggle | CalendarItemKind::Month => {
                        text(if s().lang == crate::domain::recognition::Lang::Zh {
                            format!("{}月", item.month)
                        } else {
                            [
                                "January",
                                "February",
                                "March",
                                "April",
                                "May",
                                "June",
                                "July",
                                "August",
                                "September",
                                "October",
                                "November",
                                "December",
                            ][(item.month.clamp(1, 12) - 1) as usize]
                                .into()
                        })
                        .typo(Type::Subhead)
                        .into_element()
                    }
                    _ => text(item.value.to_string())
                        .typo(Type::Body)
                        .tabular_nums()
                        .into_element(),
                })
                .on_change(move |value: &nsh_base::Date| {
                    if let Some(date) = value.start() {
                        day.set(date.to_string());
                        selected();
                    }
                }),
        )
}

fn account_label(account: &Account) -> String {
    let kind = match account.kind() {
        AccountKind::Assets => s().asset_account,
        AccountKind::Liabilities => s().liability_account,
        _ => return category_label(account),
    };
    format!("{} · {kind}", crate::ui::currency::account_label(account))
}

pub(super) fn category_label(account: &Account) -> String {
    if s().lang == crate::domain::recognition::Lang::Zh {
        return account.name().to_owned();
    }
    match account.name() {
        "餐饮" => "Dining",
        "买菜日用" => "Groceries",
        "交通" => "Transport",
        "居住" => "Housing",
        "购物" => "Shopping",
        "娱乐" => "Entertainment",
        "医疗" => "Health",
        "人情" => "Gifts",
        "其他" => "Other",
        "工资" => "Salary",
        other => other,
    }
    .to_owned()
}

pub(super) fn transaction_title(t: &Transaction) -> String {
    if let Source::Investment { trade_id } = &t.source {
        let label = finance::holdings()
            .trades
            .iter()
            .find(|t| t.id == *trade_id)
            .map(|t| super::holdings::kind_label(t.kind))
            .unwrap_or(s().record_trade);
        return format!("{label} · {}", t.payee);
    }
    let parsed = parts(t);
    if t.payee.trim().is_empty() {
        parsed
            .as_ref()
            .map(|p| {
                if p.0 == Kind::Transfer {
                    s().transfer.to_owned()
                } else {
                    category_label(&p.2)
                }
            })
            .unwrap_or_else(|| {
                super::assets::balance_title(t)
                    .unwrap_or(s().transactions)
                    .to_owned()
            })
    } else {
        t.payee.clone()
    }
}

/// A ledger row for Today and Records. Transfers explicitly say Transfer and
/// never acquire a spending sign merely because money leaves one own account.
pub fn transaction_row(t: Transaction, on_press: impl Fn() + 'static) -> impl IntoElement {
    let investment = matches!(t.source, Source::Investment { .. });
    let system_record = super::assets::balance_title(&t).is_some();
    let investment_cash = match &t.source {
        Source::Investment { trade_id } => finance::holdings_snapshot()
            .trades
            .iter()
            .find(|trade| trade.id == *trade_id)
            .and_then(|trade| trade.cash.clone()),
        _ => None,
    };
    let parsed = if investment { None } else { parts(&t) };
    let title = transaction_title(&t);
    let amount = parsed
        .as_ref()
        .map(|p| {
            format!(
                "{}{}",
                match p.0 {
                    Kind::Expense => "−",
                    Kind::Income => "+",
                    Kind::Transfer => "",
                },
                crate::ui::currency::grouped(p.3)
            )
        })
        .unwrap_or_else(|| {
            if let Some(cash) = &investment_cash {
                return crate::ui::currency::grouped(
                    t.postings
                        .iter()
                        .find(|p| p.account == *cash)
                        .map_or(0, |p| p.amount),
                );
            }
            t.own_postings()
                .next()
                .map(|p| crate::ui::currency::grouped(p.amount))
                .unwrap_or_else(|| "—".into())
        });
    let kind = parsed.as_ref().map_or_else(
        || super::assets::balance_title(&t).unwrap_or(s().transactions),
        |p| p.0.label(s()),
    );
    let accounts = parsed
        .as_ref()
        .map(|p| {
            if p.0 == Kind::Transfer {
                format!(
                    "{} → {}",
                    crate::ui::currency::account_label(&p.1),
                    crate::ui::currency::account_label(&p.2)
                )
            } else {
                p.1.name().to_owned()
            }
        })
        .unwrap_or_else(|| {
            if investment {
                return investment_cash
                    .as_ref()
                    .map(|account| account.name().to_owned())
                    .unwrap_or_else(|| s().opening_holding.to_owned());
            }
            t.own_postings()
                .next()
                .map(|p| p.account.name().to_owned())
                .unwrap_or_default()
        });
    let sub = format!(
        "{kind} · {accounts} · {:02}:{:02}",
        t.at.hour(),
        t.at.minute()
    );
    let currency = t
        .own_postings()
        .next()
        .map_or(Currency::CNY, |p| p.account.currency());
    let accessibility = format!("{title}, {amount} {}, {sub}", currency.code());
    // Keep the amount with its native currency on one baseline when it
    // fits. Larger system text moves it below the record's metadata.
    let amount_chars = amount.len();
    let stacked = move || font_scale() > 1.2 || window().width.0 < 360.0 || amount_chars > 12;
    let inline_amount = amount.clone();
    let amount_style = if system_record {
        Type::Body
    } else {
        Type::Figure
    };
    let title_style = if system_record {
        Type::Callout
    } else {
        Type::Headline
    };
    let tint = if system_record {
        color::MUTED
    } else {
        color::INK
    };
    // A balance check, not a setting: Sliders already names Settings.
    let glyph = if system_record {
        crate::ui::Icon::Check
    } else if investment {
        crate::ui::Icon::Chart
    } else {
        crate::ui::Icon::Wallet
    };
    row_button(on_press)
        .pl(px(super::rows::LEAD))
        .pr(px(18.0))
        .py(px(if system_record { 8.0 } else { 10.0 }))
        .min_h(px(if system_record { 60.0 } else { 72.0 }))
        .gap(px(14.0))
        .accessibility_label(move || Some(accessibility.clone().into()))
        .child(super::rows::glyph(
            glyph,
            if system_record {
                36.0
            } else {
                super::rows::THUMB
            },
        ))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(3.0))
                .child(
                    text(title)
                        .typo(title_style)
                        .text_color(tint)
                        .number_of_lines(1),
                )
                .child(
                    text(sub)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                )
                .child(when(stacked, move || {
                    crate::ui::currency::amount(amount.clone(), currency, amount_style, tint)
                })),
        )
        .child(when(
            move || !stacked(),
            move || {
                crate::ui::currency::amount(inline_amount.clone(), currency, amount_style, tint)
                    .justify_end()
                    .max_w(px(156.0))
            },
        ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_editor_round_trips_all_three_posting_directions() {
        let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
        let card = Account::new(AccountKind::Liabilities, "Card").unwrap();
        let entry = || Entry {
            id: "t".into(),
            at: "2026-11-14T12:30:00".parse().unwrap(),
            payee: "Shop".into(),
            note: String::new(),
            source: Source::Manual,
        };
        let expense = journal::spend(entry(), &card, &defaults::expense("餐饮"), 3150).unwrap();
        assert_eq!(
            parts(&expense),
            Some((Kind::Expense, card.clone(), defaults::expense("餐饮"), 3150))
        );
        let income = journal::receive(entry(), &cash, &defaults::income("工资"), 10000).unwrap();
        assert_eq!(
            parts(&income),
            Some((Kind::Income, cash.clone(), defaults::income("工资"), 10000))
        );
        let repayment = journal::transfer(entry(), &cash, &card, 3150).unwrap();
        assert_eq!(parts(&repayment), Some((Kind::Transfer, cash, card, 3150)));
    }

    #[test]
    fn opening_balance_is_not_silently_rewritten_as_spending() {
        let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
        let entry = Entry {
            id: "t".into(),
            at: "2026-11-14T12:30:00".parse().unwrap(),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        };
        assert!(parts(&journal::opening(entry, &cash, 10000).unwrap()).is_none());
    }
}
