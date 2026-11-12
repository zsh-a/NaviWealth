use super::*;

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
pub(super) fn account_form(
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
                .map(|k| ui::SelectOption::new(k.as_str(), kind_label(k)))
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
                        .child(ui::money_input(amount_state.opening, move || amount_state.currency.get())
                            .keyboard_type(KeyboardType::Decimal).min_h(px(48.0)).px_3().rounded(move ||theme().radius)
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
                .child(ui::primary_button("继续填写",move ||keep.discard.set(false),"account-keep",None))
                .child(ui::text_button("放弃修改", "account-discard", move ||{abandon.discard.set(false);open.set(false);}, true)))))
        },
    )
}
