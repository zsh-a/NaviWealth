use super::*;

pub(super) fn detail_line(label: &'static str, value: String) -> impl Element {
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
        .child(crate::screens::record::record_dialog(
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
            .child(crate::screens::record::record_editor(
                services,
                editor,
                version,
                edit_id,
                "/activity",
            )),
    )
}
pub(super) fn record_detail(
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
                                text(format!("{} {}", record_value(&record), record.currency))
                                    .text_size(move || px(ui::token("type-record")))
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
                                                    ui::money_for(
                                                        received.unwrap_or_default(),
                                                        &received_currency
                                                    ),
                                                    received_currency
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
