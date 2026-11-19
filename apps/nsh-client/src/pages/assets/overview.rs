//! The asset overview is a scan of current values. History and maintenance
//! have explicit entries so neither interrupts the account/position list.
use super::overview_parts::*;
use super::*;
use crate::ui::{
    sheet::{fitted_task_sheet, task_host},
    surface::card,
};

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
                    .pb_4()
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
                                IconBtn::new(Icon::List, || s().manage_assets.into())
                                    .on_press(move || manage.set(true))
                                    .px_0(),
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
                                        Btn::primary().label(|| s().add_account.into()).on_press(
                                            move || {
                                                create.set(true);
                                                manage.set(true);
                                            },
                                        ),
                                    )
                                    .child(Btn::ghost().label(|| s().add_holding.into()).on_press(
                                        move || {
                                            holding.set(Some(String::new()));
                                            manage.set(true);
                                        },
                                    ))
                                    .into_element();
                            }
                            let valued = portfolio.overview_with_rates(&entries, today.0, &rates);
                            let Ok(valued) = valued else {
                                return text(crate::i18n::statement_import::copy(
                                    "Cannot convert these amounts. Check exchange rates.",
                                    "无法折算这些金额，请检查汇率。",
                                ))
                                .typo(Type::Body)
                                .text_color(color::DANGER)
                                .into_element();
                            };
                            let snapshot = valued.snapshot;
                            let incomplete = !valued.missing.is_empty();
                            let missing = valued
                                .missing
                                .iter()
                                .map(|c| c.code())
                                .collect::<Vec<_>>()
                                .join(" / ");
                            let mut has_open_holdings = false;
                            let mut has_included_holdings = false;
                            let mut at_cost = Vec::new();
                            for sec in &portfolio.securities {
                                let position = portfolio
                                    .position(sec, today.0)
                                    .expect("overview validated positions");
                                if position.quantity == 0 {
                                    continue;
                                }
                                has_open_holdings = true;
                                if !valued.missing.contains(&sec.currency()) {
                                    has_included_holdings = true;
                                    if position.value.is_none() {
                                        at_cost.push((sec.id.clone(), sec.name.clone()));
                                    }
                                }
                            }
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
                                            text(move || {
                                                if incomplete {
                                                    crate::i18n::statement_import::copy(
                                                        "Known value · CNY",
                                                        "已折算净值 · CNY",
                                                    )
                                                } else {
                                                    s().portfolio_net
                                                }
                                            })
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED),
                                        )
                                        .child(net_figure(snapshot.net))
                                        .child(super::mini::sparkline(
                                            &entries, &portfolio, &rates, today,
                                        ))
                                        .child((!at_cost.is_empty()).then(|| cost_details(at_cost)))
                                        .child(quote_refresh_row())
                                        .child(incomplete.then(|| {
                                            row_button(|| nav::push(Route::ExchangeRates))
                                                .px_0()
                                                .child(
                                                text(format!(
                                                    "{}: {missing}",
                                                    crate::i18n::statement_import::copy(
                                                        "Missing rates; these assets are excluded",
                                                        "缺少汇率，以下币种未计入"
                                                    )
                                                ))
                                                .typo(Type::Subhead)
                                                .text_color(color::DANGER),
                                            )
                                        }))
                                        .child(
                                            view()
                                                .flex_row()
                                                .style_when(
                                                    || {
                                                        font_scale() > 1.2
                                                            || window().width.0 < 350.0
                                                    },
                                                    |s| s.flex_col(),
                                                )
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
                                                .min_h(px(48.0))
                                                .gap_3()
                                                .child(
                                                    text(if has_included_holdings {
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
                                    has_open_holdings
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
        .child(task_host(
            move || manage.get(),
            move || manage.set(false),
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
                                            || {
                                                crate::i18n::statement_import::copy(
                                                    "Exchange rates",
                                                    "汇率",
                                                )
                                            },
                                            || s().manage_rates_note,
                                            Icon::Refresh,
                                            move || {
                                                manage.set(false);
                                                nav::push(Route::ExchangeRates);
                                            },
                                        ))
                                        .child(nav_row(
                                            || {
                                                crate::i18n::statement_import::copy(
                                                    "Price history",
                                                    "价格与汇率记录",
                                                )
                                            },
                                            || s().manage_prices_note,
                                            Icon::Chart,
                                            move || {
                                                manage.set(false);
                                                nav::push(Route::PriceHistory(None));
                                            },
                                        ))
                                        .child(nav_row(
                                            || s().closed_holdings,
                                            || s().manage_closed_note,
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
