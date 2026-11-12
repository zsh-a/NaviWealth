use super::*;
pub(super) fn render(parts: Vec<String>) -> AnyElement {
    let Some(month) = parts.get(2).cloned() else {
        return months();
    };
    match parts.get(3).map(String::as_str) {
        Some("step") => {
            if let Some(step) = parts.get(4).and_then(|s| parse_step(s)) {
                step_page(month, step, parts.get(5).is_some_and(|p| p == "review"))
            } else {
                overview(month)
            }
        }
        Some("finalize") => finalize(month),
        Some("snapshot") => snapshot(month),
        _ => overview(month),
    }
}
fn key(step: CloseStep) -> &'static str {
    match step {
        CloseStep::ImportReview => "import",
        CloseStep::InboxClear => "inbox",
        CloseStep::AccountReconcile => "accounts",
        CloseStep::RunwayReview => "runway",
        CloseStep::ActionReview => "actions",
    }
}
fn parse_step(s: &str) -> Option<CloseStep> {
    CloseStep::ALL.into_iter().find(|step| key(*step) == s)
}
fn status(s: CloseStepStatus) -> &'static str {
    match s {
        CloseStepStatus::Blocked => "有阻塞",
        CloseStepStatus::Ready => "待复盘",
        CloseStepStatus::Verified => "已核实",
        CloseStepStatus::Overridden => "明确覆盖",
    }
}
fn months() -> AnyElement {
    let s = fui::services();
    loaded(
        "月结",
        move || {
            let s = s.clone();
            Box::pin(async move { s.finance_month_closes().await })
        },
        move |closes| {
            let mut body=view().gap_3().child(copy("逐步复核账单、收件箱、账户、现金跑道和行动。每一步保存真实来源证据；数据变化后需要重新复盘。" )).child(go("开始上月月结","close-last-month",format!("/activity/close/{}",previous_month())));
            body = body.child(fui::section("已保存的月结", {
                let mut list = view();
                if closes.is_empty() {
                    list = list.child(copy("暂无已保存月结。"));
                }
                for close in closes {
                    let route = format!("/activity/close/{}", close.month);
                    list = list.child(fui::row(
                        close.month,
                        format!("已复盘 {} / 5 步", close.steps.len()),
                        if close.snapshot.is_some() {
                            "已保存快照"
                        } else {
                            "进行中"
                        }
                        .into(),
                        format!("month-close-{}", close.id),
                        move || fui::navigate(route.clone()),
                    ));
                }
                list
            }));
            body = body.child(go(
                "选择其他月份",
                "close-select-month",
                "/activity/close/select".into(),
            ));
            fui::page("月结", body)
        },
    )
}
fn overview(month: String) -> AnyElement {
    if month == "select" {
        return fui::form(
            "选择月结月份",
            vec![
                Field::text("close-month", "月份", previous_month())
                    .help("格式 YYYY-MM，例如上一个已结束月份。"),
            ],
            move |v| {
                Box::pin(async move {
                    let month = required(&v, "close-month", "月份")?;
                    fui::services()
                        .finance_month_close_readiness(month.clone())
                        .await?;
                    Ok(Some(format!("/activity/close/{month}")))
                })
            },
        );
    }
    let s = fui::services();
    let load = month.clone();
    loaded(
        "月结工作台",
        move || {
            let s = s.clone();
            let month = load.clone();
            Box::pin(async move { s.finance_month_close_readiness(month).await })
        },
        move |readiness| {
            let done = readiness
                .steps
                .iter()
                .filter(|s| {
                    matches!(
                        s.status,
                        CloseStepStatus::Verified | CloseStepStatus::Overridden
                    )
                })
                .count();
            let mut body=view().gap_3().child(heading(format!("{} 月结",readiness.month))).child(copy(&format!("已完成 {done} / 5 步。阻塞不会因收件箱备注或一次点击而消失；确需继续时，须保存明确覆盖原因。")));
            for s in readiness.steps {
                let route = format!("/activity/close/{}/step/{}", readiness.month, key(s.step));
                let subtitle = if s.blockers.is_empty() {
                    s.review
                        .as_ref()
                        .map(|r| r.note.clone())
                        .unwrap_or_else(|| "来源证据就绪，请查看并记录复盘结论".into())
                } else {
                    s.blockers.join("；")
                };
                body = body.child(fui::row(
                    s.step.label().into(),
                    subtitle,
                    status(s.status).into(),
                    format!("close-step-{}", key(s.step)),
                    move || fui::navigate(route.clone()),
                ));
            }
            if readiness.ready {
                body = body.child(go(
                    "复核并保存月结快照",
                    "close-finalize",
                    format!("/activity/close/{}/finalize", readiness.month),
                ));
            }
            if let Some(snapshot) = readiness.saved_snapshot {
                body = body.child(go(
                    "查看已保存月结快照",
                    "close-open-snapshot",
                    format!("/activity/close/{}/snapshot", snapshot.month),
                ));
            }
            fui::page("月结工作台", body)
        },
    )
}
fn step_page(month: String, step: CloseStep, review: bool) -> AnyElement {
    let s = fui::services();
    let load = month.clone();
    loaded_mode(
        "月结来源证据",
        review,
        move || {
            let s = s.clone();
            let month = load.clone();
            Box::pin(async move {
                let ready = s.finance_month_close_readiness(month).await?;
                let accounts = s.finance_accounts(true).await?;
                Ok((ready, accounts))
            })
        },
        move |(readiness, accounts)| {
            let Some(current) = readiness.steps.into_iter().find(|s| s.step == step) else {
                return fui::page("月结来源证据", copy("步骤不存在，请返回月结工作台。"));
            };
            if review {
                let month = readiness.month;
                let has_blockers = !current.blockers.is_empty();
                return fui::form(
                    "记录月结复盘",
                    vec![
                        Field::multiline(
                            "close-review-note",
                            "本步骤复盘结论",
                            current
                                .review
                                .as_ref()
                                .map(|r| r.note.clone())
                                .unwrap_or_default(),
                        )
                        .help("保存你核对真实来源后的结论。来源变化时，本次核实会失效。"),
                        Field::multiline(
                            "close-review-override",
                            "覆盖阻塞的明确原因",
                            current
                                .review
                                .as_ref()
                                .and_then(|r| r.override_reason.clone())
                                .unwrap_or_default(),
                        )
                        .help("仅在确认保留未解决问题并继续月结时填写。问题与证据仍会保留。")
                        .show_when(move || has_blockers),
                    ],
                    move |v| {
                        let month = month.clone();
                        Box::pin(async move {
                            let note = required(&v, "close-review-note", "复盘结论")?;
                            let reason = read_optional(&v, "close-review-override");
                            fui::services()
                                .finance_review_month_step(month.clone(), step, note, reason)
                                .await?;
                            fui::notice("已保存本步骤的来源证据与复盘结论");
                            Ok(Some(format!("/activity/close/{month}")))
                        })
                    },
                );
            }
            let mut body = view()
                .gap_3()
                .child(heading(current.step.label()))
                .child(detail("核实状态", status(current.status)));
            for blocker in &current.blockers {
                body = body.child(copy(&format!("待处理：{blocker}")));
            }
            match step {
                CloseStep::ImportReview => {
                    let count = current.evidence["sessions"]
                        .as_array()
                        .map(Vec::len)
                        .unwrap_or(0);
                    body=body.child(detail("相关账单批次",format!("{count} 批"))).child(copy("本月记录所在批次与日期未知的问题行都纳入核对；只有确认入账或明确放弃的批次才算处理完成。" )).child(go("处理账单批次","close-source-import","/activity/import".into()));
                }
                CloseStep::InboxClear => {
                    if let Some(issues) = current.evidence["issues"].as_array() {
                        for issue in issues {
                            if let Ok(issue) =
                                serde_json::from_value::<FinancialIssue>(issue.clone())
                            {
                                body = body.child(detail(&issue.title, issue.detail));
                            }
                        }
                    }
                    body = body.child(go(
                        "打开财务收件箱",
                        "close-source-inbox",
                        "/today/inbox".into(),
                    ));
                }
                CloseStep::AccountReconcile => {
                    if let Some(rows) = current.evidence["accounts"].as_array() {
                        for row in rows {
                            let account = row["account_id"].as_str().unwrap_or_default();
                            let name = accounts
                                .iter()
                                .find(|(a, _)| a.id == account)
                                .map(|(a, _)| a.name.clone())
                                .unwrap_or_else(|| "账户".into());
                            let currency = row["currency"].as_str().unwrap_or_default();
                            let balance = row["balance"].as_str().unwrap_or("无法读取");
                            let checked = !row["reconciliation"].is_null();
                            let last =
                                month_last_date(&readiness.month).unwrap_or_else(ui::today_text);
                            let route = format!("/activity/reconcile/new/{account}/{last}");
                            body = body.child(fui::row(
                                name,
                                if checked {
                                    "月末实际余额与账本一致"
                                } else {
                                    "需要核对月末实际余额"
                                }
                                .into(),
                                format!("{balance} {currency}"),
                                format!("close-account-{account}"),
                                move || fui::navigate(route.clone()),
                            ));
                        }
                    }
                    let wealth = &current.evidence["valuation"];
                    let worth = wealth["net_worth"].as_str().unwrap_or("估值证据不完整");
                    body = body
                        .child(detail(
                            "月末净资产",
                            format!(
                                "{worth} {}",
                                wealth["base_currency"].as_str().unwrap_or_default()
                            ),
                        ))
                        .child(go(
                            "查看资产估值证据",
                            "close-source-wealth",
                            "/wealth".into(),
                        ));
                }
                CloseStep::RunwayReview => {
                    let e = &current.evidence;
                    let currency = e["currency"].as_str().unwrap_or_default();
                    body = body
                        .child(detail(
                            "计划范围",
                            format!(
                                "月末起未来 {} 天 · {currency}",
                                e["horizon_days"].as_u64().unwrap_or(90)
                            ),
                        ))
                        .child(detail(
                            "起始现金",
                            e["starting_balance"].as_str().unwrap_or("无法读取"),
                        ))
                        .child(detail(
                            "计划末现金",
                            e["predicted_balance"].as_str().unwrap_or("无法读取"),
                        ))
                        .child(detail(
                            "计划最低现金",
                            e["min_balance"].as_str().unwrap_or("无法读取"),
                        ));
                    if let Some(assumptions) = e["assumptions"].as_array() {
                        for a in assumptions {
                            if let Some(a) = a.as_str() {
                                body = body.child(copy(a));
                            }
                        }
                    }
                    if let Some(flows) = e["flows"].as_array() {
                        for f in flows {
                            body = body.child(detail(
                                &ui::ymd(f[1].as_i64().unwrap_or_default()),
                                format!(
                                    "{} {}",
                                    f[2].as_str().unwrap_or("无法读取"),
                                    f[3].as_str().unwrap_or_default()
                                ),
                            ));
                        }
                    }
                    body = body.child(go(
                        "查看现金跑道与计划",
                        "close-source-runway",
                        "/plan/runway".into(),
                    ));
                }
                CloseStep::ActionReview => {
                    if let Some(actions) = current.evidence["actions"].as_array() {
                        if actions.is_empty() {
                            body=body.child(copy("此范围内没有已录入的周期、贷款或定投行动。未录入的计划不在此次复盘范围。"));
                        }
                        for a in actions {
                            body = body.child(detail(
                                a["name"].as_str().unwrap_or("计划行动"),
                                format!(
                                    "{} · {} {} · {}",
                                    ui::ymd(a["due"].as_i64().unwrap_or_default()),
                                    a["amount"].as_str().unwrap_or("无法读取"),
                                    a["currency"].as_str().unwrap_or_default(),
                                    match a["state"].as_str() {
                                        Some("Posted") => "已入账",
                                        Some("Skipped") => "已明确跳过",
                                        _ => "尚未处理",
                                    }
                                ),
                            ));
                        }
                    }
                    body = body.child(go("处理计划行动", "close-source-actions", "/plan".into()));
                }
            }
            if let Some(r) = &current.review {
                body = body.child(fui::section(
                    "已保存的复盘",
                    view()
                        .child(detail("结论", r.note.clone()))
                        .child(detail("记录日期", ui::ymd(r.reviewed_at)))
                        .child(copy(
                            r.override_reason
                                .as_deref()
                                .unwrap_or("无覆盖原因，按真实就绪状态核实"),
                        )),
                ));
            }
            body = body.child(go(
                if current.blockers.is_empty() {
                    "记录核实结论"
                } else {
                    "记录处理结论或明确覆盖原因"
                },
                "close-review-step",
                format!(
                    "/activity/close/{}/step/{}/review",
                    readiness.month,
                    key(step)
                ),
            ));
            fui::page("月结来源证据", body)
        },
    )
}
fn month_last_date(month: &str) -> Option<String> {
    let first = chrono::NaiveDate::parse_from_str(&format!("{month}-01"), "%Y-%m-%d").ok()?;
    let next = if first.month() == 12 {
        chrono::NaiveDate::from_ymd_opt(first.year() + 1, 1, 1)?
    } else {
        chrono::NaiveDate::from_ymd_opt(first.year(), first.month() + 1, 1)?
    };
    Some(
        (next - chrono::Duration::days(1))
            .format("%Y-%m-%d")
            .to_string(),
    )
}
fn finalize(month: String) -> AnyElement {
    let s = fui::services();
    let load = month.clone();
    loaded(
        "保存月结快照",
        move || {
            let s = s.clone();
            let month = load.clone();
            Box::pin(async move { s.finance_month_close_readiness(month).await })
        },
        move |r| {
            let mut body=view().gap_3().child(heading(format!("{} 月结",r.month))).child(copy("保存该月真实余额、收支、估值缺口、复盘结论与上一份月结比较。当前月份结束前不能完成月结。"));
            for step in r.steps {
                body = body.child(detail(step.step.label(), status(step.status)));
            }
            if r.ready {
                let month = r.month.clone();
                body = body.child(mutation(
                    "保存此月月结快照",
                    "close-save-snapshot",
                    "月结快照已保存",
                    move || {
                        let month = month.clone();
                        Box::pin(async move {
                            fui::services()
                                .finance_finalize_month_close(month.clone())
                                .await?;
                            Ok(Some(format!("/activity/close/{month}/snapshot")))
                        })
                    },
                ));
            } else {
                body = body
                    .child(copy("来源已变化或还有步骤未完成，请返回工作台重新核实。"))
                    .child(go(
                        "返回月结工作台",
                        "close-back-workbench",
                        format!("/activity/close/{}", r.month),
                    ));
            }
            fui::page("保存月结快照", body)
        },
    )
}

#[path = "close_history.rs"]
mod saved;
use saved::*;
