use super::*;

pub(super) fn snapshot(month: String) -> AnyElement {
    let s = fui::services();
    loaded(
        "已保存月结",
        move || {
            let s = s.clone();
            let month = month.clone();
            Box::pin(async move { s.finance_month_close_readiness(month).await })
        },
        move |r| {
            let Some(s) = r.saved_snapshot else {
                return fui::page("已保存月结", copy("此月份尚未保存月结快照。"));
            };
            let mut body=view().gap_3().child(heading(format!("{} 月结快照",s.month))).child(copy(&format!("保存于 {}；此处展示保存时的事实与覆盖原因。后续来源变化需要返回工作台重新复盘。",ui::ymd(s.closed_at)))).child(fui::metric("月末净资产".into(),s.net_worth.map(|v|amount(v,&s.base_currency)).unwrap_or_else(||"估值证据不完整".into()),s.net_worth_change.map(|v|format!("较 {} 变动 {}",s.previous_month.as_deref().unwrap_or("上月"),amount(v,&s.base_currency))).unwrap_or_else(||"暂无相同本位币的完整上月快照比较".into())));
            for t in s.totals {
                body = body.child(fui::section(
                    "月度收支",
                    view()
                        .child(detail(
                            &format!("收入 · {}", t.currency),
                            ui::money_for(t.income, &t.currency),
                        ))
                        .child(detail(
                            &format!("支出 · {}", t.currency),
                            ui::money_for(t.expense, &t.currency),
                        )),
                ));
            }
            for a in s.accounts {
                body = body.child(detail(&a.name, amount(a.balance, &a.currency)));
            }
            for gap in s.missing_prices {
                body = body.child(copy(&format!("价格缺口：{gap}")));
            }
            for gap in s.missing_fx {
                body = body.child(copy(&format!("汇率缺口：{gap}")));
            }
            for review in s.reviews {
                body = body.child(fui::section(
                    review.step.label(),
                    view().child(detail("结论", review.note)).child(copy(
                        review
                            .override_reason
                            .as_deref()
                            .unwrap_or("按真实来源核实，无覆盖原因"),
                    )),
                ));
            }
            body = body.child(go(
                "返回月结工作台",
                "close-snapshot-workbench",
                format!("/activity/close/{}", r.month),
            ));
            fui::page("已保存月结", body)
        },
    )
}
