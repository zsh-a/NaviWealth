//! Custody accounts: exact balances, metadata, archive/restore and guarded capture.
use crate::{state::Services, ui};
use naviwealth_finance::{
    models::{Account, AccountCategory, AccountSide, NewAccount},
    repos::account_repository::AccountBalance,
};
use nsh_base::{SheetEvent, dialog, theme};
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{collections::BTreeMap, sync::Arc};

#[derive(Clone, PartialEq)]
struct AccountRow {
    account: Account,
    balance: Option<AccountBalance>,
}

fn kind_label(kind: AccountCategory) -> &'static str {
    match kind {
        AccountCategory::Cash => "现金",
        AccountCategory::Bank => "银行卡",
        AccountCategory::Broker => "证券账户",
        AccountCategory::Crypto => "数字资产",
        AccountCategory::Credit => "信用卡",
        AccountCategory::Loan => "贷款",
        AccountCategory::Asset => "其他资产",
        AccountCategory::Liability => "其他负债",
    }
}
fn liability(kind: AccountCategory) -> bool {
    matches!(
        kind,
        AccountCategory::Credit | AccountCategory::Loan | AccountCategory::Liability
    )
}
fn optional(value: String) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_owned())
}
fn balance_text(row: &AccountRow) -> String {
    match &row.balance {
        Some(balance) if !balance.legs.is_empty() => balance
            .legs
            .iter()
            .map(|(unit, amount)| {
                if lifeos::money::Currency::new(unit).is_ok() {
                    format!("{} {unit}", ui::money(*amount))
                } else {
                    format!("{} 单位持仓", amount.normalize())
                }
            })
            .collect::<Vec<_>>()
            .join("  ·  "),
        _ => format!("0.00 {}", row.account.currency),
    }
}
fn totals(rows: &[AccountRow]) -> Result<Vec<(String, Decimal)>, String> {
    let mut totals: BTreeMap<String, Decimal> = BTreeMap::new();
    for row in rows.iter().filter(|r| !r.account.archived) {
        if let Some(balance) = &row.balance {
            for (currency, amount) in &balance.legs {
                if lifeos::money::Currency::new(currency).is_err() {
                    continue;
                }
                let value = totals.entry(currency.clone()).or_default();
                *value = value
                    .checked_add(*amount)
                    .ok_or_else(|| "余额超出显示范围，请查看各账户明细".to_owned())?;
            }
        } else {
            totals.entry(row.account.currency.clone()).or_default();
        }
    }
    Ok(totals.into_iter().collect())
}

#[allow(non_snake_case)]
pub fn AccountsScreen() -> impl IntoElement {
    accounts_screen(None, false)
}

pub fn account_route(path: String) -> AnyElement {
    let target = path.strip_prefix("/wealth/accounts/").map(str::to_owned);
    if target.is_none() {
        return AccountsScreen().into_element();
    }
    let create = target.as_deref() == Some("new");
    accounts_screen(target.filter(|_| !create), create).into_element()
}

fn accounts_screen(initial_account: Option<String>, create: bool) -> impl IntoElement {
    let services = use_context::<Arc<Services>>().expect("services context");
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    let rows = signal(Vec::<AccountRow>::new());
    let loading = signal(true);
    let error = signal(String::new());
    let archived = signal(initial_account.is_some());
    let retry = signal(0_u64);
    let notice = signal(String::new());
    let serial = signal(0_u64);
    let selected = signal(None::<AccountRow>);
    let form_open = signal(create);
    let route_pending = signal(initial_account);
    let edit = signal(None::<Account>);
    let record_open = signal(false);
    let route_navigation = use_context::<crate::finance_ui::Navigation>();
    {
        let services = services.clone();
        effect(move || {
            version.get();
            retry.get();
            let include_archived = archived.get();
            serial.update(|v| *v += 1);
            let request = serial.get_untracked();
            loading.set(true);
            error.set(String::new());
            let services = services.clone();
            spawn(async move {
                let result = services.finance_accounts(include_archived).await;
                if serial.try_get() != Some(request) {
                    return;
                }
                match result {
                    Ok(accounts) => {
                        let accounts: Vec<_> = accounts
                            .into_iter()
                            .map(|(account, balance)| AccountRow { account, balance })
                            .collect();
                        if let Some(id) = route_pending.get_untracked() {
                            route_pending.set(None);
                            if let Some(account) = accounts.iter().find(|a| a.account.id == id) {
                                selected.set(Some(account.clone()));
                            } else {
                                error.set("账户不存在或当前不可用，请重新选择账户".into());
                            }
                        }
                        rows.set(accounts);
                    }
                    Err(e) => error.set(e),
                }
                loading.set(false);
            });
        });
    }
    view().flex_1()
        .child(view().px_4().pt_3().pb_2().gap_2()
            .child(view().flex_row().items_center().gap_3()
                .child(when(move || route_navigation.is_some_and(|n| !n.0.get().is_empty()), ||ui::icon_button(ui::Icon::Back,"返回财富","account-list-back",crate::finance_ui::back)))
                .child(view().gap_1().flex_1().child(text("账户").text_lg().font_weight(FontWeight::SEMIBOLD)).child(text("现金、负债与持仓账户").text_sm().text_color(move || theme().muted_foreground)))
                .child(ui::primary_button("添加",move ||{edit.set(None);form_open.set(true);},"open-account-form",None)))
            .child(view().flex_row().gap_3()
                .child(ui::secondary_button("记一笔",move ||record_open.set(true),"open-record",None).flex_1())
                .child(ui::choice_button("显示已归档",move ||archived.get(),move ||archived.update(|v|*v = !*v),"accounts-show-archived").flex_1())))
        .child(ui::interactive_scroll().flex_1().child(view().px_4().pb_6().gap_3()
            .child(when(move ||!notice.get().is_empty(),move ||text(move ||notice.get()).text_sm().text_color(move ||theme().primary)))
            .child(when(move ||loading.get(),||text("正在读取账户…").text_sm().text_color(move ||theme().muted_foreground)))
            .child(when(move ||!error.get().is_empty(),move ||view().gap_3().child(ui::error_line(error))
                .child(ui::secondary_button("重新加载",move ||retry.update(|v|*v+=1),"accounts-retry",None))))
            .child(when(move ||!loading.get()&&error.get().is_empty()&&rows.get().is_empty(),move ||view().gap_4()
                .child(ui::empty_state("从一个账户开始","添加常用的银行卡、现金或信用卡，并设置当前余额。之后就可以记录收入、支出和转账。"))
                .child(ui::primary_button("添加第一个账户",move ||{edit.set(None);form_open.set(true);},"accounts-empty-add",None))))
            .child(when(move ||rows.with(|items|items.iter().any(|row|!row.account.archived)),move ||view().gap_3()
                .child(text("使用中账户 · 原币现金净额").text_sm().text_color(move ||theme().muted_foreground))
                .child(dynamic(move ||match totals(&rows.get()) {
                    Ok(totals)=>view().gap_2().children(totals.into_iter().map(|(currency,amount)|view().flex_row().items_center().gap_3()
                        .child(text(currency).text_sm().text_color(move ||theme().muted_foreground).flex_1())
                        .child(text(ui::money(amount)).text_size(px(22.0)).tabular_nums().font_weight(FontWeight::MEDIUM)))).into_element(),
                    Err(message)=>text(message).text_sm().text_color(move ||theme().destructive).into_element(),
                }))
                .child(ui::divider())))
            .child(view().child(each(move ||rows.get(),|row:&AccountRow|row.account.id.clone(),
                move |row:ReadSignal<AccountRow>,_|account_row(row,selected))))))
        .child(account_details(services.clone(),selected,edit,form_open,version,notice))
        .child(account_form(services.clone(),form_open,edit,selected,version))
        .child(crate::screens::record::record_dialog(services,record_open,version))
}

fn account_row(
    row: ReadSignal<AccountRow>,
    selected: Signal<Option<AccountRow>>,
) -> impl IntoElement {
    let id = format!("account-{}", row.get().account.id);
    view()
        .child(
            view()
                .role(AccessibilityRole::Button)
                .test_id(&id)
                .on_press(move || selected.set(Some(row.get())))
                .flex_row()
                .items_center()
                .gap_3()
                .px_4()
                .py_3()
                .min_h(px(64.0))
                .active(|s| s.opacity(0.7))
                .child(ui::icon(ui::Icon::Wallet).text_color(move || theme().primary))
                .child(
                    view()
                        .flex_1()
                        .gap_1()
                        .child(
                            text(move || row.get().account.name)
                                .text_base()
                                .font_weight(FontWeight::MEDIUM),
                        )
                        .child(
                            text(move || {
                                let a = row.get().account;
                                format!(
                                    "{}{}",
                                    kind_label(a.kind),
                                    if a.archived { " · 已归档" } else { "" }
                                )
                            })
                            .text_sm()
                            .text_color(move || theme().muted_foreground),
                        ),
                )
                .child(
                    text(move || balance_text(&row.get()))
                        .text_base()
                        .text_right()
                        .tabular_nums()
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(ui::icon(ui::Icon::Arrow).text_color(move || theme().muted_foreground)),
        )
        .child(ui::divider())
}

fn detail_line(label: &'static str, value: impl Into<String>) -> impl IntoElement {
    view()
        .flex_row()
        .gap_3()
        .py_3()
        .child(
            text(label)
                .text_sm()
                .text_color(move || theme().muted_foreground)
                .w(px(76.0)),
        )
        .child(text(value.into()).text_base().flex_1())
}
fn account_details(
    services: Arc<Services>,
    selected: Signal<Option<AccountRow>>,
    edit: Signal<Option<Account>>,
    form_open: Signal<bool>,
    version: Signal<u64>,
    notice: Signal<String>,
) -> impl IntoElement {
    let navigation = use_context::<crate::FinanceNavigation>();
    let shell = use_context::<crate::ShellTab>();
    let routes = use_context::<crate::finance_ui::Navigation>();
    when(
        move || selected.get().is_some(),
        move || {
            let row = selected.get().expect("selected account");
            let account = row.account.clone();
            let busy = signal(false);
            let error = signal(String::new());
            let confirm = signal(false);
            let edit_account = account.clone();
            let list_id = account.id.clone();
            let archived = account.archived;
            let archive_id = account.id.clone();
            let archive_services = services.clone();
            let delete_id = account.id.clone();
            let delete_services = services.clone();
            dialog().test_id("account-details").on_cancel(move ||{if !busy.get(){selected.set(None);}}).flex_1().bg(move ||theme().background)
            .child(view().flex_row().items_center().gap_3().px_5().pt_safe_area_plus(px(12.0)).pb_3()
                .child(ui::secondary_button("返回",move ||selected.set(None),"account-detail-back",Some(busy)))
                .child(text("账户详情").text_lg().font_weight(FontWeight::SEMIBOLD).flex_1())
                .child(ui::secondary_button("编辑",move ||{edit.set(Some(edit_account.clone()));selected.set(None);form_open.set(true);},"account-edit",Some(busy))))
            .child(ui::interactive_scroll().flex_1().child(view().p_4().gap_3()
                .child(view().gap_2()
                    .child(text(account.name.clone()).text_size(px(22.0)).font_weight(FontWeight::SEMIBOLD))
                    .child(text(if account.side==AccountSide::Liability {"账户余额 · 负数表示待还"} else {"账户余额"}).text_sm().text_color(move ||theme().muted_foreground))
                    .child(text(balance_text(&row)).text_size(px(24.0)).tabular_nums().font_weight(FontWeight::MEDIUM)))
                .child(view().px_1()
                    .child(detail_line("账户类型",kind_label(account.kind))).child(ui::divider())
                    .child(detail_line("币种",account.currency)).child(ui::divider())
                    .child(detail_line("机构",account.institution.unwrap_or_else(||"未填写".to_owned()))).child(ui::divider())
                    .child(detail_line("备注",account.note.unwrap_or_else(||"未填写".to_owned()))).child(ui::divider())
                    .child(detail_line("状态",if archived {"已归档"}else{"使用中"})))
                .child(ui::primary_button("查看流水",move ||{
                    if let Some(nav)=navigation {nav.account.set(list_id.clone());nav.all_dates.set(true);}
                    if let Some(tab)=shell {tab.0.set(1);}
                    selected.set(None);
                    if let Some(routes)=routes {routes.0.update(Vec::clear);}
                },"account-records",Some(busy)))

                .child(text("账户管理").text_sm().font_weight(FontWeight::SEMIBOLD).text_color(move ||theme().muted_foreground))
                .child(ui::secondary_button(if archived {"恢复账户"}else{"归档账户"},move ||{
                    busy.set(true);error.set(String::new());let services=archive_services.clone();let id=archive_id.clone();
                    spawn(async move {match services.archive_finance_account(&id,!archived).await {
                        Ok(())=>{selected.set(None);notice.set(if archived {"账户已恢复"}else{"账户已归档，可打开“显示已归档”恢复"}.to_owned());version.update(|v|*v+=1);}
                        Err(e)=>error.set(e),
                    }busy.set(false);});
                },if archived {"account-restore"}else{"account-archive"},Some(busy)))
                .child(view().gap_2().pt_3()
                    .child(text("已有历史流水的账户请使用归档，账本和余额记录会保留。").text_sm().text_color(move ||theme().muted_foreground))
                    .child(ui::secondary_button("删除空账户",move ||confirm.set(true),"account-delete",Some(busy))))
                .child(ui::error_line(error))))
            .child(ui::app_sheet().open(move ||Some(confirm.get())).on_open_change(move |event:&SheetEvent|{
                if let SheetEvent::OpenChange(next,_) = event && !busy.get() {confirm.set(*next);}
            }).child(view().p_5().pb_safe_area_plus(px(20.0)).gap_4().bg(move ||theme().background)
                .child(text("删除这个账户？").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(text("仅未产生过流水的账户可以删除；已有历史记录的账户请改用归档。").text_base().text_color(move ||theme().muted_foreground))
                .child(ui::secondary_button("保留账户",move ||confirm.set(false),"account-delete-cancel",Some(busy)))
                .child(ui::danger_button("确认删除",move ||{
                    busy.set(true);error.set(String::new());let services=delete_services.clone();let id=delete_id.clone();
                    spawn(async move {match services.delete_finance_account(&id).await {
                        Ok(())=>{confirm.set(false);selected.set(None);notice.set("空账户已删除".to_owned());version.update(|v|*v+=1);}
                        Err(e)=>{confirm.set(false);error.set(e);}
                    }busy.set(false);});
                },"account-delete-confirm",busy))))
        },
    )
}

#[derive(Clone)]
struct AccountForm {
    name: Signal<String>,
    currency: Signal<String>,
    opening: Signal<String>,
    kind: Signal<String>,
    institution: Signal<String>,
    note: Signal<String>,
    saving: Signal<bool>,
    error: Signal<String>,
    discard: Signal<bool>,
    baseline: String,
}
impl AccountForm {
    fn new(edit: Option<&Account>) -> Self {
        let mut form = Self {
            name: signal(edit.map(|a| a.name.clone()).unwrap_or_default()),
            currency: signal(
                edit.map(|a| a.currency.clone())
                    .unwrap_or_else(|| "CNY".to_owned()),
            ),
            opening: signal(String::new()),
            kind: signal(
                edit.map(|a| a.kind.as_str().to_owned())
                    .unwrap_or_else(|| "cash".to_owned()),
            ),
            institution: signal(edit.and_then(|a| a.institution.clone()).unwrap_or_default()),
            note: signal(edit.and_then(|a| a.note.clone()).unwrap_or_default()),
            saving: signal(false),
            error: signal(String::new()),
            discard: signal(false),
            baseline: String::new(),
        };
        form.baseline = untracked(|| form.signature());
        form
    }
    fn signature(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}",
            self.name.get(),
            self.currency.get(),
            self.opening.get(),
            self.kind.get(),
            self.institution.get(),
            self.note.get()
        )
    }
    fn cancel(&self, open: Signal<bool>) {
        if self.saving.get() {
            return;
        }
        if self.signature() != self.baseline {
            self.discard.set(true);
        } else {
            open.set(false);
        }
    }
    fn submit(
        &self,
        services: Arc<Services>,
        account: Option<Account>,
        open: Signal<bool>,
        selected: Signal<Option<AccountRow>>,
        version: Signal<u64>,
    ) {
        if self.saving.get() {
            return;
        }
        if self.name.get().trim().is_empty() {
            self.error.set("请输入账户名称".to_owned());
            return;
        }
        let Some(kind) = AccountCategory::parse(&self.kind.get()) else {
            self.error.set("请选择账户类型".to_owned());
            return;
        };
        let opening = if account.is_none() && !self.opening.get().trim().is_empty() {
            match self.opening.get().trim().parse::<Decimal>() {
                Ok(value) if !liability(kind) || value >= Decimal::ZERO => {
                    Some(if liability(kind) { -value } else { value })
                }
                Ok(_) => {
                    self.error.set("待还金额请填写正数或 0".to_owned());
                    return;
                }
                Err(_) => {
                    self.error.set("请输入有效的期初金额，或留空".to_owned());
                    return;
                }
            }
        } else {
            None
        };
        self.saving.set(true);
        self.error.set(String::new());
        let state = self.clone();
        spawn(async move {
            let result = if let Some(account) = account {
                services
                    .update_finance_account(
                        &account.id,
                        state.name.get().trim().to_owned(),
                        optional(state.institution.get()),
                        optional(state.note.get()),
                    )
                    .await
            } else {
                let mut new = NewAccount::custody(
                    kind,
                    state.name.get().trim(),
                    state.currency.get().trim().to_uppercase(),
                );
                new.institution = optional(state.institution.get());
                new.note = optional(state.note.get());
                services.create_account(new, opening).await.map(|_| ())
            };
            state.saving.set(false);
            match result {
                Ok(()) => {
                    open.set(false);
                    selected.set(None);
                    version.update(|v| *v += 1);
                }
                Err(e) => state.error.set(e),
            }
        });
    }
}
fn account_form(
    services: Arc<Services>,
    open: Signal<bool>,
    edit: Signal<Option<Account>>,
    selected: Signal<Option<AccountRow>>,
    version: Signal<u64>,
) -> impl IntoElement {
    when(
        move || open.get(),
        move || {
            let account = edit.get();
            let editing = account.is_some();
            let state = AccountForm::new(account.as_ref());
            let kinds = signal(
                [
                    AccountCategory::Cash,
                    AccountCategory::Bank,
                    AccountCategory::Credit,
                    AccountCategory::Loan,
                    AccountCategory::Broker,
                    AccountCategory::Crypto,
                    AccountCategory::Asset,
                    AccountCategory::Liability,
                ]
                .into_iter()
                .map(|k| (k.as_str().to_owned(), kind_label(k).to_owned()))
                .collect::<Vec<_>>(),
            );
            let close = state.clone();
            let cancel = state.clone();
            let submit = state.clone();
            let submit_services = services.clone();
            let discard = state.clone();
            let dismiss = state.clone();
            let keep = state.clone();
            let abandon = state.clone();
            let type_state = state.clone();
            let label_state = state.clone();
            let amount_state = state.clone();
            ui::app_sheet().open(move ||Some(open.get())).on_open_change(move |event:&SheetEvent|{
            if let SheetEvent::OpenChange(next,_) = event && !next {close.cancel(open);}
        }).child(view().test_id("account-editor").bg(move ||theme().background).h(move ||px((window().height.0-80.0).clamp(320.0,680.0))).max_h(px(680.0)).gap_3()
            .child(view().flex_row().items_center().gap_3().px_5().pt_5()
                .child(text(if editing {"编辑账户"}else{"添加账户"}).text_lg().font_weight(FontWeight::SEMIBOLD).flex_1())
                .child(ui::secondary_button("取消",move ||cancel.cancel(open),"account-cancel",Some(state.saving))))
            .child(ui::interactive_scroll().flex_1().child(view().px_5().py_3().gap_4()
                .child(ui::text_field("账户名称","例如：工资卡、日常现金",state.name,"account-name"))
                .child(when(move ||!editing,move ||view().gap_4()
                    .child(ui::select_field("账户类型",kinds,type_state.kind,"account-kind"))
                    .child(ui::text_field("币种","CNY / USD / HKD",type_state.currency,"account-currency"))
                    .child(view().gap_1()
                        .child(text(move ||if liability(AccountCategory::parse(&label_state.kind.get()).unwrap_or(AccountCategory::Cash)){"当前待还金额（可选）"}else{"当前余额（可选）"}).text_sm().text_color(move ||theme().muted_foreground))
                        .child(ui::themed_input().value(amount_state.opening).on_change(move |value:&str|amount_state.opening.set(value.to_owned()))
                            .keyboard_type(KeyboardType::Decimal).placeholder("0.00").min_h(px(48.0)).px_3().rounded(move ||theme().radius)
                            .bg(move ||theme().card).border_1().border_color(move ||theme().border).text_base().test_id("account-opening")))))
                .child(when(move ||editing,move ||text("账户类型与币种保持不变；余额通过流水和期初记录管理。").text_sm().text_color(move ||theme().muted_foreground)))
                .child(ui::text_field("机构","银行或平台名称（可选）",state.institution,"account-institution"))
                .child(ui::text_field("备注","给这个账户补充一点信息（可选）",state.note,"account-note"))
                .child(ui::error_line(state.error))))
            .child(view().px_5().pb_safe_area_plus(px(16.0))
                .child(ui::primary_button("保存账户",move ||submit.submit(submit_services.clone(),account.clone(),open,selected,version),"account-save",Some(state.saving))))
            .child(ui::app_sheet().open(move ||Some(discard.discard.get())).on_open_change(move |event:&SheetEvent|{
                if let SheetEvent::OpenChange(next,_)=event {dismiss.discard.set(*next);}
            }).child(view().p_5().pb_safe_area_plus(px(20.0)).gap_4().bg(move ||theme().background)
                .child(text("放弃未保存的修改？").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(text("本次填写的账户信息将不会保存。").text_base().text_color(move ||theme().muted_foreground))
                .child(ui::secondary_button("继续填写",move ||keep.discard.set(false),"account-keep",None))
                .child(ui::primary_button("放弃修改",move ||{abandon.discard.set(false);open.set(false);},"account-discard",None)))))
        },
    )
}
