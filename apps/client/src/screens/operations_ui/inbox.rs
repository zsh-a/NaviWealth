use super::*;
pub(super) fn render(parts: Vec<String>) -> AnyElement {
    if let Some(encoded) = parts.get(2) {
        let Ok(key) = decode_key(encoded) else {
            return fui::page("财务收件箱", copy("此问题地址无效，请返回收件箱刷新。"));
        };
        detail_page(key, parts.get(3).is_some_and(|s| s == "note"))
    } else {
        list()
    }
}
fn now() -> i64 {
    chrono::Utc::now().timestamp()
}
fn encode_key(key: &str) -> String {
    key.as_bytes().iter().map(|b| format!("{b:02x}")).collect()
}
fn decode_key(encoded: &str) -> Result<String, String> {
    if !encoded.len().is_multiple_of(2) || !encoded.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("无效问题地址".into());
    }
    let bytes = (0..encoded.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&encoded[i..i + 2], 16).map_err(|_| "无效问题地址".to_owned()))
        .collect::<Result<Vec<_>, _>>()?;
    String::from_utf8(bytes).map_err(|_| "无效问题地址".into())
}
fn list() -> AnyElement {
    let s = fui::services();
    loaded(
        "财务收件箱",
        move || {
            let s = s.clone();
            Box::pin(async move { s.finance_inbox(now()).await })
        },
        move |issues| {
            let blocked = issues.iter().filter(|i| i.blocking).count();
            let mut body=view().gap_3().child(copy(&format!("{blocked} 项需要处理。这里列出真实账单问题、到期计划和估值缺口；处理说明会保留，实际问题需要在来源中解决。")));
            if issues.is_empty() {
                body = body.child(heading("当前没有待处理事项")).child(copy(
                    "已录入的账单、计划与估值来源没有产生待处理项。未录入的事项不在核验范围。",
                ));
            }
            for issue in issues {
                let route = format!("/today/inbox/{}", encode_key(&issue.key));
                let subtitle = if let Some(due) = issue.due {
                    format!("{} · {}", ui::ymd(due), issue.detail)
                } else {
                    issue.detail
                };
                let trailing = if issue.note.is_some() {
                    if issue.blocking {
                        "已说明 · 待核验"
                    } else {
                        "已说明"
                    }
                } else if issue.blocking {
                    "待处理"
                } else {
                    "即将到期"
                };
                body = body.child(fui::row(
                    issue.title,
                    subtitle,
                    trailing.into(),
                    format!("inbox-{}", encode_key(&issue.key)),
                    move || fui::navigate(route.clone()),
                ));
            }
            body = body.child(go(
                "查看月结工作台",
                "inbox-open-close",
                "/activity/close".into(),
            ));
            fui::page("财务收件箱", body)
        },
    )
}
fn detail_page(key: String, note: bool) -> AnyElement {
    let s = fui::services();
    let load = key.clone();
    loaded_mode(
        "财务事项",
        note,
        move || {
            let s = s.clone();
            let key = load.clone();
            Box::pin(async move {
                let issues = s.finance_inbox(now()).await?;
                Ok(issues.into_iter().find(|i| i.key == key))
            })
        },
        move |issue| {
            let Some(issue) = issue else {
                return fui::page(
                    "财务事项",
                    view()
                        .gap_3()
                        .child(heading("来源中已不再产生此事项"))
                        .child(copy(
                            "请返回收件箱查看最新核验结果。历史处理说明仍保存在本地。",
                        ))
                        .child(go(
                            "返回财务收件箱",
                            "inbox-return-list",
                            "/today/inbox".into(),
                        )),
                );
            };
            if note {
                let key = issue.key.clone();
                let initial = issue
                    .note
                    .as_ref()
                    .map(|n| n.note.clone())
                    .unwrap_or_default();
                return fui::form(
                    "记录处理说明",
                    vec![
                        Field::choice(
                            "issue-disposition",
                            "说明类型",
                            "resolved",
                            vec![
                                ("resolved".into(), "记录处理情况".into()),
                                ("dismissed".into(), "暂时搁置并说明原因".into()),
                            ],
                        )
                        .help("说明不会自动清除真实到期事项、差额或估值缺口。"),
                        Field::multiline("issue-note", "处理说明", initial)
                            .help("记录已采取的行动、仍缺少的资料或下一次核实安排。"),
                    ],
                    move |v| {
                        let key = key.clone();
                        Box::pin(async move {
                            let note = required(&v, "issue-note", "处理说明")?;
                            let disposition = if read_optional(&v, "issue-disposition").as_deref()
                                == Some("dismissed")
                            {
                                IssueDisposition::Dismissed
                            } else {
                                IssueDisposition::Resolved
                            };
                            fui::services()
                                .finance_note_issue(key.clone(), disposition, note, now())
                                .await?;
                            fui::notice("处理说明已保存，来源问题仍会继续核验");
                            Ok(Some(format!("/today/inbox/{}", encode_key(&key))))
                        })
                    },
                );
            }
            let route = source_route(&issue);
            let mut body = view()
                .gap_3()
                .child(heading(issue.title.clone()))
                .child(copy(&issue.detail))
                .child(detail(
                    "来源状态",
                    if issue.blocking {
                        "实际问题尚待处理"
                    } else {
                        "尚未到期"
                    },
                ));
            if let Some(date) = issue.due {
                body = body.child(detail("相关日期", ui::ymd(date)));
            }
            body = body.child(go("打开来源处理", "inbox-open-source", route));
            if let Some(note) = &issue.note {
                body = body.child(fui::section(
                    "已保存的处理说明",
                    view()
                        .child(detail("说明", note.note.clone()))
                        .child(detail("记录日期", ui::ymd(note.recorded_at)))
                        .child(copy(
                            "此说明保留为处理记录；来源中的实际状态仍然决定是否存在阻塞。",
                        )),
                ));
            }
            body = body.child(go(
                "记录或更新处理说明",
                "inbox-note",
                format!("/today/inbox/{}/note", encode_key(&issue.key)),
            ));
            fui::page("财务事项", body)
        },
    )
}
fn source_route(issue: &FinancialIssue) -> String {
    match issue.kind {
        IssueKind::ImportReview => issue
            .key
            .strip_prefix("import:")
            .map(|id| format!("/activity/import/{id}"))
            .unwrap_or_else(|| "/activity/import".into()),
        IssueKind::Reconciliation => issue
            .key
            .strip_prefix("reconciliation:")
            .map(|id| format!("/activity/reconcile/{id}"))
            .unwrap_or_else(|| "/activity/reconcile".into()),
        IssueKind::DataIntegrity => issue
            .key
            .strip_prefix("entry:")
            .map(|id| format!("/activity/entry/{id}"))
            .unwrap_or_else(|| "/activity".into()),
        IssueKind::RecurringDue => issue
            .key
            .strip_prefix("recurring:")
            .and_then(|s| s.rsplit_once(':'))
            .map(|(id, _)| format!("/plan/recurring/{id}"))
            .unwrap_or_else(|| "/plan/recurring".into()),
        IssueKind::LiabilityDue => issue
            .key
            .strip_prefix("liability:")
            .and_then(|s| s.rsplit_once(':'))
            .map(|(id, _)| format!("/wealth/liabilities/{id}"))
            .unwrap_or_else(|| "/wealth/liabilities".into()),
        IssueKind::DcaDue => issue
            .key
            .strip_prefix("dca:")
            .and_then(|s| s.rsplit_once(':'))
            .map(|(id, _)| format!("/plan/dca/{id}"))
            .unwrap_or_else(|| "/plan/dca".into()),
        IssueKind::MissingPrice => issue
            .key
            .strip_prefix("price:")
            .map(|id| format!("/wealth/assets/{id}/price"))
            .unwrap_or_else(|| "/wealth".into()),
        IssueKind::MissingFx => "/wealth/fx".into(),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn issue_addresses_preserve_unicode_and_separators() {
        let key = "price:银行/US:AAPL";
        assert_eq!(decode_key(&encode_key(key)).unwrap(), key);
        assert!(decode_key("xxx").is_err());
        assert!(decode_key("字a").is_err());
    }
}
