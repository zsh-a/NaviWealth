//! One workspace for dated prices, rates and their provenance.
mod rates;

use crate::{
    data::{finance, history},
    i18n::{s, statement_import::copy},
    nav,
    ui::{
        Btn, Type, Typo, color,
        segmented::{Segment, segmented},
        space,
        surface::{hairline, row_button},
    },
};
use navi_finance::history::{AuditRevision, DailyBar};
use navi_finance::holdings::format_units;
use nsh_core::{element::Screen, prelude::*};

pub(crate) fn title() -> &'static str {
    copy("Prices & rates", "价格与汇率")
}

#[derive(Clone, Copy, PartialEq)]
enum Section {
    Rates,
    Closes,
    Changes,
}

pub fn page(security: Option<String>) -> Screen {
    let scoped = security.is_some();
    let security = stored(security);
    let section = signal(if scoped {
        Section::Closes
    } else {
        Section::Rates
    });
    let mut segments = Vec::new();
    if !scoped {
        segments.push(Segment::new(Section::Rates, || {
            copy("Rates", "汇率").into()
        }));
    }
    segments.push(Segment::new(Section::Closes, || {
        copy("Daily closes", "每日收盘").into()
    }));
    segments.push(Segment::new(Section::Changes, || {
        copy("Changes", "变更记录").into()
    }));
    nsh_base::nav_page()
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || if scoped { s().price_history } else { title() }.into(),
                    nav::pop,
                    None,
                ))
                .child(view().px(px(space::GUTTER)).pb_3().child(segmented(
                    segments,
                    move || section.get(),
                    move |v| section.set(v),
                )))
                .child(dynamic(move || {
                    let selected = security.get();
                    let tab = section.get();
                    untracked(move || {
                        let content = match tab {
                            Section::Rates => rates::panel().into_element(),
                            Section::Closes => archive(
                                move |limit| history::daily_history(selected.as_deref(), limit),
                                bar_row,
                                || copy("No daily closes yet", "暂无收盘价"),
                            )
                            .into_element(),
                            Section::Changes => archive(
                                move |limit| history::changes(selected.as_deref(), limit),
                                audit_row,
                                || copy("No changes yet", "暂无变更记录"),
                            )
                            .into_element(),
                        };
                        scroll()
                            .flex_1()
                            .child(
                                view()
                                    .px(px(space::GUTTER))
                                    .pb_safe_area_plus(px(24.0))
                                    .child(content),
                            )
                            .into_element()
                    })
                })),
        )
}

fn archive<T: 'static, E: IntoElement + 'static>(
    read: impl Fn(i64) -> Result<Vec<T>, String> + 'static,
    row: fn(T) -> E,
    empty: fn() -> &'static str,
) -> impl IntoElement {
    let limit = signal(30usize);
    dynamic(move || {
        let _ = finance::holdings_snapshot();
        let _ = finance::rates_snapshot();
        history::watch();
        let count = limit.get();
        let result = read(count as i64 + 1);
        untracked(move || {
            let mut list = view().gap_1();
            match result {
                Err(_) => {
                    list = list.child(
                        text(copy("Could not load records", "暂时无法读取记录"))
                            .typo(Type::Body)
                            .text_color(color::DANGER),
                    )
                }
                Ok(rows) if rows.is_empty() => {
                    list = list.child(
                        text(empty())
                            .typo(Type::Body)
                            .text_color(color::MUTED)
                            .py_5(),
                    )
                }
                Ok(rows) => {
                    let more = rows.len() > count;
                    list = list.children(rows.into_iter().take(count).map(row));
                    if more {
                        list = list.child(
                            Btn::ghost()
                                .label(|| copy("Show more", "查看更多").into())
                                .on_press(move || limit.update(|n| *n += 30)),
                        );
                    }
                }
            }
            list.into_element()
        })
    })
}

fn bar_row(rows: Vec<DailyBar>) -> impl IntoElement {
    let last = rows.last().expect("group is nonempty").clone();
    let expanded = signal(false);
    let title = format!("{} · {}", last.symbol, last.day);
    let value = format!("{} {}", last.currency, format_units(last.close));
    let detail = format!(
        "{} · {} {}",
        source_label(&last.provider),
        rows.len(),
        copy("versions", "个版本")
    );
    view()
        .child(
            row_button(move || expanded.update(|v| *v = !*v))
                .px_0()
                .py_3()
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap_1()
                        .child(text(title).typo(Type::Headline).text_color(color::INK))
                        .child(text(detail).typo(Type::Caption).text_color(color::MUTED)),
                )
                .child(
                    text(value)
                        .typo(Type::Body)
                        .tabular_nums()
                        .text_color(color::INK),
                ),
        )
        .child(dynamic(move || {
            let mut v = view().gap_2();
            if expanded.get() {
                for r in rows.iter().rev() {
                    v = v
                        .child(
                            text(format!(
                                "{} {} · {} {} · {} {} · {} {}",
                                copy("Open", "开"),
                                format_units(r.open),
                                copy("High", "高"),
                                format_units(r.high),
                                copy("Low", "低"),
                                format_units(r.low),
                                copy("Close", "收"),
                                format_units(r.close)
                            ))
                            .typo(Type::Subhead)
                            .text_color(color::BODY),
                        )
                        .child(
                            text(format!(
                                "{} · {} {}{}",
                                source_label(&r.provider),
                                copy("Fetched", "获取于"),
                                local_time(r.fetched_at),
                                r.volume
                                    .map(|n| format!(
                                        " · {} {n}",
                                        copy("Volume (provider units)", "成交量（源单位）")
                                    ))
                                    .unwrap_or_default()
                            ))
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                        );
                }
            }
            v.into_element()
        }))
        .child(hairline(0.0))
}

fn audit_row(row: AuditRevision) -> impl IntoElement {
    let body: serde_json::Value = serde_json::from_str(&row.body).unwrap_or_default();
    let quote = body.get("quote").unwrap_or(&body);
    let source = body
        .get("source")
        .and_then(|v| v.as_str())
        .or_else(|| quote.get("provider").and_then(|v| v.as_str()))
        .unwrap_or(copy("Manual", "手动"));
    let label = match row.kind.as_str() {
        "fx_rate" => format!("{} → CNY", row.item_key),
        _ => finance::holdings_snapshot()
            .securities
            .iter()
            .find(|s| s.id == row.item_key)
            .map(|s| s.name.clone())
            .unwrap_or(row.item_key.clone()),
    };
    let amount = quote
        .get("price")
        .or_else(|| body.get("rate"))
        .and_then(|v| v.as_i64())
        .map(format_units)
        .unwrap_or_default();
    let amount = if row.kind == "fx_rate" {
        amount
    } else {
        let currency = quote
            .get("currency")
            .and_then(|v| v.as_str())
            .map(str::to_owned)
            .or_else(|| {
                finance::holdings_snapshot()
                    .securities
                    .iter()
                    .find(|s| s.id == row.item_key)
                    .map(|s| s.currency().code().to_string())
            })
            .unwrap_or_default();
        format!("{currency} {amount}")
    };
    let expanded = signal(false);
    let detail = format!(
        "{} · {}{}",
        row.day,
        source_label(source),
        if row.kind == "market_quote_unbound" {
            copy(" · Previous binding", " · 原绑定")
        } else {
            ""
        }
    );
    let baseline = body
        .get("baseline")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let provenance = format!(
        "{} {}{}",
        if baseline {
            copy("Existing record retained at", "原有记录留存于")
        } else {
            copy("Recorded at", "记录于")
        },
        row.received_at
            .parse()
            .map(local_time)
            .unwrap_or(row.received_at.clone()),
        quote
            .get("symbol")
            .and_then(|v| v.as_str())
            .map(|s| format!(" · {s}"))
            .unwrap_or_default()
    );
    view()
        .child(
            row_button(move || expanded.update(|v| *v = !*v))
                .px_0()
                .py_3()
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap_1()
                        .child(text(label).typo(Type::Headline).text_color(color::INK))
                        .child(text(detail).typo(Type::Caption).text_color(color::MUTED)),
                )
                .child(
                    text(amount)
                        .typo(Type::Body)
                        .tabular_nums()
                        .text_color(color::INK),
                ),
        )
        .child(when(
            move || expanded.get(),
            move || {
                text(provenance.clone())
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .pb_3()
            },
        ))
        .child(hairline(0.0))
}

fn source_label(source: &str) -> &str {
    match source {
        "manual" => copy("Manual", "手动"),
        "tencent:raw" => copy("Tencent · unadjusted", "腾讯 · 不复权"),
        "tencent" => copy("Tencent", "腾讯"),
        "frankfurter:ecb" => "ECB",
        other => other,
    }
}

fn local_time(instant: jiff::Timestamp) -> String {
    let at = crate::data::clock::zoned(instant.as_millisecond());
    format!(
        "{} {:02}:{:02}:{:02}",
        at.date(),
        at.hour(),
        at.minute(),
        at.second()
    )
}
