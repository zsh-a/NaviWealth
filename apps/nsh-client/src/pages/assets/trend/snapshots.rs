use super::*;

pub(super) fn recorded_panel(window: Signal<Window>) -> AnyElement {
    observations::watch();
    let mut panel = view().gap_4();
    let Ok(daily) = observations::read(valuation::recorded_trend) else {
        return panel.child(history_read_error()).into_element();
    };
    let today = crate::data::clock::today().0;
    let Some(&(earliest, _)) = daily.first().filter(|p| p.0 <= today) else {
        return panel
            .child(
                text(copy("No net worth snapshots yet.", "暂无净值快照。"))
                    .typo(Type::Body)
                    .text_color(color::MUTED),
            )
            .into_element();
    };
    let gaps: Vec<_> = daily
        .iter()
        .filter(|p| p.1.is_none())
        .map(|p| p.0)
        .collect();
    panel = panel.child(trend::chart(
        copy("Recorded net worth", "留存净值").into(),
        daily,
        Unit::Money,
        window,
        today,
    ));
    panel
        .child(dynamic(move || {
            let from = window.get().start(today, earliest);
            let visible =
                &gaps[gaps.partition_point(|d| *d < from)..gaps.partition_point(|d| *d <= today)];
            untracked(|| {
                view()
                    .gap_2()
                    .child((!visible.is_empty()).then(|| {
                        gap_note(
                            visible,
                            copy("Missing exchange rates", "快照缺少汇率"),
                            color::MUTED,
                        )
                    }))
                    .child(snapshot_page(None, from, today))
                    .into_element()
            })
        }))
        .into_element()
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

fn snapshot_page(before: Option<valuation::Cursor>, from: Date, to: Date) -> AnyElement {
    const PAGE_SIZE: usize = 30;
    let Ok(mut rows) = observations::read(|c| {
        valuation::summaries(c, from, to, before.as_ref(), (PAGE_SIZE + 1) as u32)
    }) else {
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
                snapshot_page(cursor.clone(), from, to)
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
    let at = crate::data::clock::observation_time(b.captured_at);
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
                            text(format!("{} {at}", copy("Recorded at", "留存于")))
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
                .child(crate::ui::surface::disclosure_chevron(details)),
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
                    let security = b.securities.iter().find(|s| s.id == h.security);
                    let currency = security.map(|s| s.currency());
                    v = v.child(
                        text(format!(
                            "{} · {} {} · {} {} · {}",
                            security
                                .map(|s| s.name.clone())
                                .unwrap_or_else(|| h.security.clone()),
                            copy("Quantity", "数量"),
                            navi_finance::holdings::format_units(h.quantity),
                            copy("Cost", "成本"),
                            currency
                                .map(|c| crate::ui::currency::format(h.cost, c))
                                .unwrap_or_else(|| crate::ui::currency::grouped(h.cost)),
                            h.price_day
                                .map(|d| format!(
                                    "{d} · {} · {}",
                                    h.price
                                        .map(|p| crate::ui::currency::observed_price(p, currency))
                                        .unwrap_or_default(),
                                    crate::i18n::market::source_label(&h.source)
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
                            "{} → CNY · {} · {} · {}",
                            r.currency,
                            r.day,
                            navi_finance::holdings::format_units(r.rate),
                            crate::i18n::market::source_label(&r.source)
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
