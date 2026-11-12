use super::*;

pub(super) fn row_page(session: String, id: String, mode: Option<String>) -> AnyElement {
    let s = fui::services();
    let load = session.clone();
    let rowid = id.clone();
    loaded_mode(
        "复核账单行",
        mode.is_some(),
        move || {
            let s = s.clone();
            let session = load.clone();
            let id = rowid.clone();
            Box::pin(async move {
                let batch = s
                    .finance_imports()
                    .await?
                    .into_iter()
                    .find(|v| v.id == session)
                    .ok_or("批次不存在")?;
                let row = s
                    .finance_import_rows(session)
                    .await?
                    .into_iter()
                    .find(|r| r.id == id)
                    .ok_or("账单行不存在")?;
                let expenses = s.finance_categories(RecordKind::Expense).await?;
                let income = s.finance_categories(RecordKind::Income).await?;
                Ok((batch, row, expenses, income))
            })
        },
        move |(batch, row, expenses, income)| {
            if mode.as_deref() == Some("correct") {
                return correct_row(batch.id, row, expenses, income);
            }
            if mode.as_deref() == Some("exclude") {
                let sid = batch.id;
                let rid = row.id;
                return fui::form(
                    "跳过此行",
                    vec![
                        Field::multiline("import-exclude-reason", "跳过原因", "")
                            .help("原因会保存在批次中；此行不会写入流水。"),
                    ],
                    move |v| {
                        let sid = sid.clone();
                        let rid = rid.clone();
                        Box::pin(async move {
                            let reason = required(&v, "import-exclude-reason", "跳过原因")?;
                            fui::services()
                                .finance_exclude_import_row(sid.clone(), rid, reason)
                                .await?;
                            Ok(Some(format!("/activity/import/{sid}")))
                        })
                    },
                );
            }
            let mut body = view()
                .gap_3()
                .child(heading(format!("第 {} 行", row.row_number)));
            for problem in &row.problems {
                body = body.child(copy(problem));
            }
            if let Some(d) = &row.draft {
                body = body
                    .child(detail("日期", ui::ymd(d.date)))
                    .child(detail("收支金额", amount(d.signed_amount, &d.currency)))
                    .child(detail(
                        "对方",
                        if d.counterparty.is_empty() {
                            "未填写".into()
                        } else {
                            d.counterparty.clone()
                        },
                    ))
                    .child(detail(
                        "备注",
                        if d.note.is_empty() {
                            "未填写".into()
                        } else {
                            d.note.clone()
                        },
                    ))
                    .child(detail(
                        "复核结果",
                        if d.excluded {
                            "明确排除"
                        } else if row.reviewed {
                            "已复核"
                        } else {
                            "等待分类与复核"
                        },
                    ));
                if let Some(category) = &d.category_id {
                    let name = expenses
                        .iter()
                        .chain(income.iter())
                        .find(|(id, _)| id == category)
                        .map(|(_, name)| name.clone())
                        .unwrap_or_else(|| "分类已不可用".into());
                    body = body.child(detail("分类", name));
                }
            }
            if let Some(duplicate) = &row.duplicate_of {
                body = body
                    .child(copy(
                        "此行与已有流水的日期、账户、金额、币种和对方相同，确认时已跳过。",
                    ))
                    .child(detail("重复证据", duplicate.clone()));
            }
            if batch.status == ImportStatus::Review {
                body = body
                    .child(go(
                        "更正并确认此行分类",
                        "import-correct-row",
                        format!("/activity/import/{}/row/{}/correct", batch.id, row.id),
                    ))
                    .child(go(
                        "跳过此行并记录原因",
                        "import-exclude-row",
                        format!("/activity/import/{}/row/{}/exclude", batch.id, row.id),
                    ));
            }
            if let Some(jid) = &row.journal_id {
                body = body.child(go(
                    "查看已创建流水",
                    "import-open-created-record",
                    format!("/activity/entry/{jid}"),
                ));
            }
            fui::page("复核账单行", body)
        },
    )
}
pub(super) fn correct_row(
    session: String,
    row: ImportRow,
    expenses: Vec<(String, String)>,
    income: Vec<(String, String)>,
) -> AnyElement {
    let d = row.draft;
    let signed = d.as_ref().map(|d| d.signed_amount).unwrap_or_default();
    let kind = Field::choice(
        "import-direction",
        "收支方向",
        if signed > Decimal::ZERO {
            "income"
        } else {
            "expense"
        },
        vec![
            ("expense".into(), "支出".into()),
            ("income".into(), "收入".into()),
        ],
    );
    let selected = kind.value;
    let category = d
        .as_ref()
        .and_then(|d| d.category_id.clone())
        .unwrap_or_default();
    let fields = vec![
        kind,
        Field::date(
            "import-row-date",
            "日期",
            d.as_ref()
                .map(|d| ui::ymd(d.date))
                .unwrap_or_else(ui::today_text),
        ),
        Field::money(
            "import-row-amount",
            "正数金额",
            if signed.is_zero() {
                String::new()
            } else {
                signed.abs().normalize().to_string()
            },
        ),
        Field::text(
            "import-row-currency",
            "币种",
            d.as_ref()
                .map(|d| d.currency.clone())
                .unwrap_or_else(|| "CNY".into()),
        )
        .help("须与来源账户一致，使用大写代码。"),
        Field::choice(
            "import-expense-category",
            "支出分类",
            category.clone(),
            expenses,
        )
        .show_when(move || selected.get() == "expense"),
        Field::choice("import-income-category", "收入分类", category, income)
            .show_when(move || selected.get() == "income"),
        Field::text(
            "import-row-payee",
            "对方",
            d.as_ref()
                .map(|d| d.counterparty.clone())
                .unwrap_or_default(),
        ),
        Field::multiline(
            "import-row-note",
            "备注",
            d.as_ref().map(|d| d.note.clone()).unwrap_or_default(),
        ),
        Field::multiline(
            "import-row-duplicate-reason",
            "保留相同交易的原因（选填）",
            d.as_ref()
                .and_then(|d| d.duplicate_override_reason.clone())
                .unwrap_or_default(),
        )
        .help("仅当重复证据相同但确为另一笔真实交易时填写；通常留空以跳过重复。"),
    ];
    let rid = row.id;
    fui::form("更正与分类", fields, move |v| {
        let sid = session.clone();
        let rid = rid.clone();
        Box::pin(async move {
            let magnitude = decimal(&v, "import-row-amount", "金额")?;
            if magnitude <= Decimal::ZERO {
                return Err("金额必须大于零".into());
            }
            let expense = required(&v, "import-direction", "收支方向")? == "expense";
            let review = RowReview {
                date: date(&v, "import-row-date")?,
                signed_amount: if expense { -magnitude } else { magnitude },
                currency: required(&v, "import-row-currency", "币种")?.to_uppercase(),
                counterparty: read_optional(&v, "import-row-payee").unwrap_or_default(),
                note: read_optional(&v, "import-row-note").unwrap_or_default(),
                category_id: Some(required(
                    &v,
                    if expense {
                        "import-expense-category"
                    } else {
                        "import-income-category"
                    },
                    "分类",
                )?),
                excluded: false,
                duplicate_override_reason: read_optional(&v, "import-row-duplicate-reason"),
            };
            fui::services()
                .finance_review_import_row(sid.clone(), rid, review)
                .await?;
            fui::notice("此行已复核，确认批次后才会入账");
            Ok(Some(format!("/activity/import/{sid}")))
        })
    })
}
