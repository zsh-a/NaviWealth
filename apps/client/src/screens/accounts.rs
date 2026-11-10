//! 账户: the custody account list with balances, the account form sheet
//! and the entry point into the expense record dialog.

use std::str::FromStr;
use std::sync::Arc;

use naviwealth_finance::models::{Account, AccountCategory, NewAccount};
use nsh_base::{SheetEvent, sheet, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;

use crate::state::Services;
use crate::ui;

#[derive(Clone, PartialEq)]
struct AccountRow {
    account: Account,
    balance: Option<naviwealth_finance::repos::account_repository::AccountBalance>,
}

fn kind_label(kind: AccountCategory) -> &'static str {
    match kind {
        AccountCategory::Cash => "现金",
        AccountCategory::Bank => "银行",
        AccountCategory::Broker => "券商",
        AccountCategory::Crypto => "加密",
        AccountCategory::Credit => "信用卡",
        AccountCategory::Loan => "贷款",
        AccountCategory::Asset => "资产",
        AccountCategory::Liability => "负债",
    }
}

const FORM_KINDS: [AccountCategory; 6] = [
    AccountCategory::Cash,
    AccountCategory::Bank,
    AccountCategory::Broker,
    AccountCategory::Crypto,
    AccountCategory::Credit,
    AccountCategory::Loan,
];

fn fetch_rows(services: &Arc<Services>, rows: Signal<Vec<AccountRow>>, load_error: Signal<String>) {
    let services = services.clone();
    spawn(async move {
        match services.accounts_with_balances().await {
            Ok(list) => {
                rows.set(
                    list.into_iter()
                        .map(|(account, balance)| AccountRow { account, balance })
                        .collect(),
                );
                load_error.set(String::new());
            }
            Err(e) => load_error.set(e),
        }
    });
}

#[allow(non_snake_case)]
pub fn AccountsScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let rows: Signal<Vec<AccountRow>> = signal(Vec::new());
    let load_error: Signal<String> = signal(String::new());
    let data_version = use_context::<crate::state::DataVersion>().expect("data version");

    fetch_rows(&services, rows, load_error);
    // Reload whenever any write bumps the shared data version.
    {
        let services = services.clone();
        effect(move || {
            let _generation = data_version.0.get();
            fetch_rows(&services, rows, load_error);
        });
    }

    let sheet_open: Signal<bool> = signal(false);
    let record_open: Signal<bool> = signal(false);

    view()
        .flex_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .px_4()
                .py_3()
                .child(
                    text("账户")
                        .text_xl()
                        .font_weight(FontWeight::BOLD)
                        .flex_1(),
                )
                .child(ui::secondary_button(
                    "记一笔",
                    move || record_open.set(true),
                    "open-record",
                    None,
                ))
                .child(ui::primary_button(
                    "＋ 账户",
                    move || sheet_open.set(true),
                    "open-account-form",
                    None,
                )),
        )
        .child(
            scroll()
                .flex_1()
                .px_4()
                .pb_4()
                .child(ui::error_line(load_error))
                .child(each(
                    move || rows.get(),
                    |row: &AccountRow| row.account.id.clone(),
                    move |row: ReadSignal<AccountRow>, _index: ReadSignal<usize>| account_row(row),
                )),
        )
        .child(account_form_sheet(
            services.clone(),
            sheet_open,
            data_version.0,
        ))
        .child(crate::screens::record::record_dialog(
            services,
            record_open,
            data_version.0,
        ))
}

fn account_row(row: ReadSignal<AccountRow>) -> impl IntoElement {
    let account = row;
    let kind_label_value = move || kind_label(account.get().account.kind).to_owned();
    let legs = move || {
        account
            .get()
            .balance
            .as_ref()
            .map(|b| {
                b.legs
                    .iter()
                    .map(|(unit, amount)| format!("{amount} {unit}"))
                    .collect::<Vec<_>>()
                    .join("　·　")
            })
            .unwrap_or_else(|| "—".to_owned())
    };
    view()
        .flex_row()
        .items_center()
        .gap_3()
        .p_4()
        .rounded(move || px(crate::ui::card_radius()))
        .bg(move || theme().card)
        .child(
            view()
                .w(px(40.0))
                .h(px(40.0))
                .items_center()
                .justify_center()
                .rounded(px(999.0))
                .bg(move || theme().secondary)
                .child(
                    text(move || kind_label_value().chars().next().unwrap_or('·').to_string())
                        .text_base()
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(move || theme().secondary_foreground),
                ),
        )
        .child(
            view().flex_1().gap_1().child(
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text(move || account.get().account.name.clone())
                            .text_base()
                            .font_weight(FontWeight::MEDIUM),
                    )
                    .child(
                        text(kind_label_value)
                            .text_xs()
                            .text_color(move || theme().muted_foreground),
                    ),
            ),
        )
        .child(text(legs).tabular_nums().text_base())
}

fn account_form_sheet(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let name: Signal<String> = signal(String::new());
    let currency: Signal<String> = signal("CNY".to_owned());
    let opening: Signal<String> = signal(String::new());
    let kind: Signal<AccountCategory> = signal(AccountCategory::Cash);
    let save_error: Signal<String> = signal(String::new());
    let saving: Signal<bool> = signal(false);

    sheet()
        .open(move || Some(open.get()))
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(next, _) = event {
                open.set(*next);
            }
        })
        .child(
            view()
                .gap_3()
                .p_5()
                .rounded_t(px(16.0))
                .bg(move || theme().background)
                .child(text("新建账户").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(ui::text_field(
                    "名称",
                    "例如：招行储蓄卡",
                    name,
                    "account-name",
                ))
                .child(ui::text_field("币种", "CNY", currency, "account-currency"))
                .child(ui::text_field(
                    "期初余额（可选）",
                    "0.00",
                    opening,
                    "account-opening",
                ))
                .child(
                    view()
                        .gap_2()
                        .child(
                            text("类型")
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(view().flex_row().gap_2().children(FORM_KINDS.map(|k| {
                            ui::chip(
                                kind_label(k).to_owned(),
                                move || kind.get() == k,
                                move || kind.set(k),
                            )
                        }))),
                )
                .child(ui::error_line(save_error))
                .child(ui::primary_button(
                    "保存",
                    move || {
                        if name.get().trim().is_empty() {
                            save_error.set("请输入账户名称".to_owned());
                            return;
                        }
                        saving.set(true);
                        let services = services.clone();
                        let name_text = name.get().trim().to_owned();
                        let currency_text = currency.get().trim().to_uppercase();
                        let opening_decimal = Decimal::from_str(opening.get().trim()).ok();
                        let kind_value = kind.get();
                        let save_error = save_error;
                        let saving = saving;
                        let open = open;
                        let reload = reload;
                        spawn(async move {
                            let new_account =
                                NewAccount::custody(kind_value, name_text, currency_text);
                            match services.create_account(new_account, opening_decimal).await {
                                Ok(_) => {
                                    saving.set(false);
                                    open.set(false);
                                    name.set(String::new());
                                    opening.set(String::new());
                                    save_error.set(String::new());
                                    reload.update(|v| *v += 1);
                                }
                                Err(e) => {
                                    saving.set(false);
                                    save_error.set(e);
                                }
                            }
                        });
                    },
                    "account-save",
                    Some(saving),
                )),
        )
}
