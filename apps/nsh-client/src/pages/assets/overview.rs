//! The asset overview is a scan of current values. History and maintenance
//! have explicit entries so neither interrupts the account/position list.
use super::overview_parts::*;
use super::summary::net_summary;
use super::*;
use crate::ui::sheet::{fitted_task_sheet, task_host_with_keyboard};

#[derive(Clone, Copy, PartialEq)]
enum Panel {
    Menu,
    Account,
    Holding,
}

pub fn assets_tab() -> impl IntoElement {
    let menu = signal(false);
    let create = signal(false);
    let holding = signal(None::<String>);
    let panel = signal(Panel::Menu);
    let typing_account = signal(true);
    let sheet_open = move || {
        (menu.get() || create.get() || holding.with(Option::is_some))
            && nav::tab() == nav::Tab::Assets
            && nav::open().is_empty()
    };
    let finish = move || {
        batch(|| {
            menu.set(false);
            create.set(false);
            holding.set(None);
        })
    };
    effect(move || {
        // Keep the last panel mounted while the sheet animates out. Only a
        // task entered through Manage has a menu to return to.
        if create.get() {
            panel.set(Panel::Account);
        } else if holding.with(Option::is_some) {
            panel.set(Panel::Holding);
        } else if menu.get() {
            panel.set(Panel::Menu);
        }
    });
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::assets_opened(menu, holding);
    view()
        .flex_1()
        .child(
            scroll().flex_1().child(
                view()
                    .px(px(space::GUTTER))
                    .pt_safe_area_plus(px(12.0))
                    .pb(move || px(crate::pages::home::dock_top_inset() + 12.0))
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
                                    .on_press(move || menu.set(true))
                                    .accessibility_label(|| Some(s().manage_assets.into()))
                                    .min_h(px(48.0)),
                            ),
                    )
                    .child(dynamic(move || {
                        let accounts: Vec<_> = finance::accounts()
                            .into_iter()
                            .filter(Account::is_cash)
                            .collect();
                        let entries = finance::transactions_snapshot();
                        let portfolio = finance::holdings_snapshot();
                        let checks = finance::checks_snapshot();
                        let archived = finance::archived_accounts();
                        let rates = finance::rates_snapshot();
                        let today = clock::today();
                        let overview = super::current::get();
                        untracked(move || {
                            if accounts.iter().all(|a| archived.contains(a))
                                && entries.is_empty()
                                && checks.is_empty()
                                && portfolio.securities.is_empty()
                            {
                                return crate::ui::feedback::empty_state(Icon::Wallet, || {
                                    s().assets_empty.into()
                                })
                                .action(
                                    view()
                                        .items_center()
                                        .gap_2()
                                        .child(
                                            Btn::primary()
                                                .label(|| s().add_account.into())
                                                .on_press(move || {
                                                    create.set(true);
                                                }),
                                        )
                                        .child(
                                            Btn::ghost().label(|| s().add_holding.into()).on_press(
                                                move || {
                                                    holding.set(Some(String::new()));
                                                },
                                            ),
                                        ),
                                )
                                .into_element();
                            }
                            let Some(overview) = overview else {
                                return text(crate::i18n::statement_import::copy(
                                    "Valuation unavailable",
                                    "估值暂不可用",
                                ))
                                .typo(Type::Body)
                                .text_color(color::DANGER)
                                .into_element();
                            };
                            view()
                                .gap_5()
                                .child(
                                    (!overview.balances.is_empty()
                                        || !checks.is_empty()
                                        || !portfolio.securities.is_empty())
                                    .then(|| {
                                        net_summary(
                                            overview.clone(),
                                            super::trend::NetWorthHistory::load(
                                                &entries, &portfolio, &rates, today,
                                            ),
                                        )
                                    }),
                                )
                                .child(account_group(
                                    AccountKind::Assets,
                                    &accounts,
                                    &overview.balances,
                                    &checks,
                                    &archived,
                                ))
                                .child(
                                    overview
                                        .has_open_holdings
                                        .then(super::super::holdings::section),
                                )
                                .child(account_group(
                                    AccountKind::Liabilities,
                                    &accounts,
                                    &overview.balances,
                                    &checks,
                                    &archived,
                                ))
                                .into_element()
                        })
                    })),
            ),
        )
        .child(task_host_with_keyboard(
            sheet_open,
            finish,
            move || panel.get() == Panel::Account && typing_account.get(),
            move || {
                dynamic(move || {
                    let panel = panel.get();
                    untracked(move || match panel {
                        Panel::Account => {
                            editor::account_task(create, None, typing_account, finish)
                                .into_element()
                        }
                        Panel::Holding => {
                            super::super::holdings::trade_task(holding, finish).into_element()
                        }
                        Panel::Menu => fitted_task_sheet(
                            sheet_open,
                            finish,
                            view()
                                .flex_row()
                                .items_center()
                                .child(
                                    text(|| s().manage_assets)
                                        .typo(Type::Title)
                                        .text_color(color::INK)
                                        .flex_1()
                                        .role(AccessibilityRole::Header),
                                )
                                .child(
                                    IconBtn::new(Icon::Close, || s().close.into()).on_press(finish),
                                ),
                            view()
                                .gap_4()
                                .child(
                                    view()
                                        .child(manage_row(
                                            || s().add_account,
                                            Some(|| s().manage_add_account_note),
                                            None,
                                            Icon::Wallet,
                                            move || create.set(true),
                                        ))
                                        .child(manage_row(
                                            || s().add_holding,
                                            Some(|| s().manage_add_holding_note),
                                            None,
                                            Icon::Plus,
                                            move || holding.set(Some(String::new())),
                                        )),
                                )
                                .child(
                                    view()
                                        .child(manage_row(
                                            super::super::prices_and_rates::title,
                                            None,
                                            None,
                                            Icon::Chart,
                                            || nav::push(Route::PricesAndRates(None)),
                                        ))
                                        .child(dynamic(move || {
                                            let count = finance::archived_accounts().len();
                                            (count > 0).then(|| {
                                                manage_row(
                                                    lifecycle::archived_title,
                                                    None,
                                                    Some(count),
                                                    Icon::Wallet,
                                                    || nav::push(Route::ArchivedAccounts),
                                                )
                                            })
                                        }))
                                        .child(dynamic(move || {
                                            let count =
                                                super::super::holdings::closed_holdings().len();
                                            if count == 0 {
                                                return view().into_element();
                                            }
                                            manage_row(
                                                || s().closed_holdings,
                                                None,
                                                Some(count),
                                                Icon::List,
                                                || nav::push(Route::ClosedHoldings),
                                            )
                                            .into_element()
                                        })),
                                ),
                            view(),
                        )
                        .into_element(),
                    })
                })
                .into_element()
            },
        ))
}
