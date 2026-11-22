//! The asset overview is a scan of current values. History and maintenance
//! have explicit entries so neither interrupts the account/position list.
use super::overview_parts::*;
use super::summary::net_summary;
use super::*;
use crate::ui::sheet::{fitted_task_sheet, task_host_with_keyboard};

pub fn assets_tab() -> impl IntoElement {
    let manage = signal(false);
    let create = signal(false);
    let holding = signal(None::<String>);
    let task = signal(0u8);
    effect(move || {
        if manage.get() {
            task.set(if create.get() {
                1
            } else if holding.get().is_some() {
                2
            } else {
                0
            });
        }
    });
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        crate::preview::assets_opened(manage, holding);
        if holding.get_untracked().is_some() {
            manage.set(true);
        }
    }
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
                                    .on_press(move || manage.set(true))
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
                        let rates = finance::rates_snapshot();
                        let today = clock::today();
                        let overview = super::current::get();
                        untracked(move || {
                            if accounts.is_empty() && portfolio.securities.is_empty() {
                                return crate::ui::feedback::empty_state(Icon::Wallet, || {
                                    s().assets_empty.into()
                                })
                                .note(|| s().assets_empty_body.into())
                                .action(
                                    view()
                                        .items_center()
                                        .gap_2()
                                        .child(
                                            Btn::primary()
                                                .label(|| s().add_account.into())
                                                .on_press(move || {
                                                    create.set(true);
                                                    manage.set(true);
                                                }),
                                        )
                                        .child(
                                            Btn::ghost().label(|| s().add_holding.into()).on_press(
                                                move || {
                                                    holding.set(Some(String::new()));
                                                    manage.set(true);
                                                },
                                            ),
                                        ),
                                )
                                .into_element();
                            }
                            let Some(overview) = overview else {
                                return text(crate::i18n::statement_import::copy(
                                    "Cannot convert these amounts. Check exchange rates.",
                                    "无法折算这些金额，请检查汇率。",
                                ))
                                .typo(Type::Body)
                                .text_color(color::DANGER)
                                .into_element();
                            };
                            view()
                                .gap_5()
                                .child(net_summary(
                                    overview.clone(),
                                    super::trend::NetWorthHistory::load(
                                        &entries, &portfolio, &rates, today,
                                    ),
                                ))
                                .child(account_group(
                                    AccountKind::Assets,
                                    &accounts,
                                    &overview.balances,
                                    &checks,
                                ))
                                .child(
                                    overview
                                        .has_open_holdings
                                        .then(|| super::super::holdings::section(false)),
                                )
                                .child(account_group(
                                    AccountKind::Liabilities,
                                    &accounts,
                                    &overview.balances,
                                    &checks,
                                ))
                                .into_element()
                        })
                    })),
            ),
        )
        .child(task_host_with_keyboard(
            move || manage.get(),
            move || manage.set(false),
            move || task.get() == 1,
            move || {
                dynamic(move || {
                    let panel = task.get();
                    untracked(move || match panel {
                        1 => editor::account_task(create, None, move || manage.set(false))
                            .into_element(),
                        2 => super::super::holdings::trade_task(holding, move || manage.set(false))
                            .into_element(),
                        _ => fitted_task_sheet(
                            move || manage.get(),
                            move || manage.set(false),
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
                                    IconBtn::new(Icon::Close, || s().close.into())
                                        .on_press(move || manage.set(false)),
                                ),
                            view()
                                .gap_3()
                                .child(
                                    view()
                                        .gap_1()
                                        .child(group_label(|| s().manage_group_create))
                                        .child(action_row(
                                            || s().add_account,
                                            || s().manage_add_account_note,
                                            Icon::Wallet,
                                            move || create.set(true),
                                        ))
                                        .child(action_row(
                                            || s().add_holding,
                                            || s().manage_add_holding_note,
                                            Icon::Plus,
                                            move || holding.set(Some(String::new())),
                                        )),
                                )
                                .child(
                                    view()
                                        .gap_1()
                                        .child(group_label(|| s().manage_group_data))
                                        .child(nav_row(
                                            super::super::prices_and_rates::title,
                                            Icon::Chart,
                                            move || {
                                                manage.set(false);
                                                nav::push(Route::PricesAndRates(None));
                                            },
                                        ))
                                        .child(nav_row(
                                            || s().closed_holdings,
                                            Icon::Bookmark,
                                            move || {
                                                manage.set(false);
                                                nav::push(Route::ClosedHoldings);
                                            },
                                        )),
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
