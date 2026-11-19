//! The asset overview is a scan of current values. History and maintenance
//! have explicit entries so neither interrupts the account/position list.
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
                                                .min_h(px(44.0))
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

/// A create action: an ink chip around its glyph, its name and a scope note.
fn action_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    note: impl Fn() -> &'static str + Copy + 'static,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px(px(space::CARD))
        .rounded(px(radius::FIELD))
        .min_h(px(64.0))
        .gap_3()
        .child(
            view()
                .w(px(32.0))
                .h(px(32.0))
                .rounded_full()
                .bg(color::INK)
                .items_center()
                .justify_center()
                .child(icon(glyph, 18.0, color::ON_ACTION)),
        )
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(label).typo(Type::Headline).text_color(color::INK))
                .child(text(note).typo(Type::Subhead).text_color(color::MUTED)),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

/// A data entry: a quiet glyph, its name and a scope note.
fn nav_row(
    label: impl Fn() -> &'static str + Copy + 'static,
    note: impl Fn() -> &'static str + Copy + 'static,
    glyph: Icon,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .px(px(space::CARD))
        .rounded(px(radius::FIELD))
        .min_h(px(52.0))
        .gap_3()
        .child(icon(glyph, 20.0, color::MUTED))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(text(label).typo(Type::Headline).text_color(color::INK))
                .child(text(note).typo(Type::Subhead).text_color(color::MUTED)),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
}

fn account_group(
    kind: AccountKind,
    accounts: &[Account],
    balances: &std::collections::BTreeMap<Account, i64>,
    checks: &[navi_finance::repository::BalanceCheck],
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
                let name = crate::ui::currency::account_label(a);
                let route = a.to_string();
                let value = assets::displayed(a, balance);
                let label = format!(
                    "{name}, {} {}, {detail}",
                    money::format(value),
                    a.currency().code()
                );
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
                                .flex_row()
                                .items_center()
                                .gap_3()
                                .style_when(
                                    || font_scale() > 1.2 || window().width.0 < 350.0,
                                    |s| s.flex_col().items_start().gap_1(),
                                )
                                .child(
                                    view()
                                        .flex_1()
                                        .min_w(px(0.0))
                                        .gap_1()
                                        .style_when(
                                            || font_scale() > 1.2 || window().width.0 < 350.0,
                                            |s| s.w_full(),
                                        )
                                        .child(
                                            text(name)
                                                .typo(Type::Headline)
                                                .text_color(color::INK)
                                                .number_of_lines(1),
                                        )
                                        .child(
                                            text(detail)
                                                .typo(Type::Caption)
                                                .text_color(color::MUTED),
                                        ),
                                )
                                .child(
                                    view().min_w(px(0.0)).flex_shrink(1.0_f32).child(amount_in(
                                        value,
                                        Type::Headline,
                                        a.currency(),
                                    )),
                                ),
                        )
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
        .flex_wrap()
        .min_w(px(0.0))
        .accessible(true)
        .label(move || format!("¥{}", money::format(value)))
        .child(text("¥").typo(Type::Figure).text_color(color::MUTED).mr_1())
        .child(
            text(whole.to_owned())
                .typo(Type::Display)
                .min_w(px(0.0))
                .flex_shrink(1.0_f32)
                .number_of_lines(1)
                .shrink_to_fit(0.35)
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

fn cost_details(items: Vec<(String, String)>) -> impl IntoElement {
    let expanded = signal(false);
    let count = items.len();
    view()
        .child(
            row_button(move || expanded.update(|v| *v = !*v))
                .px_0()
                .min_h(px(44.0))
                .child(
                    text(move || s().cost_holdings(count))
                        .typo(Type::Subhead)
                        .text_color(color::BODY),
                )
                .child(dynamic(move || {
                    icon(
                        if expanded.get() {
                            Icon::ChevronDown
                        } else {
                            Icon::ChevronRight
                        },
                        16.0,
                        color::MUTED,
                    )
                    .into_element()
                })),
        )
        .child(when(
            move || expanded.get(),
            move || {
                view()
                    .test_id("cost-holdings")
                    .children(items.iter().cloned().map(|(id, name)| {
                        row_button(move || nav::push(Route::Holding(id.clone())))
                            .child(text(name).typo(Type::Body).text_color(color::INK))
                    }))
            },
        ))
}

fn quote_refresh_row() -> impl IntoElement {
    when(
        || {
            let book = finance::holdings_snapshot();
            let bindings = crate::data::catalog::bindings();
            finance::accounts()
                .iter()
                .any(|a| a.is_cash() && a.currency() != navi_finance::currency::Currency::CNY)
                || book.securities.iter().any(|sec| {
                    (sec.currency() != navi_finance::currency::Currency::CNY
                        || bindings.iter().any(|b| b.security == sec.id))
                        && book
                            .position(sec, clock::today().0)
                            .is_ok_and(|p| p.quantity > 0)
                })
        },
        || {
            let expanded = signal(false);
            view()
                .gap_1()
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .style_when(
                            || font_scale() > 1.2 || window().width.0 < 350.0,
                            |s| s.flex_col().items_start(),
                        )
                        .gap_3()
                        .child(dynamic(move || {
                            let status = crate::data::market::status();
                            let summary = if let Some(at) = status.completed_at {
                                let ms = at.as_millisecond();
                                let time = format!(
                                    "{} {}",
                                    s().short_date(crate::domain::meal::Day(
                                        clock::zoned(ms).date()
                                    )),
                                    clock::time_label(ms)
                                );
                                s().refresh_summary(&time, status.updated, status.failed)
                            } else {
                                crate::i18n::catalog::copy("Prices and FX", "价格与汇率").to_owned()
                            };
                            let caption =
                                text(summary).typo(Type::Caption).text_color(color::MUTED);
                            if status.failed_items.is_empty() {
                                caption.flex_1().into_element()
                            } else {
                                row_button(move || expanded.update(|open| *open = !*open))
                                    .px_0()
                                    .min_h(px(44.0))
                                    .flex_1()
                                    .child(caption)
                                    .child(icon(
                                        if expanded.get() {
                                            Icon::ChevronDown
                                        } else {
                                            Icon::ChevronRight
                                        },
                                        16.0,
                                        color::MUTED,
                                    ))
                                    .into_element()
                            }
                        }))
                        .child(
                            Btn::ghost()
                                .size(crate::ui::Size::Small)
                                .label(|| {
                                    if crate::data::market::status().refreshing {
                                        s().refreshing_quotes()
                                    } else {
                                        s().refresh_quotes()
                                    }
                                    .into()
                                })
                                .disabled(|| crate::data::market::status().refreshing)
                                .on_press(move || {
                                    expanded.set(false);
                                    crate::data::tasks::spawn_app(crate::data::market::refresh(
                                        true,
                                    ))
                                }),
                        ),
                )
                .child(when(
                    move || {
                        expanded.get() && !crate::data::market::status().failed_items.is_empty()
                    },
                    || {
                        text(|| crate::data::market::status().failed_items.join(" · "))
                            .typo(Type::Caption)
                            .text_color(color::BODY)
                    },
                ))
        },
    )
}
