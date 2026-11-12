use super::*;

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
    let category = signal(String::new());
    let search_open = signal(false);
    let kind: Signal<Option<RecordKind>> = signal(None);
    let account = nav.account;
    let limit = signal(50_i64);
    let days: Signal<Vec<Day>> = signal(Vec::new());
    let facts = loading::month_facts(services.clone(), month, version);
    let metadata = loading::metadata(services.clone(), version);
    let currencies = metadata.currencies;
    let account_options = metadata.options;
    let account_count = metadata.count;
    let totals = facts.totals;
    let budget_summary = facts.budgets;
    let composition = facts.composition;
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
            let category = category.get();
            let filter = RecordFilter {
                query: query.get(),
                kind: kind.get(),
                category_id: (!category.is_empty()).then_some(category),
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
                let records = visible_records(&services, filter, count + 1).await;
                if sequence.get() != generation {
                    return;
                }
                match records {
                    Ok(mut records) => {
                        has_more.set(records.len() > count as usize);
                        records.truncate(count as usize);
                        let next = group_days(records);
                        if !days.get_untracked().is_empty() && days.get_untracked() != next {
                            ui::animate_list_change();
                        }
                        days.set(next);
                        error.set(String::new());
                    }
                    Err(e) => error.set(e),
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
            ui::interactive_scroll().flex_1().child(
                view()
                    .px(move || px(ui::page_px()()))
                    .pb_5()
                    .gap_5()
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
                                .text_size(move || px(ui::token("type-body")))
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
                            ))
                            .child(ui::icon_button(
                                ui::Icon::More,
                                "流水管理",
                                "activity-tools",
                                move || tools_open.set(true),
                            )),
                    )
                    .child(when(
                        move || !totals.get().is_empty(),
                        move || {
                            fui::changed_fact(
                                "/activity".into(),
                                each(
                                    move || totals.get(),
                                    |t: &(String, Decimal, Decimal)| t.0.clone(),
                                    move |row: ReadSignal<(String, Decimal, Decimal)>, _| {
                                        let currency = row.get().0;
                                        view().child(
                                            view()
                                                .gap_3()
                                                .child(ui::quiet_text("本月支出"))
                                                .child(ui::amount_live(
                                                    move || {
                                                        ui::format_money(
                                                            row.get().2,
                                                            &row.get().0,
                                                            ui::MoneySign::Outflow,
                                                        )
                                                    },
                                                    currency,
                                                    "type-expense",
                                                ))
                                                .child(
                                                    text(move || {
                                                        format!(
                                                            "收入 {} · 结余 {}",
                                                            ui::format_money(
                                                                row.get().1,
                                                                &row.get().0,
                                                                ui::MoneySign::Inflow
                                                            ),
                                                            ui::money_for(
                                                                row.get().1 - row.get().2,
                                                                &row.get().0
                                                            )
                                                        )
                                                    })
                                                    .text_size(move || {
                                                        px(ui::token("type-caption"))
                                                    })
                                                    .tabular_nums()
                                                    .text_color(move || theme().muted_foreground),
                                                ),
                                        )
                                    },
                                ),
                            )
                        },
                    ))
                    .child(composition::render(composition))
                    .child(shortcuts::render(
                        category,
                        kind,
                        limit,
                        search_open,
                        metadata.categories,
                    ))
                    .child(
                        view()
                            .style_when(
                                move || !search_open.get() && query.get().is_empty(),
                                |s| s.hidden(),
                            )
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
                            .child(ui::icon_button(
                                ui::Icon::Close,
                                "关闭搜索",
                                "ledger-search-close",
                                move || {
                                    query.set(String::new());
                                    search_open.set(false);
                                    limit.set(50);
                                },
                            )),
                    )
                    .child(when(
                        move || {
                            kind.get().is_some()
                                || !account.get().is_empty()
                                || all_dates.get()
                                || !category.get().is_empty()
                        },
                        move || {
                            view()
                                .flex_row()
                                .items_center()
                                .gap_2()
                                .child(
                                    text(move || {
                                        let mut labels = Vec::new();
                                        if !category.get().is_empty() {
                                            labels.push(
                                                metadata
                                                    .categories
                                                    .get()
                                                    .iter()
                                                    .find(|c| c.id == category.get())
                                                    .map(|c| c.name.clone())
                                                    .unwrap_or_else(|| "分类".into()),
                                            );
                                        }
                                        if let Some(kind) = kind.get() {
                                            labels.push(kind.label().to_owned());
                                        }
                                        if !account.get().is_empty()
                                            && let Some(option) = account_options
                                                .get()
                                                .into_iter()
                                                .find(|o| o.value == account.get())
                                        {
                                            labels.push(option.label);
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
                                        category.set(String::new());
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
                    .child(
                        view()
                            .test_id("ledger-composition-error")
                            .child(ui::error_line(facts.composition_error))
                            .style_when(
                                move || facts.composition_error.get().is_empty(),
                                |s| s.hidden(),
                            ),
                    )
                    .child(ui::error_line(facts.error))
                    .child(ui::error_line(metadata.error))
                    .child(when(
                        move || {
                            !error.get().is_empty()
                                || !facts.composition_error.get().is_empty()
                                || !facts.error.get().is_empty()
                                || !metadata.error.get().is_empty()
                        },
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
                        move || loading.get() && days.get().is_empty(),
                        ui::skeleton,
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
                            view()
                                .min_h(px(220.0))
                                .justify_center()
                                .child(empty)
                                .child(when(
                                    move || account_count.get() > 0,
                                    move || {
                                        ui::primary_button(
                                            "记下第一笔",
                                            move || {
                                                edit_id.set(None);
                                                editor.set(true);
                                            },
                                            "ledger-empty-record",
                                            None,
                                        )
                                    },
                                ))
                                .child(when(
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
                                        record_row(record, selected, currencies)
                                    },
                                ))
                        },
                    ))
                    .child(budget::module(budget_summary))
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
        .child(overlays::overlays(
            tools_open,
            filters_open,
            account_options,
            account,
            all_dates,
            kinds,
        ))
        .child(record_detail(
            services.clone(),
            selected,
            editor,
            edit_id,
            version,
        ))
        .child(crate::screens::record::record_editor(
            services,
            editor,
            version,
            edit_id,
            "/activity",
        ))
}
