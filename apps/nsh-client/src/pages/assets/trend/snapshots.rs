use super::*;

pub(super) fn recorded_panel(window: Signal<Window>) -> AnyElement {
    observations::watch();
    let mut panel = view().gap_4();
    let Ok(daily) = observations::read(valuation::recorded_trend) else {
        return panel.child(history_read_error()).into_element();
    };
    if daily.is_empty() {
        return panel
            .child(
                text(copy("No net worth snapshots yet.", "暂无净值快照。"))
                    .typo(Type::Body)
                    .text_color(color::MUTED),
            )
            .into_element();
    }
    let partial = daily.iter().any(|p| p.1.is_none());
    panel = panel.child(trend::chart(
        copy("Recorded net worth", "留存净值").into(),
        daily,
        Unit::Money,
        window,
    ));
    if partial {
        panel = panel.child(
            text(copy(
                "Snapshots with missing rates are excluded from the trend.",
                "缺少汇率的快照只显示已知金额，趋势在该处断开。",
            ))
            .typo(Type::Subhead)
            .text_color(color::MUTED),
        );
    }
    panel.child(snapshot_page(None)).into_element()
}

fn history_read_error() -> AnyElement {
    text(copy(
        "Could not read valuation history.",
        "读取净值快照失败。",
    ))
    .typo(Type::Body)
    .text_color(color::DANGER)
    .into_element()
}

fn snapshot_page(before: Option<valuation::Cursor>) -> AnyElement {
    const PAGE_SIZE: usize = 30;
    let Ok(mut rows) =
        observations::read(|c| valuation::summaries(c, before.as_ref(), (PAGE_SIZE + 1) as u32))
    else {
        return history_read_error();
    };
    let more = rows.len() > PAGE_SIZE;
    rows.truncate(PAGE_SIZE);
    let cursor = rows.last().map(valuation::Summary::cursor);
    let mut page = view().gap_2().children(rows.into_iter().map(snapshot_row));
    if more {
        let opened = signal(false);
        page = page.child(dynamic(move || {
            if opened.get() {
                snapshot_page(cursor.clone())
            } else {
                crate::ui::Btn::ghost()
                    .label(|| copy("Show more", "显示更多").into())
                    .on_press(move || opened.set(true))
                    .into_element()
            }
        }));
    }
    page.into_element()
}

fn snapshot_row(b: valuation::Summary) -> AnyElement {
    let at = crate::data::clock::zoned(b.captured_at.as_millisecond());
    let partial = if b.missing.is_empty() {
        String::new()
    } else {
        format!(
            " · {} {}",
            copy("Missing FX", "缺少汇率"),
            b.missing
                .iter()
                .map(|c| c.code())
                .collect::<Vec<_>>()
                .join(", ")
        )
    };
    let details = signal(false);
    view()
        .gap_2()
        .py_3()
        .child(
            crate::ui::surface::row_button(move || details.update(|v| *v = !*v))
                .px_0()
                .child(
                    view()
                        .gap_1()
                        .flex_1()
                        .child(
                            text(format!(
                                "{} {} {:02}:{:02}:{:02}",
                                copy("Recorded at", "留存于"),
                                at.date(),
                                at.hour(),
                                at.minute(),
                                at.second()
                            ))
                            .typo(Type::Subhead)
                            .text_color(color::BODY),
                        )
                        .child(
                            text(format!(
                                "{} {}{}",
                                if b.missing.is_empty() {
                                    copy("Net worth", "净值")
                                } else {
                                    copy("Known value", "已知金额")
                                },
                                crate::ui::currency::format(
                                    b.net,
                                    navi_finance::currency::Currency::CNY
                                ),
                                partial
                            ))
                            .typo(Type::Body)
                            .text_color(color::INK),
                        ),
                )
                .child(dynamic(move || {
                    crate::ui::icon(
                        if details.get() {
                            crate::ui::Icon::ChevronDown
                        } else {
                            crate::ui::Icon::ChevronRight
                        },
                        16.0,
                        color::MUTED,
                    )
                    .into_element()
                })),
        )
        .child(dynamic(move || {
            let mut v = view().gap_2();
            if details.get() {
                let Ok(snapshot) = observations::read(|c| valuation::detail(c, b.id)) else {
                    return history_read_error();
                };
                let b = snapshot.body;
                v = v.child(
                    text(format!(
                        "{} {} · {} {}",
                        copy("Assets", "资产"),
                        crate::ui::currency::format(
                            b.assets,
                            navi_finance::currency::Currency::CNY
                        ),
                        copy("Debt", "负债"),
                        crate::ui::currency::format(b.debt, navi_finance::currency::Currency::CNY)
                    ))
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
                );
                for a in b.balances.iter().filter(|a| a.account.is_cash()) {
                    v = v.child(
                        text(format!(
                            "{} {}",
                            a.account.name(),
                            crate::ui::currency::format(a.native, a.account.currency())
                        ))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                    );
                }
                for h in &b.holdings {
                    v = v.child(
                        text(format!(
                            "{} · {} {} · {} {} · {}",
                            b.securities
                                .iter()
                                .find(|s| s.id == h.security)
                                .map(|s| format!("{} ({})", s.name, s.currency()))
                                .unwrap_or_else(|| h.security.clone()),
                            copy("Quantity", "数量"),
                            navi_finance::holdings::format_units(h.quantity),
                            copy("Cost", "成本"),
                            crate::ui::currency::grouped(h.cost),
                            h.price_day
                                .map(|d| format!(
                                    "{d} / {} / {}",
                                    h.price
                                        .map(navi_finance::holdings::format_units)
                                        .unwrap_or_default(),
                                    source_name(&h.source)
                                ))
                                .unwrap_or_else(|| copy("At cost", "按成本").into())
                        ))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                    );
                }
                for r in &b.rates {
                    v = v.child(
                        text(format!(
                            "{} / {} / {} / {}",
                            r.currency,
                            r.day,
                            navi_finance::holdings::format_units(r.rate),
                            source_name(&r.source)
                        ))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                    );
                }
            }
            v.into_element()
        }))
        .into_element()
}
fn source_name(source: &str) -> &str {
    match source {
        "manual" => copy("Manual", "手动"),
        "base" => copy("Base currency", "本位币"),
        "cost" => copy("Cost", "成本"),
        "tencent" => copy("Tencent quote", "腾讯行情"),
        "tencent:raw" => copy("Tencent unadjusted close", "腾讯未复权收盘价"),
        "frankfurter:ecb" => copy("ECB reference", "欧洲央行参考汇率"),
        _ => source,
    }
}
