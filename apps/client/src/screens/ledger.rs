//! Finance workspace: dated activity, exact monthly totals, filtering and record management.
use crate::{
    finance::{FinanceRecord, RecordFilter, RecordKind, RecordSource},
    finance_ui as fui,
    state::Services,
    ui,
};
use chrono::{Datelike, Local, NaiveDate};
use naviwealth_finance::wealth::OperationKind;
use nsh_base::{SheetEvent, dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{cell::Cell, rc::Rc, sync::Arc};

fn month_window(offset: i32) -> (i64, i64, String) {
    month_window_for(Local::now().date_naive(), offset)
}
fn month_window_for(today: NaiveDate, offset: i32) -> (i64, i64, String) {
    let index = today.year() * 12 + today.month0() as i32 + offset;
    let year = index.div_euclid(12);
    let month = index.rem_euclid(12) as u32 + 1;
    let start = chrono::NaiveDate::from_ymd_opt(year, month, 1)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp();
    let end = chrono::NaiveDate::from_ymd_opt(
        if month == 12 { year + 1 } else { year },
        if month == 12 { 1 } else { month + 1 },
        1,
    )
    .unwrap()
    .and_hms_opt(0, 0, 0)
    .unwrap()
    .and_utc()
    .timestamp();
    (start, end, format!("{year} 年 {month} 月"))
}
#[derive(Clone, PartialEq)]
struct Day {
    date: String,
    records: Vec<FinanceRecord>,
}
fn group_days(records: Vec<FinanceRecord>) -> Vec<Day> {
    let mut days: Vec<Day> = Vec::new();
    for record in records {
        let date = ui::ymd(record.date);
        if days.last().is_none_or(|d| d.date != date) {
            days.push(Day {
                date,
                records: Vec::new(),
            });
        }
        days.last_mut().unwrap().records.push(record);
    }
    days
}

// The repository deliberately bounds each page. Accumulate pages for the visible
// window so "load more" never treats that bound as the end of the user's history.
async fn visible_records(
    services: &Services,
    filter: RecordFilter,
    count: i64,
) -> Result<Vec<FinanceRecord>, String> {
    let mut records = Vec::new();
    while records.len() < count as usize {
        let take = (count - records.len() as i64).min(200);
        let page = services
            .finance_records(filter.clone(), take, records.len() as i64)
            .await?;
        let exhausted = page.len() < take as usize;
        records.extend(page);
        if exhausted {
            break;
        }
    }
    Ok(records)
}

#[allow(non_snake_case)]
pub fn LedgerScreen() -> impl IntoElement {
    let services = use_context::<Arc<Services>>().expect("services");
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    let nav = use_context::<crate::FinanceNavigation>().expect("finance navigation");
    let month = signal(0_i32);
    let all_dates = nav.all_dates;
    let query = signal(String::new());
    let kind: Signal<Option<RecordKind>> = signal(None);
    let account = nav.account;
    let limit = signal(50_i64);
    let days: Signal<Vec<Day>> = signal(Vec::new());
    let totals: Signal<Vec<(String, Decimal, Decimal)>> = signal(Vec::new());
    let budget_summary = signal(Vec::<(String, u8)>::new());
    let account_options = signal(Vec::<(String, String)>::new());
    let account_count = signal(0_usize);
    let loading = signal(true);
    let error = signal(String::new());
    let has_more = signal(false);
    let selected: Signal<Option<FinanceRecord>> = signal(None);
    let editor = signal(false);
    let edit_id: Signal<Option<String>> = signal(None);
    let sequence = Rc::new(Cell::new(0_u64));
    // The workspace capture button opens this pane's editor in place.
    let intent = use_context::<crate::CaptureIntent>()
        .expect("capture intent")
        .0;
    let tab = use_context::<crate::ShellTab>().expect("tab").0;
    let seen_intent = signal(intent.get_untracked());
    effect(move || {
        let now = intent.get();
        if now != seen_intent.get_untracked() {
            seen_intent.set(now);
            if tab.get() == 1 {
                edit_id.set(None);
                editor.set(true);
            }
        }
    });
    {
        let services = services.clone();
        effect(move || {
            version.get();
            let (from, until, _) = month_window(month.get());
            let count = limit.get();
            let filter = RecordFilter {
                query: query.get(),
                kind: kind.get(),
                account_id: if account.get().is_empty() {
                    None
                } else {
                    Some(account.get())
                },
                from: if all_dates.get() { None } else { Some(from) },
                until: if all_dates.get() { None } else { Some(until) },
            };
            let generation = sequence.get() + 1;
            sequence.set(generation);
            let sequence = sequence.clone();
            loading.set(true);
            let services = services.clone();
            spawn(async move {
                let (records, monthly, accounts, budgets) = tokio::join!(
                    visible_records(&services, filter, count + 1),
                    services.finance_monthly_totals(from, until),
                    services.finance_accounts(false),
                    services.finance_budgets(ui::ymd(from)[..7].to_owned())
                );
                if sequence.get() != generation {
                    return;
                }
                budget_summary.set(match budgets {
                    Ok(budgets) => {
                        let mut currencies =
                            std::collections::BTreeMap::<String, (Decimal, Decimal)>::new();
                        let mut overflow = false;
                        for budget in budgets {
                            let row = currencies.entry(budget.budget.currency).or_default();
                            if let (Some(spent), Some(limit)) = (
                                row.0.checked_add(budget.spent),
                                row.1.checked_add(budget.budget.limit),
                            ) {
                                *row = (spent, limit);
                            } else {
                                overflow = true;
                                break;
                            }
                        }
                        if overflow {
                            vec![("预算合计超出范围，请查看分类明细".into(), 2)]
                        } else {
                            currencies
                                .into_iter()
                                .map(|(currency, (spent, limit))| {
                                    // Normal progress reads in the investment
                                    // data role; near-limit and over-budget
                                    // escalate with the explicit wording.
                                    let ratio = if limit > Decimal::ZERO {
                                        spent.checked_div(limit).unwrap_or(Decimal::MAX)
                                    } else {
                                        Decimal::ZERO
                                    };
                                    let status = if ratio >= Decimal::ONE {
                                        2_u8
                                    } else if ratio >= Decimal::new(9, 1) {
                                        1
                                    } else {
                                        0
                                    };
                                    (
                                        format!(
                                            "分类预算 · {currency}  已用 {} / {}{}",
                                            ui::money(spent),
                                            ui::money(limit),
                                            match status {
                                                1 => " · 接近上限",
                                                2 => " · 已达或超出预算",
                                                _ => "",
                                            }
                                        ),
                                        status,
                                    )
                                })
                                .collect()
                        }
                    }
                    Err(_) => vec![("预算暂不可用，点此重新查看".into(), 2)],
                });
                match (records, monthly, accounts) {
                    (Ok(mut records), Ok(monthly), Ok(accounts)) => {
                        has_more.set(records.len() > count as usize);
                        records.truncate(count as usize);
                        days.set(group_days(records));
                        totals.set(monthly);
                        account_count.set(accounts.len());
                        let mut options = vec![(String::new(), "全部账户".to_owned())];
                        options.extend(accounts.into_iter().map(|(a, _)| (a.id, a.name)));
                        account_options.set(options);
                        error.set(String::new());
                    }
                    (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => error.set(e),
                }
                loading.set(false);
            });
        });
    }
    let kinds = view().flex_row().gap_2().children(
        [
            (None, "全部"),
            (Some(RecordKind::Expense), "支出"),
            (Some(RecordKind::Income), "收入"),
            (Some(RecordKind::Transfer), "转账"),
            (Some(RecordKind::Investment), "投资"),
        ]
        .map(|(value, label)| {
            ui::choice_button(
                label,
                move || kind.get() == value,
                move || {
                    kind.set(value);
                    limit.set(50);
                },
                format!("ledger-kind-{label}"),
            )
            .flex_1()
        }),
    );
    let filters_open = signal(false);
    let tools_open = signal(false);
    view()
        .flex_1()
        .child(
            view()
                .px_4()
                .min_h(px(52.0))
                .flex_row()
                .items_center()
                .gap_3()
                .child(
                    text("流水")
                        .text_size(px(22.0))
                        .font_weight(FontWeight::SEMIBOLD)
                        .flex_1(),
                )
                .child(fui::action("管理", "activity-tools", move || {
                    tools_open.set(true)
                })),
        )
        .child(
            ui::interactive_scroll().flex_1().child(
                view()
                    .px_4()
                    .pb_5()
                    .gap_2()
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_2()
                            .child(
                                text(move || {
                                    if all_dates.get() {
                                        "全部时间".to_owned()
                                    } else {
                                        month_window(month.get()).2
                                    }
                                })
                                .text_lg()
                                .font_weight(FontWeight::MEDIUM)
                                .flex_1(),
                            )
                            .child(ui::icon_button(
                                ui::Icon::Back,
                                "上月",
                                "ledger-prev-month",
                                move || {
                                    month.update(|v| *v -= 1);
                                    all_dates.set(false);
                                },
                            ))
                            .child(ui::icon_button(
                                ui::Icon::Arrow,
                                "下月",
                                "ledger-next-month",
                                move || {
                                    month.update(|v| *v += 1);
                                    all_dates.set(false);
                                },
                            )),
                    )
                    .child(when(
                        move || !totals.get().is_empty(),
                        move || {
                            fui::changed_fact(
                                "/activity".into(),
                                view().py_1().gap_2().child(each(
                                    move || totals.get(),
                                    |t: &(String, Decimal, Decimal)| t.0.clone(),
                                    move |row: ReadSignal<(String, Decimal, Decimal)>, _| {
                                        let (currency, _, _) = row.get();
                                        view()
                                            .flex_row()
                                            .gap_4()
                                            .child(
                                                view()
                                                    .flex_1()
                                                    .gap_1()
                                                    .child(
                                                        text(format!("本月收入 · {currency}"))
                                                            .text_sm()
                                                            .text_color(move || {
                                                                theme().muted_foreground
                                                            }),
                                                    )
                                                    .child(
                                                        text(move || ui::money(row.get().1))
                                                            .text_color(fui::gain)
                                                            .text_size(px(20.0))
                                                            .tabular_nums()
                                                            .font_weight(FontWeight::MEDIUM),
                                                    ),
                                            )
                                            .child(
                                                view()
                                                    .flex_1()
                                                    .gap_1()
                                                    .child(
                                                        text(format!("本月支出 · {currency}"))
                                                            .text_sm()
                                                            .text_color(move || {
                                                                theme().muted_foreground
                                                            }),
                                                    )
                                                    .child(
                                                        text(move || ui::money(row.get().2))
                                                            .text_color(|| theme().destructive)
                                                            .text_size(px(29.0))
                                                            .tabular_nums()
                                                            .font_weight(FontWeight::MEDIUM),
                                                    ),
                                            )
                                    },
                                )),
                            )
                        },
                    ))
                    .child(when(
                        move || !budget_summary.get().is_empty(),
                        move || {
                            view()
                                .role(AccessibilityRole::Button)
                                .min_h(px(48.0))
                                .on_press(|| fui::navigate("/plan/budgets"))
                                .test_id("ledger-budget-context")
                                .children(budget_summary.get().into_iter().map(|(line, status)| {
                                    text(line).text_size(px(12.0)).tabular_nums().text_color(
                                        move || match status {
                                            1 => fui::warning(),
                                            2 => theme().destructive,
                                            _ => fui::data_investment(),
                                        },
                                    )
                                }))
                        },
                    ))
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_3()
                            .child(
                                view()
                                    .flex_1()
                                    .flex_row()
                                    .items_center()
                                    .gap_2()
                                    .px_3()
                                    .bg(move || theme().card)
                                    .rounded(px(12.0))
                                    .child(
                                        ui::icon(ui::Icon::Search)
                                            .text_color(move || theme().muted_foreground),
                                    )
                                    .child(
                                        ui::themed_input()
                                            .value(query)
                                            .on_change(move |v: &str| {
                                                query.set(v.to_owned());
                                                limit.set(50);
                                            })
                                            .placeholder("搜索商家或备注")
                                            .text_base()
                                            .h(px(50.0))
                                            .flex_1()
                                            .test_id("ledger-search"),
                                    ),
                            )
                            .child(ui::secondary_button(
                                "筛选",
                                move || filters_open.set(true),
                                "ledger-filters",
                                None,
                            )),
                    )
                    .child(when(
                        move || {
                            kind.get().is_some() || !account.get().is_empty() || all_dates.get()
                        },
                        move || {
                            view()
                                .flex_row()
                                .items_center()
                                .gap_2()
                                .child(
                                    text(move || {
                                        let mut labels = Vec::new();
                                        if let Some(kind) = kind.get() {
                                            labels.push(kind.label().to_owned());
                                        }
                                        if !account.get().is_empty()
                                            && let Some((_, name)) = account_options
                                                .get()
                                                .into_iter()
                                                .find(|(id, _)| *id == account.get())
                                        {
                                            labels.push(name);
                                        }
                                        if all_dates.get() {
                                            labels.push("全部时间".to_owned());
                                        }
                                        labels.join(" · ")
                                    })
                                    .text_sm()
                                    .text_color(move || theme().muted_foreground)
                                    .flex_1(),
                                )
                                .child(ui::secondary_button(
                                    "清除筛选",
                                    move || {
                                        kind.set(None);
                                        account.set(String::new());
                                        all_dates.set(false);
                                        limit.set(50);
                                    },
                                    "ledger-reset-filters",
                                    None,
                                ))
                        },
                    ))
                    .child(ui::error_line(error))
                    .child(when(
                        move || !error.get().is_empty(),
                        move || {
                            ui::secondary_button(
                                "重新加载",
                                move || version.update(|v| *v += 1),
                                "ledger-retry",
                                Some(loading),
                            )
                        },
                    ))
                    .child(when(
                        move || loading.get(),
                        || {
                            text("正在读取流水…")
                                .text_sm()
                                .text_color(move || theme().muted_foreground)
                        },
                    ))
                    .child(when(
                        move || !loading.get() && days.get().is_empty() && error.get().is_empty(),
                        move || {
                            let empty = ui::empty_state(
                                if account_count.get() == 0 {
                                    "从一个账户开始"
                                } else {
                                    "这里还没有记录"
                                },
                                if account_count.get() == 0 {
                                    "添加现金、银行卡或信用卡，即可开始记账。"
                                } else {
                                    "试试调整筛选条件，或记下第一笔收支。"
                                },
                            );
                            view().child(empty).child(when(
                                move || account_count.get() == 0,
                                move || {
                                    ui::primary_button(
                                        "添加账户",
                                        move || {
                                            fui::navigate("/wealth/accounts/new");
                                        },
                                        "ledger-add-account",
                                        None,
                                    )
                                },
                            ))
                        },
                    ))
                    .child(each(
                        move || days.get(),
                        |day: &Day| day.date.clone(),
                        move |day: ReadSignal<Day>, _| {
                            view()
                                .gap_2()
                                .child(
                                    text(day.get().date)
                                        .text_sm()
                                        .font_weight(FontWeight::MEDIUM)
                                        .text_color(move || theme().muted_foreground),
                                )
                                .child(each(
                                    move || day.get().records,
                                    |record: &FinanceRecord| record.id.clone(),
                                    move |record: ReadSignal<FinanceRecord>, _| {
                                        record_row(record, selected)
                                    },
                                ))
                        },
                    ))
                    .child(when(
                        move || has_more.get(),
                        move || {
                            ui::secondary_button(
                                "加载更多",
                                move || limit.update(|v| *v += 50),
                                "ledger-load-more",
                                Some(loading),
                            )
                        },
                    )),
            ),
        )
        .child(
            ui::app_sheet()
                .open(move || Some(tools_open.get()))
                .on_open_change(move |e: &SheetEvent| {
                    if let SheetEvent::OpenChange(next, _) = e {
                        tools_open.set(*next);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_2()
                        .bg(move || theme().background)
                        .child(text("流水管理").text_lg().font_weight(FontWeight::SEMIBOLD))
                        .children(
                            [
                                ("导入账单", "/activity/import", "activity-import"),
                                ("账户对账", "/activity/reconcile", "activity-reconcile"),
                                ("月结复核", "/activity/close", "activity-close"),
                            ]
                            .map(move |(label, path, id)| {
                                fui::action(label, id, move || {
                                    tools_open.set(false);
                                    fui::navigate(path);
                                })
                            }),
                        )
                        .child(fui::action("取消", "activity-tools-cancel", move || {
                            tools_open.set(false)
                        })),
                ),
        )
        .child(
            ui::app_sheet()
                .open(move || Some(filters_open.get()))
                .on_open_change(move |e: &SheetEvent| {
                    if let SheetEvent::OpenChange(next, _) = e {
                        filters_open.set(*next);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_4()
                        .bg(move || theme().background)
                        .child(text("筛选流水").text_lg().font_weight(FontWeight::SEMIBOLD))
                        .child(kinds)
                        .child(view().bg(move || theme().card).rounded(px(12.0)).child(
                            ui::select_field("账户", account_options, account, "ledger-account"),
                        ))
                        .child(
                            view()
                                .flex_row()
                                .gap_2()
                                .child(
                                    ui::choice_button(
                                        "所选月份",
                                        move || !all_dates.get(),
                                        move || all_dates.set(false),
                                        "ledger-month-only",
                                    )
                                    .flex_1(),
                                )
                                .child(
                                    ui::choice_button(
                                        "全部时间",
                                        move || all_dates.get(),
                                        move || all_dates.set(true),
                                        "ledger-all-dates",
                                    )
                                    .flex_1(),
                                ),
                        )
                        .child(ui::primary_button(
                            "完成",
                            move || filters_open.set(false),
                            "ledger-filters-done",
                            None,
                        )),
                ),
        )
        .child(record_detail(
            services.clone(),
            selected,
            editor,
            edit_id,
            version,
        ))
        .child(super::record::record_editor(
            services,
            editor,
            version,
            edit_id,
            "/activity",
        ))
}
fn record_row(
    record: ReadSignal<FinanceRecord>,
    selected: Signal<Option<FinanceRecord>>,
) -> impl IntoElement {
    dynamic(move || record_row_content(record.get(), selected))
}
fn record_row_content(
    item: FinanceRecord,
    selected: Signal<Option<FinanceRecord>>,
) -> impl IntoElement {
    let pressed = item.clone();
    let id = format!("record-{}", item.id);
    let icon = match item.kind {
        RecordKind::Expense => ui::Icon::Expense,
        RecordKind::Income => ui::Icon::Income,
        RecordKind::Transfer => ui::Icon::Transfer,
        _ => ui::Icon::Wallet,
    };
    let title = record_title(&item);
    let detail = record_accounts(&item);
    let signed = record_value(&item);
    view()
        .role(AccessibilityRole::Button)
        .label(format!("{title}，{detail}，{signed} {}", item.currency))
        .test_id(&id)
        .on_press(move || {
            if pressed.source != RecordSource::Daily && pressed.source != RecordSource::Other {
                fui::navigate(format!("/activity/entry/{}", pressed.id));
            } else {
                selected.set(Some(pressed.clone()));
            }
        })
        .min_h(px(64.0))
        .px_2()
        .py_3()
        .flex_row()
        .items_center()
        .gap_3()
        .border_b_1()
        .border_color(move || theme().border)
        .active(|s| s.opacity(0.75))
        .focus(|s| {
            s.outline(px(2.0))
                .outline_color(move || theme().ring)
                .outline_offset(px(-2.0))
        })
        .child(fui::record_highlight(&item.id))
        .child(
            ui::icon(icon)
                .w(px(20.0))
                .h(px(20.0))
                .flex_shrink_0()
                .text_color(move || theme().muted_foreground),
        )
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(
                    text(title)
                        .text_size(px(15.0))
                        .truncate()
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(
                    text(detail)
                        .truncate()
                        .text_sm()
                        .text_color(move || theme().muted_foreground),
                ),
        )
        .child(
            view()
                .flex_shrink_0()
                .gap_1()
                .items_end()
                .child(
                    text(signed)
                        .text_color(move || fui::record_color(item.kind))
                        .text_size(px(15.0))
                        .tabular_nums()
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(
                    text(item.currency)
                        .text_xs()
                        .text_color(move || theme().muted_foreground),
                ),
        )
}
fn record_title(record: &FinanceRecord) -> String {
    let identity = record
        .payee
        .clone()
        .or(record.category_name.clone())
        .unwrap_or_else(|| record.kind.label().to_owned());
    match record.investment_kind {
        Some(kind) => format!("{} · {identity}", kind.label()),
        None => identity,
    }
}
fn record_accounts(record: &FinanceRecord) -> String {
    match (record.kind, record.destination_account_name.as_deref()) {
        (RecordKind::Investment, Some(cash)) => {
            format!("结算 {cash} · 持仓 {}", record.account_name)
        }
        (RecordKind::Investment, None) => format!("持仓 {}", record.account_name),
        (RecordKind::Transfer, Some(destination)) => {
            format!("{} → {destination}", record.account_name)
        }
        _ => record.account_name.clone(),
    }
}
fn record_value(record: &FinanceRecord) -> String {
    match (record.kind, record.investment_kind) {
        (_, Some(OperationKind::Opening)) => format!("成本 {}", ui::money(record.amount)),
        (_, Some(OperationKind::Split)) => format!("现金 {}", ui::money(record.amount)),
        (RecordKind::Expense, _) => format!("-{}", ui::money(record.amount)),
        (RecordKind::Income, _) => format!("+{}", ui::money(record.amount)),
        (RecordKind::Investment, _) if record.amount > Decimal::ZERO => {
            format!("+{}", ui::money(record.amount))
        }
        _ => ui::money(record.amount),
    }
}
fn detail_line(label: &'static str, value: String) -> impl Element {
    view()
        .flex_row()
        .gap_4()
        .py_3()
        .child(
            text(label)
                .text_base()
                .text_color(move || theme().muted_foreground),
        )
        .child(text(value).text_base().flex_1())
}

pub fn capture_route() -> AnyElement {
    let open = signal(true);
    let version = use_context::<crate::state::DataVersion>()
        .expect("version")
        .0;
    effect(move || {
        if !open.get() {
            fui::back();
        }
    });
    view()
        .flex_1()
        .child(super::record::record_dialog(
            fui::services(),
            open,
            version,
            "/activity",
        ))
        .into_element()
}
pub fn entry_route(id: String) -> AnyElement {
    let record = signal(None::<FinanceRecord>);
    let source = signal(None::<String>);
    let error = signal(String::new());
    let version = use_context::<crate::state::DataVersion>()
        .expect("version")
        .0;
    let editor = signal(false);
    let edit_id = signal(Some(id.clone()));
    let services = fui::services();
    let s = services.clone();
    effect(move || {
        version.get();
        let s = s.clone();
        let id = id.clone();
        spawn(async move {
            match s.finance_record(&id).await {
                Ok(v) => {
                    record.set(Some(v));
                    error.set(String::new());
                }
                Err(e) => error.set(e),
            }
            match s.finance_record_source_route(id).await {
                Ok(path) => source.set(path),
                Err(e) => error.set(e),
            }
        });
    });
    fui::page(
        "流水详情",
        view()
            .gap_4()
            .child(ui::error_line(error))
            .child(dynamic(move || {
                let Some(r) = record.get() else {
                    return text("正在读取记录…").text_sm().into_element();
                };
                let mut body = view().gap_3().child(fui::metric(
                    r.investment_kind
                        .map_or(r.kind.label(), OperationKind::label)
                        .into(),
                    format!("{} {}", record_value(&r), r.currency),
                    ui::ymd(r.date),
                ));
                if r.investment_kind.is_some() {
                    body = body
                        .child(detail_line("资产", r.payee.unwrap_or_default()))
                        .child(detail_line("持仓账户", r.account_name))
                        .child(detail_line(
                            "结算账户",
                            r.destination_account_name
                                .unwrap_or_else(|| "无现金结算".into()),
                        ));
                } else {
                    body = body
                        .child(detail_line("账户", r.account_name))
                        .child(detail_line(
                            "分类 / 去向",
                            r.category_name
                                .or(r.destination_account_name)
                                .unwrap_or_default(),
                        ))
                        .child(detail_line("对方", r.payee.unwrap_or_default()));
                }
                body = body.child(detail_line("备注", r.note.unwrap_or_default()));
                if let Some(path) = source.get() {
                    body = body
                        .child(
                            text("这笔流水由专属流程生成，请在来源中修改或撤销。")
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(fui::action(
                            "查看来源与处理记录",
                            "entry-source",
                            move || fui::navigate(path.clone()),
                        ));
                }
                if r.editable {
                    let id = r.id.clone();
                    body = body
                        .child(fui::action("编辑记录", "entry-edit", move || {
                            editor.set(true)
                        }))
                        .child(fui::confirm(
                            "删除这笔记录？".into(),
                            "确认后会重新计算账户余额与分类预算；删除后 60 秒内可撤销。".into(),
                            "删除记录".into(),
                            "entry-delete",
                            move || {
                                let s = fui::services();
                                let id = id.clone();
                                Box::pin(async move {
                                    s.delete_finance_record(&id).await?;
                                    fui::offer_undo(id, "这笔记录已删除", fui::UndoAction::Restore);
                                    Ok(Some("/activity".into()))
                                })
                            },
                        ));
                }
                body.into_element()
            }))
            .child(super::record::record_editor(
                services,
                editor,
                version,
                edit_id,
                "/activity",
            )),
    )
}
fn record_detail(
    services: Arc<Services>,
    selected: Signal<Option<FinanceRecord>>,
    editor: Signal<bool>,
    edit_id: Signal<Option<String>>,
    version: Signal<u64>,
) -> impl IntoElement {
    let confirm = signal(false);
    let busy = signal(false);
    let error = signal(String::new());
    when(
        move || selected.get().is_some(),
        move || {
            let record = selected.get().unwrap();
            let delete_services = services.clone();
            let record_id = record.id.clone();
            let edit = record.id.clone();
            let editable = record.editable;
            let received = record.destination_amount;
            let received_currency = record.destination_currency.clone().unwrap_or_default();
            let show_received = record.kind == RecordKind::Transfer
                && !received_currency.is_empty()
                && received_currency != record.currency;
            dialog()
                .on_cancel(move || selected.set(None))
                .flex_1()
                .bg(move || theme().background)
                .child(view().px_5().pt_safe_area_plus(px(12.0)).pb_3().child(
                    ui::secondary_button(
                        "返回",
                        move || selected.set(None),
                        "record-detail-close",
                        None,
                    ),
                ))
                .child(
                    ui::interactive_scroll().flex_1().child(
                        view()
                            .p_5()
                            .gap_4()
                            .child(
                                text(record.kind.label())
                                    .text_xl()
                                    .font_weight(FontWeight::SEMIBOLD),
                            )
                            .child(
                                text(format!("{} {}", record.currency, ui::money(record.amount)))
                                    .text_size(px(34.0))
                                    .tabular_nums(),
                            )
                            .child(
                                view()
                                    .bg(move || theme().card)
                                    .rounded(px(16.0))
                                    .px_4()
                                    .child(detail_line("日期", ui::ymd(record.date)))
                                    .child(ui::divider())
                                    .child(detail_line("账户", record.account_name))
                                    .child(ui::divider())
                                    .child(detail_line(
                                        "分类 / 去向",
                                        record
                                            .category_name
                                            .or(record.destination_account_name)
                                            .unwrap_or_else(|| record.kind.label().to_owned()),
                                    ))
                                    .child(when(
                                        move || show_received,
                                        move || {
                                            detail_line(
                                                "实际到账",
                                                format!(
                                                    "{} {}",
                                                    received_currency,
                                                    ui::money(received.unwrap_or_default())
                                                ),
                                            )
                                        },
                                    ))
                                    .child(detail_line(
                                        "对方",
                                        record.payee.unwrap_or_else(|| "未填写".to_owned()),
                                    ))
                                    .child(detail_line(
                                        "备注",
                                        record.note.unwrap_or_else(|| "未填写".to_owned()),
                                    )),
                            )
                            .child(ui::error_line(error))
                            .child(when(
                                move || editable,
                                move || {
                                    let edit = edit.clone();
                                    ui::primary_button(
                                        "编辑记录",
                                        move || {
                                            selected.set(None);
                                            edit_id.set(Some(edit.clone()));
                                            editor.set(true);
                                        },
                                        "record-edit",
                                        None,
                                    )
                                },
                            ))
                            .child(when(
                                move || !editable,
                                || {
                                    text("这类记录暂不支持在此修改，可查看详情或删除。")
                                        .text_sm()
                                        .text_color(move || theme().muted_foreground)
                                },
                            ))
                            .child(ui::secondary_button(
                                "删除记录",
                                move || confirm.set(true),
                                "record-delete",
                                Some(busy),
                            )),
                    ),
                )
                .child(
                    ui::app_sheet()
                        .open(move || Some(confirm.get()))
                        .on_open_change(move |e: &SheetEvent| {
                            if let SheetEvent::OpenChange(next, _) = e {
                                confirm.set(*next);
                            }
                        })
                        .child(
                            view()
                                .p_5()
                                .pb_safe_area_plus(px(20.0))
                                .gap_4()
                                .bg(move || theme().background)
                                .child(
                                    text("删除这笔记录？")
                                        .text_lg()
                                        .font_weight(FontWeight::SEMIBOLD),
                                )
                                .child(
                                    text("相关账户余额会同步更新；删除后 60 秒内可撤销。")
                                        .text_base()
                                        .text_color(move || theme().muted_foreground),
                                )
                                .child(ui::secondary_button(
                                    "保留记录",
                                    move || confirm.set(false),
                                    "record-delete-cancel",
                                    Some(busy),
                                ))
                                .child(ui::danger_button(
                                    "确认删除",
                                    move || {
                                        if busy.get() {
                                            return;
                                        }
                                        busy.set(true);
                                        let services = delete_services.clone();
                                        let id = record_id.clone();
                                        spawn(async move {
                                            match services.delete_finance_record(&id).await {
                                                Ok(()) => {
                                                    confirm.set(false);
                                                    selected.set(None);
                                                    version.update(|v| *v += 1);
                                                    fui::offer_undo(
                                                        id,
                                                        "这笔记录已删除",
                                                        fui::UndoAction::Restore,
                                                    );
                                                }
                                                Err(e) => {
                                                    confirm.set(false);
                                                    error.set(e);
                                                }
                                            }
                                            busy.set(false);
                                        });
                                    },
                                    "record-delete-confirm",
                                    busy,
                                )),
                        ),
                )
        },
    )
}

#[cfg(test)]
mod calendar_tests {
    use super::*;
    #[test]
    fn local_month_is_not_previous_utc_month_at_midnight() {
        let local = chrono::DateTime::parse_from_rfc3339("2026-12-01T00:30:00+08:00").unwrap();
        let (from, until, label) = month_window_for(local.date_naive(), 0);
        assert_eq!(label, "2026 年 12 月");
        assert_eq!(ui::ymd(from), "2026-12-01");
        assert_eq!(ui::ymd(until), "2027-01-01");
        assert_eq!(month_window_for(local.date_naive(), -1).2, "2026 年 11 月");
    }
}
