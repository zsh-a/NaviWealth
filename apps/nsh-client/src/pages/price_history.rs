//! Read-only provenance, kept one level below the asset workspace.
use crate::{
    data::{db, finance, history},
    i18n::statement_import::copy,
    nav,
    ui::{
        Btn, Type, Typo, color,
        segmented::{Segment, segmented},
        space,
        surface::{hairline, row_button},
    },
};
use navi_finance::{
    catalog,
    history::{AuditRevision, DailyBar},
    holdings::format_units,
};
use nsh_core::{element::Screen, prelude::*};
use std::collections::BTreeMap;

pub fn page(security: Option<String>) -> Screen {
    let security = stored(security);
    let revisions = signal(false);
    let limit = signal(30usize);
    nsh_base::nav_page().header_visible(false).status_bar(super::parts::status_bar)
        .child(view().flex_1().bg(color::CANVAS)
            .child(super::parts::top_bar(|| copy("Price history", "价格与汇率记录").into(), nav::pop, None))
            .child(scroll().flex_1().child(view().px(px(space::GUTTER)).gap_4().pb_safe_area_plus(px(24.0))
                .child(segmented(vec![Segment::new(false, || copy("Daily closes", "每日收盘").into()), Segment::new(true, || copy("Changes", "修改记录").into())], move || revisions.get(), move |v| {revisions.set(v);limit.set(30);} ))
                .child(dynamic(move || {
                    let _ = finance::holdings();
                    let _ = finance::rates();
                    let _ = history::status();
                    let selected = security.get();
                    let audit = revisions.get();
                    let count = limit.get();
                    untracked(move || {
                        let result = db::with(|c| {
                            let bindings = catalog::bindings(c).map_err(|e|e.to_string())?;
                            let bars = navi_finance::history::all_daily_revisions(c).map_err(|e|e.to_string())?;
                            let changes = navi_finance::history::audit(c).map_err(|e|e.to_string())?;
                            Ok::<_, String>((bindings, bars, changes))
                        }).unwrap_or_else(||Err("database unavailable".into()));
                        let Ok((bindings,bars,changes)) = result else {
                            return text(copy("Could not read history. Reopen this page to retry.", "暂时无法读取记录，请重新打开此页重试。")).typo(Type::Body).text_color(color::DANGER).into_element();
                        };
                        let binding=selected.as_ref().and_then(|id|bindings.iter().find(|b|b.security==*id));
                        let mut panel=view().gap_1();
                        let total;
                        if audit {
                            let rows:Vec<_>=changes.into_iter().filter(|r|selected.as_ref().is_none_or(|id|r.item_key==*id)).collect();
                            total=rows.len();
                            panel=panel.child(text(copy("Saved changes remain available after corrections or a security rebind.", "修正价格或重新绑定标的后，原记录仍会保留。")).typo(Type::Subhead).text_color(color::MUTED).mb_3());
                            for row in rows.into_iter().take(count) {panel=panel.child(audit_row(row));}
                        } else {
                            let mut groups:BTreeMap<_,Vec<DailyBar>>=BTreeMap::new();
                            for bar in bars {
                                if selected.is_some() && !binding.is_some_and(|b| b.market==bar.market && b.currency==bar.currency && navi_finance::market::canonical_binding(b).as_ref()==Some(&bar.symbol)) {continue}
                                groups.entry((bar.day,bar.market.clone(),bar.symbol.clone(),bar.currency.clone())).or_default().push(bar);
                            }
                            total=groups.len();
                            panel=panel.child(text(copy("Unadjusted daily prices. Unfinished trading days are excluded; tap a row for OHLC and revisions.", "保存不复权日线，不含尚未结束的交易日。点按查看开高低收及修订版本。")).typo(Type::Subhead).text_color(color::MUTED).mb_3());
                            for (_,mut rows) in groups.into_iter().rev().take(count) {
                                rows.sort_by_key(|r|r.fetched_at);
                                panel=panel.child(bar_row(rows));
                            }
                        }
                        if total==0 {panel=panel.child(text(copy("No stored records yet. Fill history from Asset changes, or refresh prices and rates.", "尚无记录。可在资产变化中补全历史，或刷新价格与汇率。")).typo(Type::Body).text_color(color::MUTED).py_5());}
                        if total>count {panel=panel.child(Btn::ghost().label(||copy("Show more", "查看更多").into()).on_press(move||limit.update(|v|*v+=30)));}
                        panel.into_element()
                    })
                })))))
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
        _ => finance::holdings()
            .securities
            .into_iter()
            .find(|s| s.id == row.item_key)
            .map(|s| s.name)
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
                finance::holdings()
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
