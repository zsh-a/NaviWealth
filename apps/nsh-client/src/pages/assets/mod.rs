//! Assets answers what the recorded ledger says the owner owns. Account
//! details and balance observations use the same journal as Today/Records.
mod editor;
mod trend;

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

pub fn assets_tab() -> impl IntoElement {
    let create = signal(false);
    let holding = signal(None::<String>);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::holdings_opened(holding);
    view()
        .flex_1()
        .child(
            scroll().flex_1().child(
                view()
                    .px(px(space::GUTTER))
                    .pt_safe_area_plus(px(12.0))
                    .pb(move || px(super::home::dock_clearance()))
                    .gap_5()
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_3()
                            .child(
                                text(|| s().assets)
                                    .typo(Type::LargeTitle)
                                    .text_color(color::INK)
                                    .flex_1()
                                    .role(AccessibilityRole::Header),
                            )
                            .child(
                                IconBtn::new(Icon::Plus, || s().add_account.into())
                                    .variant(Variant::Secondary)
                                    .on_press(move || create.set(true))
                                    .style_when(
                                        || {
                                            !finance::accounts().iter().any(|a| a.is_cash())
                                                && finance::holdings().securities.is_empty()
                                        },
                                        |s| s.hidden(),
                                    ),
                            ),
                    )
                    .child(dynamic(move || {
                        let accounts: Vec<_> = finance::accounts()
                            .into_iter()
                            .filter(|a| a.is_cash())
                            .collect();
                        let entries = finance::transactions();
                        let portfolio = finance::holdings();
                        let checks = finance::checks();
                        let today = clock::today();
                        untracked(move || {
                            if accounts.is_empty() && portfolio.securities.is_empty() {
                                return view()
                                    .gap_3()
                                    .py_5()
                                    .child(
                                        text(|| s().assets_empty)
                                            .typo(Type::Title)
                                            .text_color(color::INK),
                                    )
                                    .child(
                                        text(|| s().assets_empty_body)
                                            .typo(Type::Body)
                                            .text_color(color::MUTED),
                                    )
                                    .child(
                                        Btn::primary()
                                            .label(|| s().add_account.into())
                                            .on_press(move || create.set(true)),
                                    )
                                    .child(
                                        Btn::secondary()
                                            .label(|| s().add_holding.into())
                                            .on_press(move || holding.set(Some(String::new()))),
                                    )
                                    .into_element();
                            }
                            let snapshot = portfolio
                                .overview(&entries, today.0)
                                .expect("validated holdings valuation");
                            let has_holdings = !portfolio.securities.is_empty();
                            let balances = journal::balances(
                                entries.iter().filter(|t| t.at.date() <= today.0),
                            );
                            view()
                                .gap_5()
                                .child(
                                    view()
                                        .gap_2()
                                        .child(
                                            text(move || {
                                                if has_holdings {
                                                    s().portfolio_net
                                                } else {
                                                    s().net_worth
                                                }
                                            })
                                            .typo(Type::Headline)
                                            .text_color(color::BODY),
                                        )
                                        .child(amount(snapshot.net, Type::Display))
                                        .child(
                                            view()
                                                .flex_row()
                                                .gap_4()
                                                .child(metric(s().total_assets, snapshot.assets))
                                                .child(metric(s().total_debt, snapshot.debt)),
                                        )
                                        .child(
                                            text(move || {
                                                if has_holdings {
                                                    s().portfolio_basis
                                                } else {
                                                    s().assets_basis
                                                }
                                            })
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED),
                                        ),
                                )
                                .child(super::holdings::section(holding))
                                .child(trend::chart(&entries, &portfolio, today))
                                .children(
                                    [AccountKind::Assets, AccountKind::Liabilities]
                                        .into_iter()
                                        .filter_map(|kind| {
                                            let own: Vec<_> = accounts
                                                .iter()
                                                .filter(|a| a.kind() == kind)
                                                .cloned()
                                                .collect();
                                            if own.is_empty() {
                                                return None;
                                            }
                                            Some(
                                                view()
                                                    .gap_2()
                                                    .child(
                                                        text(if kind == AccountKind::Assets {
                                                            s().total_assets
                                                        } else {
                                                            s().total_debt
                                                        })
                                                        .typo(Type::Title)
                                                        .text_color(color::INK),
                                                    )
                                                    .children(own.into_iter().map(|a| {
                                                        let balance =
                                                            balances.get(&a).copied().unwrap_or(0);
                                                        let checked = checks
                                                            .iter()
                                                            .filter(|c| c.account == a)
                                                            .max_by_key(|c| c.checked_at);
                                                        let detail = checked
                                                            .map(|c| {
                                                                format!(
                                                                    "{} · {}",
                                                                    s().account_checked,
                                                                    s().short_date(Day(c.day))
                                                                )
                                                            })
                                                            .unwrap_or_else(|| {
                                                                s().account_unchecked.into()
                                                            });
                                                        let name = a.name().to_owned();
                                                        let value = assets::displayed(&a, balance);
                                                        let label = format!(
                                                            "{name}, {} CNY, {detail}",
                                                            money::format(value)
                                                        );
                                                        view()
                                                            .child(
                                                                row_button(move || {
                                                                    nav::push(Route::Account(
                                                                        a.to_string(),
                                                                    ))
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
                                                                            text(name)
                                                                                .typo(
                                                                                    Type::Headline,
                                                                                )
                                                                                .text_color(
                                                                                    color::INK,
                                                                                )
                                                                                .number_of_lines(1),
                                                                        )
                                                                        .child(
                                                                            text(detail)
                                                                                .typo(Type::Caption)
                                                                                .text_color(
                                                                                    color::MUTED,
                                                                                ),
                                                                        ),
                                                                )
                                                                .child(amount(value, Type::Figure))
                                                                .child(icon(
                                                                    Icon::ChevronRight,
                                                                    16.0,
                                                                    color::MUTED,
                                                                )),
                                                            )
                                                            .child(hairline(0.0))
                                                    })),
                                            )
                                        }),
                                )
                                .into_element()
                        })
                    })),
            ),
        )
        .child(editor::account_editor(create, None))
        .child(super::holdings::trade_editor(holding))
}

fn metric(label: &'static str, value: i64) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
        .child(amount(value, Type::Figure))
}

pub(super) fn amount(value: i64, style: Type) -> impl IntoElement {
    text(format!("¥{}", money::format(value)))
        .typo(style)
        .tabular_nums()
        .text_color(color::INK)
}

pub fn account_page(name: &str) -> Screen {
    let own = signal(Account::parse(name).expect("account route created from a valid account"));
    let balance = signal(false);
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
                                        .child(amount(assets::displayed(&a, book), Type::Display))
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
                                            let label =
                                                format!("{title}, {} CNY", money::format(value));
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
                                                    .child(amount(value, Type::Figure)),
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
    if t.postings.iter().any(|p| p.account == defaults::opening()) {
        Some(s().opening_balance)
    } else if t
        .postings
        .iter()
        .any(|p| p.account == defaults::adjustment())
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
                .child(amount(
                    assets::displayed(&p.account, p.amount),
                    Type::LargeTitle,
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
