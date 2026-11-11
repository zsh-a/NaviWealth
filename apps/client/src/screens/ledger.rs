//! Finance workspace: dated activity, exact monthly totals, filtering and record management.
use crate::{
    finance::{FinanceRecord, RecordFilter, RecordKind},
    state::Services,
    ui,
};
use chrono::{Datelike, Local, NaiveDate};
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
    let account_options = signal(Vec::<(String, String)>::new());
    let account_count = signal(0_usize);
    let loading = signal(true);
    let error = signal(String::new());
    let has_more = signal(false);
    let selected: Signal<Option<FinanceRecord>> = signal(None);
    let editor = signal(false);
    let edit_id: Signal<Option<String>> = signal(None);
    let sequence = Rc::new(Cell::new(0_u64));
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
                let result = tokio::join!(
                    visible_records(&services, filter, count + 1),
                    services.finance_monthly_totals(from, until),
                    services.finance_accounts(false)
                );
                if sequence.get() != generation {
                    return;
                }
                match result {
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
    let add = move || {
        edit_id.set(None);
        editor.set(true);
    };
    view()
        .flex_1()
        .child(
            view()
                .px_5()
                .pt_5()
                .pb_4()
                .flex_row()
                .items_center()
                .gap_3()
                .child(ui::page_title("流水", "收入 · 支出 · 转账").flex_1())
                .child(ui::primary_button("记一笔", add, "open-record", None)),
        )
        .child(
            ui::interactive_scroll().flex_1().child(
                view()
                    .px_5()
                    .pb_5()
                    .gap_4()
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
                            view()
                                .bg(move || theme().card)
                                .rounded(px(16.0))
                                .px_4()
                                .py_3()
                                .gap_3()
                                .child(each(
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
                                                            .text_size(px(22.0))
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
                                                            .text_size(px(22.0))
                                                            .tabular_nums()
                                                            .font_weight(FontWeight::MEDIUM),
                                                    ),
                                            )
                                    },
                                ))
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
                                            if let Some(tab) = use_context::<crate::ShellTab>() {
                                                tab.0.set(0);
                                            }
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
                                .child(view().bg(move || theme().card).rounded(px(16.0)).child(
                                    each(
                                        move || day.get().records,
                                        |record: &FinanceRecord| record.id.clone(),
                                        move |record: ReadSignal<FinanceRecord>, _| {
                                            record_row(record, selected)
                                        },
                                    ),
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
            services, editor, version, edit_id,
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
    let title = item
        .payee
        .clone()
        .or(item.category_name.clone())
        .unwrap_or_else(|| item.kind.label().to_owned());
    let detail = if let Some(destination) = &item.destination_account_name {
        format!("{} → {destination}", item.account_name)
    } else {
        item.account_name.clone()
    };
    let signed = match item.kind {
        RecordKind::Expense => format!("-{}", ui::money(item.amount)),
        RecordKind::Income => format!("+{}", ui::money(item.amount)),
        _ => ui::money(item.amount),
    };
    view()
        .role(AccessibilityRole::Button)
        .test_id(&id)
        .on_press(move || selected.set(Some(pressed.clone())))
        .min_h(px(80.0))
        .px_4()
        .py_3()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            view()
                .w(px(40.0))
                .h(px(40.0))
                .flex_shrink_0()
                .items_center()
                .justify_center()
                .rounded(px(12.0))
                .bg(move || theme().muted)
                .child(ui::icon(icon)),
        )
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(
                    text(title)
                        .text_base()
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
                        .text_lg()
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
                                    text("相关账户余额会同步更新。此操作无法撤销。")
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
