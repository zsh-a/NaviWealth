use super::*;
use crate::finance::RecordKind;

pub(super) fn render(parts: Vec<String>) -> AnyElement {
    let Some(id) = parts.get(2).cloned() else {
        return list();
    };
    if id == "new" {
        return capture();
    }
    if id == "paste" {
        return capture_paste();
    }
    match parts.get(3).map(String::as_str) {
        Some("account") => account(id),
        Some("preview") => preview(id),
        Some("undo") => undo(id),
        Some("cancel") => cancel(id),
        Some("row") => {
            if let Some(row) = parts.get(4) {
                row_page(id, row.clone(), parts.get(5).cloned())
            } else {
                list()
            }
        }
        _ => batch(id),
    }
}
fn list() -> AnyElement {
    let s = fui::services();
    loaded(
        "账单导入",
        move || {
            let s = s.clone();
            Box::pin(async move { s.finance_imports().await })
        },
        move |sessions| {
            let mut body = view()
                .gap_3()
                .child(copy(
                    "先选择来源账户，再逐行核对日期、方向与分类。确认批次后才会更新流水和余额。",
                ))
                .child(go(
                    "导入通用 CSV",
                    "import-new",
                    "/activity/import/new".into(),
                ));
            if sessions.is_empty() {
                body = body.child(copy("还没有导入批次。支持粘贴 UTF-8 CSV，原始文件不上传。"));
            }
            for session in sessions {
                let route = format!("/activity/import/{}", session.id);
                let state = match session.status {
                    ImportStatus::Review => "待复核",
                    ImportStatus::Confirmed => "已入账",
                    ImportStatus::Undone => "已撤销",
                };
                body = body.child(fui::row(
                    session.source_name,
                    format!("{} · {} 行", ui::ymd(session.created_at), session.row_count),
                    state.into(),
                    format!("import-batch-{}", session.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("账单导入", body)
        },
    )
}
fn capture() -> AnyElement {
    let busy = signal(false);
    let error = signal(String::new());
    fui::page("导入通用 CSV",view().gap_3().child(copy("从设备选择 UTF-8 CSV 账单，或粘贴通用 CSV 内容。先生成本地复核批次，确认前不会写入流水。"))
    .child(ui::primary_button("选择 CSV 文件",move||{
        if busy.get(){return;}busy.set(true);error.set(String::new());
        spawn(async move {
            let result=crate::native_files::import_statement_csv().await;
            match result {
                Ok(Some(csv))=>{
                    let name=format!("CSV账单 · {}",chrono::Local::now().format("%Y-%m-%d %H:%M"));
                    match fui::services().finance_import_csv(name,csv).await {
                        Ok(session)=>{busy.set(false);fui::notice("CSV 已读取并建立本地复核批次，请选择来源账户");fui::finish(Some(format!("/activity/import/{}",session.id)),false);return;},
                        Err(e)=>error.set(e),
                    }
                },
                Ok(None)=>fui::notice("已取消文件选择，未创建导入批次"),
                Err(e)=>error.set(e),
            }
            busy.set(false);
        });
    },"import-file",Some(busy)))
    .child(when(move||busy.get(),||copy("正在选择并读取文件…")))
    .child(ui::error_line(error))
    .child(go("粘贴 CSV 内容","import-paste","/activity/import/paste".into()))
    .child(fui::section("通用列契约",view().gap_2().child(copy(STATEMENT_CSV_HEADER)).child(copy("每行依次为日期、正数金额、大写币种、expense 或 income、对方、备注。日期使用 YYYY-MM-DD；带逗号的文字加双引号。文件上限 10 MB。")))))
}
fn capture_paste() -> AnyElement {
    fui::form("导入通用 CSV",vec![
  Field::text("import-source","来源名称","").help("例如银行与账单月份；不会自动推断账户。"),
  Field::multiline("import-csv","CSV 内容",format!("{STATEMENT_CSV_HEADER}\n")).help("表头保持原样；date 为 YYYY-MM-DD，amount 为正数，direction 为 expense 或 income。含逗号或换行的字段加双引号。"),
 ],move|values|Box::pin(async move{let source=required(&values,"import-source","来源名称")?;let csv=required(&values,"import-csv","CSV 内容")?;let session=fui::services().finance_import_csv(source,csv).await?;fui::notice("已建立本地复核批次，尚未写入流水");Ok(Some(format!("/activity/import/{}",session.id)))}))
}
fn batch(id: String) -> AnyElement {
    let s = fui::services();
    let load = id.clone();
    loaded(
        "账单批次",
        move || {
            let s = s.clone();
            let id = load.clone();
            Box::pin(async move {
                let sessions = s.finance_imports().await?;
                let session = sessions
                    .into_iter()
                    .find(|x| x.id == id)
                    .ok_or("找不到导入批次，请返回列表刷新")?;
                let rows = s.finance_import_rows(id.clone()).await?;
                let undo = if session.status == ImportStatus::Confirmed {
                    Some(s.finance_import_undo_readiness(id).await?)
                } else {
                    None
                };
                Ok((session, rows, undo))
            })
        },
        move |(session, rows, undo)| {
            let mut body = view()
                .gap_3()
                .child(heading(session.source_name.clone()))
                .child(detail(
                    "批次状态",
                    match session.status {
                        ImportStatus::Review => "待复核，尚未入账",
                        ImportStatus::Confirmed => "已确认入账",
                        ImportStatus::Undone => "已撤销",
                    },
                ));
            if session.status == ImportStatus::Review {
                body=body.child(go(if session.source_account_id.is_some(){"更换来源账户"}else{"选择来源账户"},"import-account",format!("/activity/import/{}/account",session.id)))
   .child(copy("逐行查看原始解析结果。日期或金额错误可完整更正；不导入的行需要明确填写跳过原因。"));
            }
            if let Some(result) = &session.confirmation {
                body = body.child(fui::metric(
                    "实际入账".into(),
                    format!("{} 笔", result.created),
                    format!(
                        "{} 行重复已跳过 · {} 行明确排除",
                        result.duplicates, result.excluded
                    ),
                ));
            }
            for row in rows {
                let d = row.draft.as_ref();
                let title = d
                    .map(|v| {
                        if v.counterparty.is_empty() {
                            format!("第 {} 行", row.row_number)
                        } else {
                            v.counterparty.clone()
                        }
                    })
                    .unwrap_or_else(|| format!("第 {} 行 · 解析失败", row.row_number));
                let subtitle = if !row.problems.is_empty() {
                    row.problems.join("；")
                } else {
                    d.map(|d| {
                        format!(
                            "{} · {} · {}",
                            ui::ymd(d.date),
                            if d.signed_amount < Decimal::ZERO {
                                "支出"
                            } else {
                                "收入"
                            },
                            if row.reviewed {
                                "已复核"
                            } else {
                                "待分类复核"
                            }
                        )
                    })
                    .unwrap_or_default()
                };
                let trailing = if row.duplicate_of.is_some() {
                    "重复已跳过".into()
                } else {
                    d.map(|d| amount(d.signed_amount, &d.currency))
                        .unwrap_or_else(|| "待更正".into())
                };
                let route = format!("/activity/import/{}/row/{}", session.id, row.id);
                body = body.child(fui::row(
                    title,
                    subtitle,
                    trailing,
                    format!("import-row-{}", row.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            match session.status {
                ImportStatus::Review => {
                    body = body
                        .child(go(
                            "查看重复证据与入账预览",
                            "import-preview",
                            format!("/activity/import/{}/preview", session.id),
                        ))
                        .child(go(
                            "放弃此复核批次",
                            "import-cancel",
                            format!("/activity/import/{}/cancel", session.id),
                        ));
                }
                ImportStatus::Confirmed => {
                    if let Some(undo) = undo {
                        if undo.can_undo {
                            body = body.child(go(
                                "撤销此批次创建的流水",
                                "import-undo",
                                format!("/activity/import/{}/undo", session.id),
                            ));
                        } else {
                            body = body.child(copy(&undo.message)).child(fui::action(
                                "刷新完整批次回执",
                                "import-undo-retry",
                                fui::refresh,
                            ));
                        }
                    }
                    body = body.child(go(
                        "查看活动流水",
                        "import-open-activity",
                        "/activity".into(),
                    ));
                }
                ImportStatus::Undone => {}
            }
            fui::page("账单批次", body)
        },
    )
}
fn account(id: String) -> AnyElement {
    let s = fui::services();
    let load = id.clone();
    loaded_mode(
        "来源账户",
        true,
        move || {
            let s = s.clone();
            let id = load.clone();
            Box::pin(async move {
                let session = s
                    .finance_imports()
                    .await?
                    .into_iter()
                    .find(|v| v.id == id)
                    .ok_or("批次不存在")?;
                let accounts = s.finance_accounts(false).await?;
                Ok((session, accounts))
            })
        },
        move |(session, accounts)| {
            if accounts.is_empty() {
                return fui::page(
                    "来源账户",
                    view()
                        .gap_3()
                        .child(copy(
                            "先建立实际资金账户，再导入该账户的账单。每批次只能分配一个来源账户。",
                        ))
                        .child(go(
                            "建立账户",
                            "import-create-account",
                            "/wealth/accounts/new".into(),
                        )),
                );
            }
            let options = accounts
                .into_iter()
                .map(|(a, _)| (a.id, format!("{} · {}", a.name, a.currency)))
                .collect();
            let id = session.id.clone();
            fui::form(
                "来源账户",
                vec![
                    Field::choice(
                        "import-source-account",
                        "账单所属账户",
                        session.source_account_id.unwrap_or_default(),
                        options,
                    )
                    .help("账单币种必须与账户一致；跨账户文件请分批处理。"),
                ],
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        let account = required(&v, "import-source-account", "来源账户")?;
                        fui::services()
                            .finance_assign_import_account(id.clone(), account)
                            .await?;
                        fui::notice("来源账户已分配");
                        Ok(Some(format!("/activity/import/{id}")))
                    })
                },
            )
        },
    )
}
fn preview(id: String) -> AnyElement {
    let s = fui::services();
    let load = id.clone();
    loaded(
        "确认入账预览",
        move || {
            let s = s.clone();
            let id = load.clone();
            Box::pin(async move { s.finance_import_preview(id).await })
        },
        move |preview| {
            let mut body=view().gap_3().child(fui::metric("将写入流水".into(),format!("{} 笔",preview.created),format!("重复 {} 行 · 明确排除 {} 行",preview.duplicates,preview.excluded))).child(copy("重复判定使用同一账户的日期、带方向金额、币种与对方；提交时会再次检查。只写入已复核且不重复的行。"));
            for b in &preview.blockers {
                body = body.child(copy(b));
            }
            for row in preview.rows {
                let state = if let Some(other) = row.duplicate_of.as_ref() {
                    format!(
                        "与 {} 的交易证据一致，将跳过",
                        if other.starts_with("row:") {
                            "本批次另一行"
                        } else {
                            "已有流水"
                        }
                    )
                } else if row.will_create {
                    "已复核，将创建流水".into()
                } else if row.problems.is_empty() {
                    "明确排除，不会入账".into()
                } else {
                    row.problems.join("；")
                };
                let route = format!("/activity/import/{}/row/{}", preview.session_id, row.row_id);
                body = body.child(fui::row(
                    format!("第 {} 行", row.row_number),
                    state,
                    if row.will_create { "入账" } else { "查看" }.into(),
                    format!("import-preview-{}", row.row_id),
                    move || fui::navigate(route.clone()),
                ));
            }
            if preview.can_confirm {
                let sid = preview.session_id.clone();
                body = body.child(mutation(
                    "确认此批次入账",
                    "import-confirm",
                    "批次已确认，活动流水与账户余额已更新",
                    move || {
                        let sid = sid.clone();
                        Box::pin(async move {
                            let result =
                                fui::services().finance_confirm_import(sid.clone()).await?;
                            fui::notice(format!(
                                "已创建 {} 笔流水，跳过 {} 行重复",
                                result.created, result.duplicates
                            ));
                            Ok(Some(format!("/activity/import/{sid}")))
                        })
                    },
                ));
            } else {
                body = body.child(go(
                    "返回批次补全复核",
                    "import-return-review",
                    format!("/activity/import/{}", preview.session_id),
                ));
            }
            fui::page("确认入账预览", body)
        },
    )
}
fn undo(id: String) -> AnyElement {
    let services = fui::services();
    let load = id.clone();
    loaded(
        "撤销导入批次",
        move || {
            let s = services.clone();
            let id = load.clone();
            Box::pin(async move { s.finance_import_undo_readiness(id).await })
        },
        move |readiness| {
            let mut body = view().gap_3().child(copy(&readiness.message));
            if readiness.can_undo {
                let target = id.clone();
                body=body.child(copy("仅撤销由此批次创建的流水和余额影响。原本存在的重复流水会保留；批次中有流水被修改时，整批撤销会被拒绝，避免覆盖后续更正。"))
            .child(detail("将撤销的批次流水",format!("{} 笔",readiness.created)))
            .child(mutation("撤销此批次创建的流水","import-undo-confirm","批次已撤销，账户余额已恢复",move||{let id=target.clone();Box::pin(async move{let removed=fui::services().finance_undo_import(id.clone()).await?;fui::notice(format!("已撤销 {removed} 笔批次流水"));Ok(Some(format!("/activity/import/{id}")))})}));
            } else {
                body = body.child(fui::action(
                    "刷新完整批次回执",
                    "import-undo-retry",
                    fui::refresh,
                ));
            }
            body = body.child(go(
                "返回批次详情",
                "import-undo-return",
                format!("/activity/import/{id}"),
            ));
            fui::page("撤销导入批次", body)
        },
    )
}

fn cancel(id: String) -> AnyElement {
    fui::page(
        "放弃复核批次",
        view()
            .gap_3()
            .child(copy(
                "此批次尚未写入流水。放弃后保留批次记录，不会改变账户余额。",
            ))
            .child(mutation(
                "放弃此批次",
                "import-cancel-confirm",
                "复核批次已放弃",
                move || {
                    let id = id.clone();
                    Box::pin(async move {
                        fui::services().finance_cancel_import(id).await?;
                        Ok(Some("/activity/import".into()))
                    })
                },
            )),
    )
}

#[path = "import_rows.rs"]
mod rows;
use rows::*;
