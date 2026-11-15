//! Assets answers what the recorded ledger says the owner owns. Account
//! details and balance observations use the same journal as Today/Records.
mod editor;
mod overview;
mod trend;
pub use overview::assets_tab;
pub use trend::history_page;

use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, color, icon, space,
        surface::{hairline, row_button},
        toast::toast_view,
    },
};
use finance_core::{
    account::{Account, AccountKind, defaults},
    assets,
    journal::{self, Transaction},
    money,
};
use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};

/// Group display digits without changing exact minor units or editable input.
fn display_money(value: i64) -> String {
    crate::ui::currency::grouped(value)
}

pub(super) fn amount(value: i64, style: Type) -> impl IntoElement {
    amount_in(value, style, finance_core::currency::Currency::CNY)
}

pub(super) fn amount_in(
    value: i64,
    style: Type,
    currency: finance_core::currency::Currency,
) -> impl IntoElement {
    text(if currency == finance_core::currency::Currency::CNY {
        format!("¥{}", display_money(value))
    } else {
        format!("{} {}", currency.code(), display_money(value))
    })
    .typo(style)
    .number_of_lines(1)
    .shrink_to_fit(0.65)
    .min_w(px(0.0))
    .flex_shrink(1.0_f32)
    .tabular_nums()
    .text_color(color::INK)
}

pub fn account_page(name: &str) -> Screen {
    let own = signal(Account::parse(name).expect("account route created from a valid account"));
    let balance = signal(editor::take_created_check(name));
    let rename = signal(false);
    let transaction = signal(None::<String>);
    let shown = signal(50usize);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::balance_opened(balance);
    nav_page()
        .title(move || own.with(|a| a.name().to_owned()))
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || own.with(|a| a.name().to_owned().into()),
                    nav::pop,
                    Some(
                        IconBtn::new(Icon::Pencil, || s().rename_account.into())
                            .variant(Variant::Ghost)
                            .on_press(move || rename.set(true))
                            .into_element(),
                    ),
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pb_safe_area_plus(px(90.0))
                            .gap_5()
                            .child(dynamic(move || {
                                let a = own.get();
                                let entries = finance::transactions();
                                let book = journal::balance_on(&entries, &a, clock::today().0);
                                let checks = finance::checks();
                                let checked = checks
                                    .iter()
                                    .filter(|c| c.account == a)
                                    .max_by_key(|c| c.checked_at)
                                    .map(|c| {
                                        format!(
                                            "{} · {}",
                                            s().account_checked,
                                            s().short_date(Day(c.day))
                                        )
                                    });
                                untracked(move || {
                                    view()
                                        .gap_3()
                                        .pt_4()
                                        .child(
                                            text(if a.kind() == AccountKind::Liabilities {
                                                s().account_debt
                                            } else {
                                                s().account_balance
                                            })
                                            .typo(Type::Headline)
                                            .text_color(color::BODY),
                                        )
                                        .child(amount_in(
                                            assets::displayed(&a, book),
                                            Type::Display,
                                            a.currency(),
                                        ))
                                        .child(
                                            text(
                                                checked.unwrap_or_else(|| {
                                                    s().account_unchecked.into()
                                                }),
                                            )
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED),
                                        )
                                        .child(
                                            Btn::tonal()
                                                .label(|| s().check_balance.into())
                                                .on_press(move || balance.set(true)),
                                        )
                                })
                            }))
                            .child(
                                text(|| s().account_activity)
                                    .typo(Type::Title)
                                    .text_color(color::INK),
                            )
                            .child(dynamic(move || {
                                let a = own.get();
                                let mut entries: Vec<_> = finance::transactions()
                                    .into_iter()
                                    .filter(|t| t.postings.iter().any(|p| p.account == a))
                                    .collect();
                                entries.reverse();
                                let more = entries.len() > shown.get();
                                entries.truncate(shown.get());
                                untracked(move || {
                                    if entries.is_empty() {
                                        return text(|| s().account_activity_empty)
                                            .typo(Type::Body)
                                            .text_color(color::MUTED)
                                            .into_element();
                                    }
                                    view()
                                        .children(entries.into_iter().map(|t| {
                                            let id = t.id.clone();
                                            let value = assets::displayed(&a, t.amount_in(&a));
                                            let caption = format!(
                                                "{} · {}",
                                                s().long_date(Day(t.at.date())),
                                                t.note
                                            );
                                            let title = super::finance::transaction_title(&t);
                                            let label = format!(
                                                "{title}, {} {}",
                                                money::format(value),
                                                a.currency().code()
                                            );
                                            view()
                                                .child(
                                                    row_button(move || {
                                                        transaction.set(Some(id.clone()))
                                                    })
                                                    .accessibility_label(move || {
                                                        Some(label.clone().into())
                                                    })
                                                    .px_0()
                                                    .py_3()
                                                    .gap_3()
                                                    .child(
                                                        view()
                                                            .flex_1()
                                                            .min_w(px(0.0))
                                                            .gap_1()
                                                            .child(
                                                                text(title)
                                                                    .typo(Type::Headline)
                                                                    .text_color(color::INK)
                                                                    .number_of_lines(1),
                                                            )
                                                            .child(
                                                                text(
                                                                    caption
                                                                        .trim_end_matches(" · ")
                                                                        .to_owned(),
                                                                )
                                                                .typo(Type::Subhead)
                                                                .text_color(color::MUTED)
                                                                .number_of_lines(1),
                                                            ),
                                                    )
                                                    .child(amount_in(
                                                        value,
                                                        Type::Figure,
                                                        a.currency(),
                                                    )),
                                                )
                                                .child(hairline(0.0))
                                        }))
                                        .child(more.then(|| {
                                            Btn::secondary()
                                                .label(|| s().show_earlier.into())
                                                .on_press(move || shown.update(|n| *n += 50))
                                        }))
                                        .into_element()
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
                            move || balance.get() || rename.get() || transaction.get().is_some(),
                            |s| s.hidden(),
                        )
                        .child(toast_view(|| 24.0)),
                )
                .child(editor::account_editor(rename, Some(own)))
                .child(editor::balance_editor(balance, own))
                .child(super::finance::finance_editor(transaction)),
        )
}

pub(super) fn balance_title(t: &Transaction) -> Option<&'static str> {
    if t.postings
        .iter()
        .any(|p| p.account == defaults::opening().in_currency(p.account.currency()))
    {
        Some(s().opening_balance)
    } else if t
        .postings
        .iter()
        .any(|p| p.account == defaults::adjustment().in_currency(p.account.currency()))
    {
        Some(s().balance_adjustment)
    } else {
        None
    }
}

/// Balance entries remain readable from Today/Records as well as an account.
pub(super) fn balance_entry(t: Transaction, open: Signal<Option<String>>) -> AnyElement {
    let own = t.own_postings().next().map(|p| p.account.clone());
    let header = view()
        .flex_row()
        .items_center()
        .child(
            text(balance_title(&t).unwrap_or(s().transactions))
                .typo(Type::Title)
                .text_color(color::INK)
                .flex_1(),
        )
        .child(
            Btn::ghost()
                .label(|| s().close.into())
                .on_press(move || open.set(None)),
        );
    let body = view()
        .gap_4()
        .child(
            text(s().long_date(Day(t.at.date())))
                .typo(Type::Body)
                .text_color(color::MUTED),
        )
        .children(t.own_postings().map(|p| {
            view()
                .gap_2()
                .child(
                    text(p.account.name().to_owned())
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(amount_in(
                    assets::displayed(&p.account, p.amount),
                    Type::LargeTitle,
                    p.account.currency(),
                ))
        }))
        .child(
            text(|| s().balance_readonly)
                .typo(Type::Body)
                .text_color(color::MUTED),
        );
    let action = Btn::primary()
        .label(|| s().view_account.into())
        .on_press(move || {
            open.set(None);
            if let Some(a) = &own {
                nav::push(Route::Account(a.to_string()));
            }
        });
    crate::ui::sheet::task_sheet(
        move || open.get().is_some(),
        move || open.set(None),
        header,
        body,
        action,
    )
    .into_element()
}
