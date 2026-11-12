//! Income, expense and transfer capture share one guarded full-page editor.
use crate::{
    finance::{RecordDraft, RecordKind},
    state::Services,
    ui,
};
use nsh_base::{SheetEvent, dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Clone)]
struct Form {
    kind: Signal<RecordKind>,
    date: Signal<String>,
    amount: Signal<String>,
    account: Signal<String>,
    destination: Signal<String>,
    received: Signal<String>,
    category: Signal<String>,
    payee: Signal<String>,
    note: Signal<String>,
    accounts: Signal<Vec<(String, String)>>,
    categories: Signal<Vec<(String, String)>>,
    currencies: Signal<Vec<(String, String)>>,
    loading: Signal<bool>,
    saving: Signal<bool>,
    error: Signal<String>,
    baseline: Signal<String>,
    discard: Signal<bool>,
}
impl Form {
    fn new() -> Self {
        Self {
            kind: signal(RecordKind::Expense),
            date: signal(ui::today_text()),
            amount: signal(String::new()),
            account: signal(String::new()),
            destination: signal(String::new()),
            received: signal(String::new()),
            category: signal(String::new()),
            payee: signal(String::new()),
            note: signal(String::new()),
            accounts: signal(Vec::new()),
            categories: signal(Vec::new()),
            currencies: signal(Vec::new()),
            loading: signal(true),
            saving: signal(false),
            error: signal(String::new()),
            baseline: signal(String::new()),
            discard: signal(false),
        }
    }
    fn signature(&self) -> String {
        format!(
            "{:?}|{}|{}|{}|{}|{}|{}|{}|{}",
            self.kind.get(),
            self.date.get(),
            self.amount.get(),
            self.account.get(),
            self.destination.get(),
            self.received.get(),
            self.category.get(),
            self.payee.get(),
            self.note.get()
        )
    }
    fn cancel(&self, open: Signal<bool>) {
        if self.saving.get() {
            return;
        }
        if !self.loading.get() && self.signature() != self.baseline.get() {
            self.discard.set(true);
        } else {
            open.set(false);
        }
    }
    fn currency(&self, account: &str) -> String {
        self.currencies.with(|v| {
            v.iter()
                .find(|(id, _)| id == account)
                .map(|(_, c)| c.clone())
                .unwrap_or_else(|| "CNY".to_owned())
        })
    }
    fn cross_currency(&self) -> bool {
        self.kind.get() == RecordKind::Transfer
            && !self.destination.get().is_empty()
            && self.currency(&self.account.get()) != self.currency(&self.destination.get())
    }
    fn categories(&self, services: Arc<Services>) {
        let state = self.clone();
        let kind = self.kind.get();
        spawn(async move {
            match services.finance_categories(kind).await {
                Ok(items) if state.kind.get() == kind => {
                    if !items.iter().any(|(id, _)| *id == state.category.get()) {
                        state
                            .category
                            .set(items.first().map(|v| v.0.clone()).unwrap_or_default());
                    }
                    state.categories.set(items);
                }
                Err(e) => state.error.set(e),
                _ => {}
            }
        });
    }
    fn load(&self, services: Arc<Services>, edit: Option<String>) {
        let state = self.clone();
        self.loading.set(true);
        self.error.set(String::new());
        spawn(async move {
            let result: Result<(), String> = async {
                state.kind.set(RecordKind::Expense);
                state.date.set(ui::today_text());
                for value in [
                    state.amount,
                    state.account,
                    state.destination,
                    state.received,
                    state.category,
                    state.payee,
                    state.note,
                ] {
                    value.set(String::new());
                }
                let editing = edit.is_some();
                let mut original_category = None;
                if let Some(id) = edit {
                    let record = services.finance_record(&id).await?;
                    original_category =
                        record.category_id.clone().zip(record.category_name.clone());
                    state.kind.set(record.kind);
                    state.date.set(ui::ymd(record.date));
                    state.amount.set(record.amount.normalize().to_string());
                    state.account.set(record.account_id);
                    state
                        .destination
                        .set(record.destination_account_id.unwrap_or_default());
                    state.received.set(
                        record
                            .destination_amount
                            .map(|v| v.normalize().to_string())
                            .unwrap_or_default(),
                    );
                    state.category.set(record.category_id.unwrap_or_default());
                    state.payee.set(record.payee.unwrap_or_default());
                    state.note.set(record.note.unwrap_or_default());
                }
                let accounts = services.finance_accounts(editing).await?;
                let accounts: Vec<_> = accounts
                    .into_iter()
                    .filter(|(a, _)| {
                        !a.archived
                            || a.id == state.account.get()
                            || a.id == state.destination.get()
                    })
                    .collect();
                state.currencies.set(
                    accounts
                        .iter()
                        .map(|(a, _)| (a.id.clone(), a.currency.clone()))
                        .collect(),
                );
                let items: Vec<_> = accounts
                    .into_iter()
                    .map(|(a, _)| {
                        (
                            a.id,
                            format!(
                                "{} · {}{}",
                                a.name,
                                a.currency,
                                if a.archived { " · 已归档" } else { "" }
                            ),
                        )
                    })
                    .collect();
                if state.account.get().is_empty() {
                    state
                        .account
                        .set(items.first().map(|v| v.0.clone()).unwrap_or_default());
                }
                if state.destination.get().is_empty() {
                    state.destination.set(
                        items
                            .iter()
                            .find(|v| v.0 != state.account.get())
                            .map(|v| v.0.clone())
                            .unwrap_or_default(),
                    );
                }
                state.accounts.set(items);
                let mut categories = services.finance_categories(state.kind.get()).await?;
                if let Some(original) = original_category
                    && !categories.iter().any(|(id, _)| *id == original.0)
                {
                    categories.push(original);
                }
                if state.category.get().is_empty() {
                    state
                        .category
                        .set(categories.first().map(|v| v.0.clone()).unwrap_or_default());
                }
                state.categories.set(categories);
                Ok(())
            }
            .await;
            if let Err(e) = result {
                state.error.set(e);
            }
            state.baseline.set(state.signature());
            state.loading.set(false);
        });
    }
    fn submit(
        &self,
        services: Arc<Services>,
        edit: Option<String>,
        open: Signal<bool>,
        reload: Signal<u64>,
        source: &'static str,
    ) {
        if self.saving.get() || self.loading.get() {
            return;
        }
        let amount = match Decimal::from_str(self.amount.get().trim()) {
            Ok(v)
                if v > Decimal::ZERO
                    || (self.kind.get() == RecordKind::OpeningBalance && v != Decimal::ZERO) =>
            {
                v
            }
            _ => {
                self.error
                    .set("请输入有效金额，收入、支出和转账金额须大于 0".to_owned());
                return;
            }
        };
        let Some(date) = ui::date_to_secs(&self.date.get()) else {
            self.error.set("请输入有效日期，例如 2026-11-11".to_owned());
            return;
        };
        let received = if self.cross_currency() {
            match self.received.get().trim().parse::<Decimal>() {
                Ok(v) if v > Decimal::ZERO => Some(v),
                _ => {
                    self.error.set("请输入实际到账金额".to_owned());
                    return;
                }
            }
        } else {
            None
        };
        let optional = |v: String| {
            if v.trim().is_empty() {
                None
            } else {
                Some(v.trim().to_owned())
            }
        };
        let draft = RecordDraft {
            kind: self.kind.get(),
            date,
            amount,
            account_id: self.account.get(),
            category_id: optional(self.category.get()),
            destination_account_id: optional(self.destination.get()),
            destination_amount: received,
            payee: optional(self.payee.get()),
            note: optional(self.note.get()),
        };
        self.saving.set(true);
        self.error.set(String::new());
        let created = edit.is_none();
        let state = self.clone();
        spawn(async move {
            match services.save_finance_record(edit, draft).await {
                Ok(id) => {
                    state.saving.set(false);
                    if created {
                        // The undo pill owns the bottom slot for the window.
                        crate::finance_ui::offer_undo(
                            id.clone(),
                            "记录已保存，余额与预算已更新",
                            crate::finance_ui::UndoAction::Remove,
                        );
                    } else {
                        crate::finance_ui::notice("记录已保存，账户余额和预算已更新");
                    }
                    crate::finance_ui::acknowledge_fact(
                        source,
                        "记录已保存；余额与分类预算已更新。若列表未显示，请检查日期和筛选。",
                        Some(id),
                    );
                    reload.update(|v| *v += 1);
                    open.set(false);
                }
                Err(e) => {
                    state.saving.set(false);
                    state.error.set(e);
                }
            }
        });
    }
}

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
            dialog()
                .on_cancel(move || cancel.cancel(open))
                .flex_1()
                .bg(hsla(0.0, 0.0, 0.0, 0.36))
                .pt_safe_area_plus(px(12.0))
                .child(
                    view()
                        .flex_1()
                        .rounded(move || px(ui::card_radius()))
                        .overflow_hidden()
                        .bg(move || theme().card)
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_3()
                                .px_5()
                                .pt_safe_area_plus(px(12.0))
                                .pb_3()
                                .child(ui::secondary_button(
                                    "取消",
                                    move || cancel_button.cancel(open),
                                    "record-cancel",
                                    None,
                                ))
                                .child(
                                    text(title)
                                        .text_lg()
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .flex_1(),
                                ),
                        )
                        .child(
                            ui::interactive_scroll().flex_1().child(
                                view()
                                    .p_5()
                                    .gap_5()
                                    .child(when(
                                        move || state.loading.get(),
                                        || {
                                            text("正在读取账户…")
                                                .text_color(move || theme().muted_foreground)
                                        },
                                    ))
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
                        .child(view().px_5().pt_3().pb_safe_area_plus(px(16.0)).child(
                            ui::primary_button(
                                "保存记录",
                                submit_action,
                                "record-save",
                                Some(state.saving),
                            ),
                        ))
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
                                        .bg(move || theme().card)
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
                                        .child(
                                            view()
                                                .role(AccessibilityRole::Button)
                                                .label("放弃修改")
                                                .test_id("record-discard")
                                                .min_h(px(48.0))
                                                .items_center()
                                                .justify_center()
                                                .on_press(move || {
                                                    state.discard.set(false);
                                                    open.set(false);
                                                })
                                                .child(
                                                    text("放弃修改")
                                                        .text_sm()
                                                        .text_color(move || theme().destructive),
                                                ),
                                        ),
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
    let source = state.clone();
    let cross = state.clone();
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
        .gap_5()
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
                .py_3()
                .child(
                    text("金额")
                        .text_sm()
                        .text_color(move || theme().muted_foreground),
                )
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .gap_3()
                        .child(
                            text(move || amount_currency.currency(&amount_currency.account.get()))
                                .text_lg()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(
                            ui::themed_input()
                                .value(amount_state.amount)
                                .on_change(move |v: &str| amount_state.amount.set(v.to_owned()))
                                .on_submit(move |_: &str| amount_submit())
                                .keyboard_type(move || {
                                    if keyboard_kind.get() == RecordKind::OpeningBalance {
                                        KeyboardType::Numeric
                                    } else {
                                        KeyboardType::Decimal
                                    }
                                })
                                .placeholder("0.00")
                                .text_size(px(40.0))
                                .font_weight(FontWeight::MEDIUM)
                                .h(px(68.0))
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
                .bg(move || theme().card)
                .rounded(px(16.0))
                .child(ui::select_field(
                    "账户",
                    state.accounts,
                    state.account,
                    "record-account",
                ))
                .child(ui::divider())
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
                ui::text_field(
                    "实际到账金额",
                    "转入账户币种的金额",
                    received,
                    "record-received",
                )
            },
        ))
        .child(crate::finance_ui::date_field(
            "日期",
            "record-date",
            state.date,
        ))
        .child(ui::text_field_submit(
            "对方",
            "商家或付款方（可选）",
            state.payee,
            "record-payee",
            payee_submit,
        ))
        .child(ui::text_field_submit(
            "备注",
            "给这笔记录补充一点信息",
            state.note,
            "record-note",
            note_submit,
        ))
        .child(ui::error_line(state.error))
}

/// Category choices as four independent cells: the selection is a quiet wash
/// plus a small steel check replacing the label's leading mark — no shared
/// track, no raised inset, no shadow.
fn category_grid(state: Form) -> AnyElement {
    view()
        .test_id("record-category")
        .grid()
        .grid_cols(4)
        .gap(px(6.0))
        .child(each(
            move || state.categories.get(),
            |c: &(String, String)| c.0.clone(),
            move |item: ReadSignal<(String, String)>, _| {
                let (value, label) = item.get();
                category_cell(state.clone(), value, label)
            },
        ))
        .into_element()
}

fn category_cell(state: Form, value: String, label: String) -> impl IntoElement {
    let selected = state.clone();
    let check = state.clone();
    let semantic = state.clone();
    let semantic_value = value.clone();
    let press = state.clone();
    let press_value = value.clone();
    let bg_value = value.clone();
    let text_value = value.clone();
    view()
        .role(AccessibilityRole::Button)
        .label(format!("{label}分类选项"))
        .accessibility_state(move || AccessibilityState {
            selected: semantic.category.get() == semantic_value,
            ..Default::default()
        })
        .test_id(&format!("record-category-{}", value))
        .on_press(move || press.category.set(press_value.clone()))
        .flex_1()
        .min_h(px(48.0))
        .min_w(px(48.0))
        .px_2()
        .py_2()
        .items_center()
        .justify_center()
        .gap_1()
        .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
        .bg(move || {
            if selected.category.get() == bg_value {
                crate::finance_ui::wash()
            } else {
                theme().card
            }
        })
        .active(|s| s.opacity(0.8))
        .focus(ui::focus_ring)
        .child(dynamic(move || {
            let active = check.category.get() == value;
            let opacity = animated_value(1.0);
            if !reduce_motion() {
                opacity.set(0.0);
                opacity.timing(1.0, 120.0, Easing::Bezier(0.16, 1.0, 0.3, 1.0));
            }
            ui::icon(if active {
                ui::Icon::Check
            } else {
                ui::Icon::Expense
            })
            .w(px(17.0))
            .h(px(17.0))
            .text_color(move || {
                if active {
                    theme().ring
                } else {
                    theme().muted_foreground
                }
            })
            .bind_opacity(&opacity)
        }))
        .child(
            text(label)
                .text_size(px(12.0))
                .font_weight(FontWeight::MEDIUM)
                .text_color(move || {
                    if selected.category.get() == text_value {
                        theme().foreground
                    } else {
                        theme().muted_foreground
                    }
                }),
        )
}

fn kind_switch(state: Form, services: Arc<Services>) -> impl IntoElement {
    view().flex_row().gap_2().children(
        [
            RecordKind::Expense,
            RecordKind::Income,
            RecordKind::Transfer,
        ]
        .map(|kind| {
            let state = state.clone();
            let selected = state.clone();
            let services = services.clone();
            ui::choice_button(
                kind.label(),
                move || selected.kind.get() == kind,
                move || {
                    state.kind.set(kind);
                    state.categories(services.clone());
                },
                format!("record-kind-{}", kind.label()),
            )
            .flex_1()
        }),
    )
}
