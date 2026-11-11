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
        let state = self.clone();
        spawn(async move {
            match services.save_finance_record(edit, draft).await {
                Ok(()) => {
                    state.saving.set(false);
                    open.set(false);
                    reload.update(|v| *v += 1);
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
) -> impl IntoElement {
    record_editor(services, open, reload, signal(None))
}
pub fn record_editor(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
    edit: Signal<Option<String>>,
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
            let cancel_button = state.clone();
            let guard = state.clone();
            let close = state.clone();
            dialog()
                .on_cancel(move || cancel.cancel(open))
                .flex_1()
                .bg(move || theme().background)
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
                                move || form_fields(fields_state.clone(), fields_services.clone()),
                            )),
                    ),
                )
                .child(
                    view()
                        .px_5()
                        .pt_3()
                        .pb_safe_area_plus(px(16.0))
                        .child(ui::primary_button(
                            "保存记录",
                            move || submit.submit(save_services.clone(), edit.get(), open, reload),
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
                                .child(ui::secondary_button(
                                    "继续填写",
                                    move || state.discard.set(false),
                                    "record-keep",
                                    None,
                                ))
                                .child(ui::primary_button(
                                    "放弃修改",
                                    move || {
                                        state.discard.set(false);
                                        open.set(false);
                                    },
                                    "record-discard",
                                    None,
                                )),
                        ),
                )
        },
    )
}

fn form_fields(state: Form, services: Arc<Services>) -> impl IntoElement {
    let source = state.clone();
    let cross = state.clone();
    let received = state.received;
    let dest = state.clone();
    let kind_state = state.clone();
    let keyboard_kind = state.kind;
    let amount_state = state.clone();
    let amount_currency = state.clone();

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
                    move || {
                        ui::select_field(
                            "分类",
                            source.categories,
                            source.category,
                            "record-category",
                        )
                    },
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
        .child(ui::text_field(
            "日期",
            "yyyy-mm-dd",
            state.date,
            "record-date",
        ))
        .child(ui::text_field(
            "对方",
            "商家或付款方（可选）",
            state.payee,
            "record-payee",
        ))
        .child(ui::text_field(
            "备注",
            "给这笔记录补充一点信息",
            state.note,
            "record-note",
        ))
        .child(ui::error_line(state.error))
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
