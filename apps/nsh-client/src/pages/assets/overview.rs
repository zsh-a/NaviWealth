//! The asset overview is a scan of current values. History and maintenance
//! have explicit entries so neither interrupts the account/position list.
use super::*;
use crate::ui::{sheet::bottom_sheet, surface::card};

pub fn assets_tab() -> impl IntoElement {
    let manage = signal(false);
    let create = signal(false);
    let holding = signal(None::<String>);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::assets_opened(manage, holding);
    view()
        .flex_1()
        .child(
            scroll().flex_1().child(
                view()
                    .px(px(space::GUTTER))
                    .pt_safe_area_plus(px(12.0))
                    .pb(move || px(super::super::home::dock_clearance()))
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
                                Btn::ghost()
                                    .label(|| s().manage_assets.into())
                                    .on_press(move || manage.set(true))
                                    .px_0(),
                            ),
                    )
                    .child(dynamic(move || {
                        let accounts: Vec<_> = finance::accounts()
                            .into_iter()
                            .filter(Account::is_cash)
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
                                    card()
                                        .p_5()
                                        .gap_3()
                                        .child(
                                            text(|| s().portfolio_net)
                                                .typo(Type::Subhead)
                                                .text_color(color::MUTED),
                                        )
                                        .child(net_figure(snapshot.net))
                                        .child(
                                            view()
                                                .flex_row()
                                                .gap_4()
                                                .py_2()
                                                .child(total(s().total_assets, snapshot.assets))
                                                .child(total(s().total_debt, snapshot.debt)),
                                        )
                                        .child(
                                            row_button(|| nav::push(Route::AssetHistory))
                                                .accessibility_label(|| {
                                                    Some(s().asset_history.into())
                                                })
                                                .px_0()
                                                .min_h(px(44.0))
                                                .gap_3()
                                                .child(
                                                    text(if has_holdings {
                                                        s().valuation_recorded
                                                    } else {
                                                        s().valuation_book
                                                    })
                                                    .typo(Type::Subhead)
                                                    .text_color(color::MUTED)
                                                    .flex_1(),
                                                )
                                                .child(
                                                    text(|| s().asset_history)
                                                        .typo(Type::Subhead)
                                                        .text_color(color::INK),
                                                )
                                                .child(icon(
                                                    Icon::ChevronRight,
                                                    16.0,
                                                    color::MUTED,
                                                )),
                                        ),
                                )
                                .child(account_group(
                                    AccountKind::Assets,
                                    &accounts,
                                    &balances,
                                    &checks,
                                ))
                                .child(
                                    portfolio
                                        .securities
                                        .iter()
                                        .any(|sec| {
                                            portfolio
                                                .position(sec, today.0)
                                                .expect("validated holdings")
                                                .quantity
                                                > 0
                                        })
                                        .then(|| super::super::holdings::section(false)),
                                )
                                .child(account_group(
                                    AccountKind::Liabilities,
                                    &accounts,
                                    &balances,
                                    &checks,
                                ))
                                .into_element()
                        })
                    })),
            ),
        )
        .child(bottom_sheet(
            move || manage.get(),
            move || manage.set(false),
            view()
                .gap_2()
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .child(
                            text(|| s().manage_assets)
                                .typo(Type::Title)
                                .text_color(color::INK)
                                .flex_1(),
                        )
                        .child(
                            Btn::ghost()
                                .label(|| s().close.into())
                                .on_press(move || manage.set(false)),
                        ),
                )
                .child(menu_row(
                    || s().add_account,
                    move || {
                        manage.set(false);
                        create.set(true);
                    },
                ))
                .child(menu_row(
                    || s().add_holding,
                    move || {
                        manage.set(false);
                        holding.set(Some(String::new()));
                    },
                ))
                .child(menu_row(
                    || s().closed_holdings,
                    move || {
                        manage.set(false);
                        nav::push(Route::ClosedHoldings);
                    },
                )),
        ))
        .child(editor::account_editor(create, None))
        .child(super::super::holdings::trade_editor(holding))
}

fn menu_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px_0()
        .min_h(px(52.0))
        .gap_3()
        .child(text(label).typo(Type::Body).text_color(color::INK).flex_1())
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

fn account_group(
    kind: AccountKind,
    accounts: &[Account],
    balances: &std::collections::BTreeMap<Account, i64>,
    checks: &[finance_core::repository::BalanceCheck],
) -> Option<AnyElement> {
    let own: Vec<_> = accounts.iter().filter(|a| a.kind() == kind).collect();
    if own.is_empty() {
        return None;
    }
    Some(
        view()
            .gap_1()
            .child(
                text(if kind == AccountKind::Assets {
                    s().cash_accounts
                } else {
                    s().debt_accounts
                })
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(color::MUTED)
                .role(AccessibilityRole::Header),
            )
            .children(own.into_iter().map(|a| {
                let balance = balances.get(a).copied().unwrap_or(0);
                let checked = checks
                    .iter()
                    .filter(|c| c.account == *a)
                    .max_by_key(|c| c.checked_at);
                let detail = checked
                    .map(|c| format!("{} · {}", s().account_checked, s().short_date(Day(c.day))))
                    .unwrap_or_else(|| s().account_unchecked.into());
                let name = a.name().to_owned();
                let route = a.to_string();
                let value = assets::displayed(a, balance);
                let label = format!("{name}, {} CNY, {detail}", money::format(value));
                view().child(
                    row_button(move || nav::push(Route::Account(route.clone())))
                        .accessibility_label(move || Some(label.clone().into()))
                        .px_0()
                        .py_3()
                        .min_h(px(56.0))
                        .gap_3()
                        .child(icon(
                            if kind == AccountKind::Assets {
                                Icon::Wallet
                            } else {
                                Icon::Minus
                            },
                            22.0,
                            color::MUTED,
                        ))
                        .child(
                            view()
                                .flex_1()
                                .min_w(px(0.0))
                                .gap_1()
                                .child(
                                    text(name)
                                        .typo(Type::Headline)
                                        .text_color(color::INK)
                                        .number_of_lines(1),
                                )
                                .child(checked.is_none().then(|| {
                                    text(|| s().account_unchecked)
                                        .typo(Type::Caption)
                                        .text_color(color::MUTED)
                                })),
                        )
                        .child(amount(value, Type::Headline))
                        .child(icon(Icon::ChevronRight, 16.0, color::MUTED)),
                )
            }))
            .into_element(),
    )
}

fn total(label: &'static str, value: i64) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(amount(value, Type::Body))
}

fn net_figure(value: i64) -> impl IntoElement {
    let written = display_money(value);
    let (whole, fraction) = written.split_once('.').expect("money decimals");
    view()
        .flex_row()
        .items_baseline()
        .min_w(px(0.0))
        .accessible(true)
        .label(move || format!("¥{}", money::format(value)))
        .child(text("¥").typo(Type::Figure).text_color(color::MUTED).mr_1())
        .child(
            text(whole.to_owned())
                .typo(Type::Display)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(
            text(format!(".{fraction}"))
                .typo(Type::Title)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}
