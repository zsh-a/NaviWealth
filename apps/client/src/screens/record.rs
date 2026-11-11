//! 记一笔: the expense record dialog (full page per the form convention:
//! multiple sections). Date defaults to today; amount, category, account
//! are required; the write refuses to unbalance.

use std::str::FromStr;
use std::sync::Arc;

use nsh_base::{dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;

use crate::state::Services;
use crate::ui;

/// yyyy-mm-dd for the date field (civil-from-days; no chrono formatting in
/// the UI layer).
fn today_text() -> String {
    ui::ymd(lifeos::ids::now_secs())
}

#[derive(Clone, PartialEq)]
struct Pick {
    id: String,
    label: String,
}

#[derive(Clone)]
struct RecordState {
    date: Signal<String>,
    amount: Signal<String>,
    payee: Signal<String>,
    note: Signal<String>,
    categories: Signal<Vec<Pick>>,
    accounts: Signal<Vec<Pick>>,
    selected_category: Signal<String>,
    selected_account: Signal<String>,
    save_error: Signal<String>,
    saving: Signal<bool>,
}

impl RecordState {
    fn new() -> Self {
        Self {
            date: signal(today_text()),
            amount: signal(String::new()),
            payee: signal(String::new()),
            note: signal(String::new()),
            categories: signal(Vec::new()),
            accounts: signal(Vec::new()),
            selected_category: signal(String::new()),
            selected_account: signal(String::new()),
            save_error: signal(String::new()),
            saving: signal(false),
        }
    }

    fn load_picks(&self, services: &Arc<Services>) {
        let categories = self.categories;
        let accounts = self.accounts;
        let selected_category = self.selected_category;
        let selected_account = self.selected_account;
        let services = services.clone();
        spawn(async move {
            let cats = services.expense_categories().await.unwrap_or_default();
            if let Some((id, _)) = cats.first() {
                selected_category.set(id.clone());
            }
            categories.set(
                cats.into_iter()
                    .map(|(id, label)| Pick { id, label })
                    .collect(),
            );
            let accs = services.cash_accounts().await.unwrap_or_default();
            if let Some((id, _, _)) = accs.first() {
                selected_account.set(id.clone());
            }
            accounts.set(
                accs.into_iter()
                    .map(|(id, name, currency)| Pick {
                        id,
                        label: format!("{name} ({currency})"),
                    })
                    .collect(),
            );
        });
    }

    fn category_chips(&self) -> impl IntoElement {
        let state = self.clone();
        each(
            move || state.categories.get(),
            |pick: &Pick| pick.id.clone(),
            move |pick: ReadSignal<Pick>, _index: ReadSignal<usize>| {
                let pick = pick.get();
                let id_flag = pick.id.clone();
                let id_set = pick.id.clone();
                let state = state.clone();
                ui::chip(
                    pick.label,
                    move || state.selected_category.get() == id_flag,
                    move || state.selected_category.set(id_set.clone()),
                )
            },
        )
    }

    fn account_chips(&self) -> impl IntoElement {
        let state = self.clone();
        each(
            move || state.accounts.get(),
            |pick: &Pick| pick.id.clone(),
            move |pick: ReadSignal<Pick>, _index: ReadSignal<usize>| {
                let pick = pick.get();
                let id_flag = pick.id.clone();
                let id_set = pick.id.clone();
                let state = state.clone();
                ui::chip(
                    pick.label,
                    move || state.selected_account.get() == id_flag,
                    move || state.selected_account.set(id_set.clone()),
                )
            },
        )
    }

    fn optional_text(signal: Signal<String>) -> Option<String> {
        let owned = signal.get();
        let trimmed = owned.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_owned())
    }

    fn submit(&self, services: &Arc<Services>, open: Signal<bool>, reload: Signal<u64>) {
        let amount_value = match Decimal::from_str(self.amount.get().trim()) {
            Ok(v) if v > Decimal::ZERO => v,
            _ => {
                self.save_error.set("请输入正数金额".to_owned());
                return;
            }
        };
        let date_secs = match ui::date_to_secs(self.date.get().trim()) {
            Some(secs) => secs,
            None => {
                self.save_error.set("日期格式应为 yyyy-mm-dd".to_owned());
                return;
            }
        };
        if self.selected_category.get().is_empty() || self.selected_account.get().is_empty() {
            self.save_error.set("请选择分类和账户".to_owned());
            return;
        }
        self.saving.set(true);
        let services = services.clone();
        let expense_account = self.selected_category.get();
        let from_account = self.selected_account.get();
        let payee_text = Self::optional_text(self.payee);
        let note_text = Self::optional_text(self.note);
        let save_error = self.save_error;
        let saving = self.saving;
        let amount = self.amount;
        let note = self.note;
        spawn(async move {
            match services
                .create_expense(
                    date_secs,
                    amount_value,
                    expense_account,
                    from_account,
                    payee_text,
                    note_text,
                )
                .await
            {
                Ok(()) => {
                    saving.set(false);
                    open.set(false);
                    amount.set(String::new());
                    note.set(String::new());
                    save_error.set(String::new());
                    reload.update(|v| *v += 1);
                }
                Err(e) => {
                    saving.set(false);
                    save_error.set(e);
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
    let state = RecordState::new();

    when(
        move || open.get(),
        move || {
            // Picks refresh on every open (accounts/categories change).
            state.load_picks(&services);
            dialog()
                .on_cancel(move || open.set(false))
                .flex_1()
                .bg(move || theme().background)
                .child(
                    scroll().flex_1().child(
                        view()
                            .px_5()
                            .pt_safe_area_plus(px(20.0))
                            .pb_safe_area_plus(px(20.0))
                            .gap_3()
                            .child(text("记一笔").text_xl().font_weight(FontWeight::BOLD))
                            .child(ui::text_field(
                                "日期",
                                "yyyy-mm-dd",
                                state.date,
                                "record-date",
                            ))
                            .child(ui::text_field(
                                "金额",
                                "0.00",
                                state.amount,
                                "record-amount",
                            ))
                            .child(
                                view()
                                    .gap_2()
                                    .child(
                                        text("分类")
                                            .text_sm()
                                            .text_color(move || theme().muted_foreground),
                                    )
                                    .child(state.category_chips()),
                            )
                            .child(
                                view()
                                    .gap_2()
                                    .child(
                                        text("账户")
                                            .text_sm()
                                            .text_color(move || theme().muted_foreground),
                                    )
                                    .child(state.account_chips()),
                            )
                            .child(ui::text_field("对方", "可选", state.payee, "record-payee"))
                            .child(ui::text_field("备注", "可选", state.note, "record-note"))
                            .child(ui::error_line(state.save_error))
                            .child(
                                view()
                                    .flex_row()
                                    .gap_3()
                                    .child(
                                        ui::secondary_button(
                                            "取消",
                                            move || open.set(false),
                                            "",
                                            None,
                                        )
                                        .flex_1(),
                                    )
                                    .child(
                                        ui::primary_button(
                                            "保存",
                                            {
                                                let services = services.clone();
                                                let state = state.clone();
                                                move || state.submit(&services, open, reload)
                                            },
                                            "record-save",
                                            Some(state.saving),
                                        )
                                        .flex_1(),
                                    ),
                            ),
                    ),
                )
        },
    )
}
