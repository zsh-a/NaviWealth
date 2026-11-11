use super::*;
pub(super) fn render(parts: Vec<String>) -> AnyElement {
    match parts.get(2).map(String::as_str) {
        None => list(),
        Some("new") => capture(parts.get(3).cloned(), parts.get(4).cloned()),
        Some(id) => {
            if parts.get(3).map(String::as_str) == Some("undo") {
                undo(id.into())
            } else if parts.get(3).map(String::as_str) == Some("cancel") {
                cancel(id.into())
            } else {
                receipt(id.into())
            }
        }
    }
}
fn list() -> AnyElement {
    let s = fui::services();
    loaded(
        "账户对账",
        move || {
            let s = s.clone();
            Box::pin(async move { s.finance_reconciliations().await })
        },
        move |rows| {
            let mut body=view().gap_3().child(copy("将实际账单余额与指定日期的账本余额比较。差额确认前不改变余额；确认后生成一笔平衡的权益调整。" )).child(go("建立对账预览","reconcile-new","/activity/reconcile/new".into()));
            if rows.is_empty() {
                body = body.child(copy("尚无对账记录。月结前请核对各资金账户的月末余额。"));
            }
            for r in rows {
                let route = format!("/activity/reconcile/{}", r.id);
                body = body.child(fui::row(
                    ui::ymd(r.date),
                    format!(
                        "实际 {} · 差额 {}",
                        amount(r.actual, &r.currency),
                        amount(r.difference, &r.currency)
                    ),
                    match r.status {
                        ReconciliationStatus::Review => "待确认",
                        ReconciliationStatus::Confirmed => "已确认",
                        ReconciliationStatus::Undone => "已撤销",
                    }
                    .into(),
                    format!("reconciliation-{}", r.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("账户对账", body)
        },
    )
}
fn capture(selected: Option<String>, selected_date: Option<String>) -> AnyElement {
    let s = fui::services();
    loaded_mode(
        "建立对账预览",
        true,
        move || {
            let s = s.clone();
            Box::pin(async move { s.finance_accounts(false).await })
        },
        move |accounts| {
            if accounts.is_empty() {
                return fui::page(
                    "建立对账预览",
                    view().gap_3().child(copy("请先建立资金账户。")).child(go(
                        "建立账户",
                        "reconcile-create-account",
                        "/wealth/accounts/new".into(),
                    )),
                );
            }
            let choices = accounts
                .into_iter()
                .map(|(a, _)| (a.id, format!("{} · {}", a.name, a.currency)))
                .collect();
            fui::form("建立对账预览",vec![Field::choice("reconcile-account","资金账户",selected.clone().unwrap_or_default(),choices),Field::date("reconcile-date","对账日期",selected_date.clone().unwrap_or_else(ui::today_text)).help("实际余额指所选日期结束时的余额。"),Field::decimal("reconcile-actual","实际余额","").help("使用账本符号：资产为正，欠款为负。零余额可直接填写 0。仅核对账户币种的现金余额。"),Field::multiline("reconcile-note","差额原因（有差额时必填）","").help("例如账单手续费遗漏；先核查交易，确需调整再确认。")],move|v|Box::pin(async move{let account=required(&v,"reconcile-account","资金账户")?;let actual=decimal(&v,"reconcile-actual","实际余额")?;let date=date(&v,"reconcile-date")?;let note=read_optional(&v,"reconcile-note").unwrap_or_default();let r=fui::services().finance_create_reconciliation(account,date,actual,note).await?;fui::notice("对账预览已保存，余额尚未改变");Ok(Some(format!("/activity/reconcile/{}",r.id)))}))
        },
    )
}
fn receipt(id: String) -> AnyElement {
    let s = fui::services();
    let load = id.clone();
    loaded(
        "对账预览",
        move || {
            let s = s.clone();
            let id = load.clone();
            Box::pin(async move {
                let r = s
                    .finance_reconciliations()
                    .await?
                    .into_iter()
                    .find(|r| r.id == id)
                    .ok_or("对账记录不存在")?;
                let a = s
                    .finance_accounts(true)
                    .await?
                    .into_iter()
                    .find(|(a, _)| a.id == r.account_id)
                    .map(|(a, _)| a.name)
                    .unwrap_or_else(|| "账户不可用".into());
                Ok((r, a))
            })
        },
        move |(r, account)| {
            let mut body = view()
                .gap_3()
                .child(heading(account))
                .child(detail("对账日期", ui::ymd(r.date)))
                .child(detail("账本原余额", amount(r.before, &r.currency)))
                .child(detail("实际余额", amount(r.actual, &r.currency)))
                .child(fui::metric(
                    "需要调整".into(),
                    amount(r.difference, &r.currency),
                    if r.difference.is_zero() {
                        "余额一致，确认后保存核对证据"
                    } else {
                        "确认后写入平衡的权益调整，不计作收入或支出"
                    }
                    .into(),
                ))
                .child(detail(
                    "核对说明",
                    if r.note.is_empty() {
                        "未填写".into()
                    } else {
                        r.note.clone()
                    },
                ));
            match r.status {
                ReconciliationStatus::Review => {
                    let id = r.id.clone();
                    body=body.child(copy("如果此日期以前的流水已发生变化，确认会被拒绝。请重新建立预览，核对新的差额。" )).child(mutation("确认对账结果","reconcile-confirm","对账结果已确认，账户余额与证据已更新",move||{let id=id.clone();Box::pin(async move{fui::services().finance_confirm_reconciliation(id.clone()).await?;Ok(Some(format!("/activity/reconcile/{id}")))})})).child(go("重新建立对账预览","reconcile-recreate",format!("/activity/reconcile/new/{}/{}",r.account_id,ui::ymd(r.date)))).child(go("放弃此预览","reconcile-cancel",format!("/activity/reconcile/{}/cancel",r.id)));
                }
                ReconciliationStatus::Confirmed => {
                    body=body.child(copy("已保存对账证据。后续更正会重新影响余额；月结会再次核对证据是否仍然一致。" )).child(go("撤销此对账调整","reconcile-undo",format!("/activity/reconcile/{}/undo",r.id)));
                    if let Some(jid) = r.journal_id {
                        body = body.child(go(
                            "查看调整流水",
                            "reconcile-open-entry",
                            format!("/activity/entry/{jid}"),
                        ));
                    }
                }
                ReconciliationStatus::Undone => {
                    body = body.child(copy("此对账已撤销。需要时可重新建立实际余额预览。"))
                }
            }
            fui::page("账户对账", body)
        },
    )
}
fn undo(id: String) -> AnyElement {
    fui::page("撤销对账调整",view().gap_3().child(copy("撤销此对账创建的权益调整并保留撤销记录。若调整流水已被修改，撤销会被拒绝，请先单独核对。" )).child(mutation("撤销此对账调整","reconcile-undo-confirm","对账调整已撤销",move||{let id=id.clone();Box::pin(async move{fui::services().finance_undo_reconciliation(id.clone()).await?;Ok(Some(format!("/activity/reconcile/{id}")))})})))
}
fn cancel(id: String) -> AnyElement {
    fui::page(
        "放弃对账预览",
        view()
            .gap_3()
            .child(copy("此预览尚未产生调整流水。放弃后不会改变账户余额。"))
            .child(mutation(
                "放弃此预览",
                "reconcile-cancel-confirm",
                "对账预览已放弃",
                move || {
                    let id = id.clone();
                    Box::pin(async move {
                        fui::services().finance_cancel_reconciliation(id).await?;
                        Ok(Some("/activity/reconcile".into()))
                    })
                },
            )),
    )
}
