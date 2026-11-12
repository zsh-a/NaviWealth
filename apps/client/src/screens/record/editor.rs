use super::*;

pub fn record_dialog(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
    source: &'static str,
) -> impl IntoElement {
    record_editor(services, open, reload, signal(None), source)
}
pub fn record_editor(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
    edit: Signal<Option<String>>,
    source: &'static str,
) -> impl IntoElement {
    let state = Form::new();
    when(
        move || open.get(),
        move || {
            state.load(services.clone(), edit.get());
            let cancel = state.clone();
            let title = if edit.get().is_some() {
                "编辑记录"
            } else {
                "记一笔"
            };
            let fields_state = state.clone();
            let fields_services = services.clone();
            let submit = state.clone();
            let save_services = services.clone();
            let submit_edit = edit;
            let submit_open = open;
            let submit_reload = reload;
            let submit_source = source;
            let submit_action = move || {
                submit.submit(
                    save_services.clone(),
                    submit_edit.get(),
                    submit_open,
                    submit_reload,
                    submit_source,
                )
            };
            let fields_submit = submit_action.clone();
            let cancel_button = state.clone();
            let guard = state.clone();
            let close = state.clone();
            let entrance = ui::enter_offset();
            dialog()
                .on_cancel(move || cancel.cancel(open))
                .flex_1()
                .bg(move || hsla(0.0, 0.0, 0.0, ui::token("opacity-scrim")))
                .pt_safe_area_plus(px(32.0))
                .child(
                    view()
                        .flex_1()
                        .bind_translate_y(&entrance)
                        .rounded(move || px(ui::token("radius-sheet")))
                        .overflow_hidden()
                        .bg(move || theme().background)
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_3()
                                .px_5()
                                .pt_safe_area_plus(px(12.0))
                                .pb_3()
                                .child(ui::text_button(
                                    "取消",
                                    "record-cancel",
                                    move || cancel_button.cancel(open),
                                    false,
                                ))
                                .child(
                                    text(title)
                                        .text_center()
                                        .text_size(move || px(ui::token("type-section")))
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .flex_1(),
                                )
                                .child(view().w(px(52.0))),
                        )
                        .child(
                            ui::interactive_scroll().flex_1().child(
                                view()
                                    .px(move || px(ui::page_px()()))
                                    .pb(px(32.0))
                                    .gap_4()
                                    .child(when(move || state.loading.get(), ui::skeleton))
                                    .child(when(
                                        move || !state.loading.get(),
                                        move || {
                                            form_fields(
                                                fields_state.clone(),
                                                fields_services.clone(),
                                                fields_submit.clone(),
                                            )
                                        },
                                    )),
                            ),
                        )
                        .child(
                            view()
                                .bg(move || theme().background)
                                .px(move || px(ui::page_px()()))
                                .pt_3()
                                .pb_safe_area_plus(px(16.0))
                                .child(ui::primary_button(
                                    "保存记录",
                                    submit_action,
                                    "record-save",
                                    Some(state.saving),
                                )),
                        )
                        .child(
                            ui::app_sheet()
                                .open(move || Some(guard.discard.get()))
                                .on_open_change(move |e: &SheetEvent| {
                                    if let SheetEvent::OpenChange(next, _) = e {
                                        close.discard.set(*next);
                                    }
                                })
                                .child(
                                    view()
                                        .p_5()
                                        .pb_safe_area_plus(px(20.0))
                                        .gap_4()
                                        .bg(move || theme().background)
                                        .child(
                                            text("放弃未保存的修改？")
                                                .text_lg()
                                                .font_weight(FontWeight::SEMIBOLD),
                                        )
                                        .child(
                                            text("返回后，本次填写的内容将不会保存。")
                                                .text_base()
                                                .text_color(move || theme().muted_foreground),
                                        )
                                        .child(ui::primary_button(
                                            "继续填写",
                                            move || state.discard.set(false),
                                            "record-keep",
                                            None,
                                        ))
                                        .child(ui::text_button(
                                            "放弃修改",
                                            "record-discard",
                                            move || {
                                                state.discard.set(false);
                                                open.set(false);
                                            },
                                            true,
                                        )),
                                ),
                        ),
                )
        },
    )
}

fn form_fields(
    state: Form,
    services: Arc<Services>,
    submit_action: impl Fn() + Clone + 'static,
) -> impl IntoElement {
    let budget_state = state.clone();
    let budget_services = services.clone();
    effect(move || {
        let month = budget_state
            .date
            .get()
            .get(..7)
            .unwrap_or_default()
            .to_owned();
        let s = budget_services.clone();
        let state = budget_state.clone();
        spawn(async move {
            if let Ok(budgets) = s.finance_budgets(month.clone()).await
                && state.date.get_untracked().starts_with(&month)
            {
                state.budgets.set(budgets);
            }
        });
    });
    let source = state.clone();
    let cross = state.clone();
    let received_currency = state.clone();
    let received = state.received;
    let dest = state.clone();
    let kind_state = state.clone();
    let keyboard_kind = state.kind;
    let amount_state = state.clone();
    let amount_currency = state.clone();
    let amount_submit = submit_action.clone();
    let payee_submit = submit_action.clone();
    let note_submit = submit_action.clone();

    view()
        .test_id("record-ready")
        .gap_4()
        .child(when(
            move || state.kind.get() != RecordKind::OpeningBalance,
            move || {
                let state = kind_state.clone();
                let services = services.clone();
                kind_switch(state, services)
            },
        ))
        .child(
            view()
                .gap_2()
                .py_1()
                .child(
                    text(move || format!("{}金额", amount_currency.kind.get().label()))
                        .text_size(move || px(ui::token("type-caption")))
                        .text_color(move || theme().muted_foreground)
                        .child(text(move || {
                            format!(
                                " · {}",
                                amount_currency.currency(&amount_currency.account.get())
                            )
                        })),
                )
                .child(
                    view().flex_row().items_center().child(
                        ui::money_input(amount_state.amount, move || {
                            amount_state.currency(&amount_state.account.get())
                        })
                        .on_submit(move |_: &str| amount_submit())
                        .keyboard_type(move || {
                            if keyboard_kind.get() == RecordKind::OpeningBalance {
                                KeyboardType::Numeric
                            } else {
                                KeyboardType::Decimal
                            }
                        })
                        .text_size(move || px(crate::ui::token("type-amount-input")))
                        .font_weight(FontWeight::NORMAL)
                        .tabular_nums()
                        .font_family(ui::number_font)
                        .letter_spacing(move || px(ui::token("tracking-display")))
                        .placeholder_color(move || color(theme().muted_foreground))
                        .h(move || px(64.0 * font_scale()))
                        .flex_1()
                        .test_id("record-amount"),
                    ),
                ),
        )
        .child(when(
            move || state.accounts.get().is_empty() && !state.loading.get(),
            || {
                ui::empty_state(
                    "先添加一个账户",
                    "前往账户页添加现金、银行卡或信用卡，再回来记一笔。",
                )
            },
        ))
        .child(
            view()
                .bg(move || theme().background)
                .child(ui::compact_select_field(
                    "账户",
                    state.accounts,
                    state.account,
                    "record-account",
                ))
                .child(view().h(px(0.0)))
                .child(when(
                    move || {
                        source.kind.get() != RecordKind::Transfer
                            && source.kind.get() != RecordKind::OpeningBalance
                    },
                    move || category_grid(source.clone()),
                ))
                .child(when(
                    move || dest.kind.get() == RecordKind::Transfer,
                    move || {
                        ui::select_field(
                            "转入账户",
                            dest.accounts,
                            dest.destination,
                            "record-destination",
                        )
                    },
                )),
        )
        .child(when(
            move || cross.cross_currency(),
            move || {
                let currency_state = received_currency.clone();
                ui::money_field(
                    "实际到账金额",
                    "转入账户币种的金额",
                    received,
                    "record-received",
                    move || currency_state.currency(&currency_state.destination.get()),
                )
            },
        ))
        .child(crate::finance_ui::compact_date_field(
            "日期",
            "record-date",
            state.date,
        ))
        .child(inline_field(
            "对方",
            "商家或付款方",
            state.payee,
            "record-payee",
            payee_submit,
        ))
        .child(inline_field(
            "备注",
            "添加备注",
            state.note,
            "record-note",
            note_submit,
        ))
        .child(ui::error_line(state.error))
}

fn kind_switch(state: Form, services: Arc<Services>) -> impl IntoElement {
    nsh_base::tabs()
        .flex_row()
        .p_1()
        .rounded_lg()
        .bg(move || theme().muted)
        .indicator_style(|s| {
            s.top(px(4.0))
                .bottom(px(4.0))
                .rounded_md()
                .bg(move || theme().card)
                .shadow_sm()
        })
        .children(
            [
                RecordKind::Expense,
                RecordKind::Income,
                RecordKind::Transfer,
            ]
            .map(|kind| {
                let state = state.clone();
                let services = services.clone();
                let selected = state.kind;
                nsh_base::tab()
                    .selected(move || selected.get() == kind)
                    .on_press(move |_: &()| {
                        state.kind.set(kind);
                        state.categories(services.clone());
                    })
                    .flex_1()
                    .min_h(px(44.0))
                    .items_center()
                    .justify_center()
                    .child(
                        view()
                            .test_id(&format!("record-kind-{}", kind.label()))
                            .items_center()
                            .justify_center()
                            .w_full()
                            .h_full()
                            .child(text(kind.label()).text_sm().font_weight(FontWeight::MEDIUM)),
                    )
            }),
        )
}

fn inline_field(
    label: &'static str,
    placeholder: &'static str,
    value: Signal<String>,
    id: &'static str,
    submit: impl Fn() + 'static,
) -> impl Element {
    view()
        .flex_row()
        .items_center()
        .gap_4()
        .child(ui::quiet_text(label))
        .child(
            ui::themed_input()
                .test_id(id)
                .label(label)
                .value(value)
                .on_change(move |v: &str| value.set(v.to_owned()))
                .on_submit(move |_: &str| submit())
                .placeholder(placeholder)
                .text_size(move || px(ui::token("type-body")))
                .text_right()
                .flex_1()
                .min_h(move || px(ui::token("control-height"))),
        )
}
