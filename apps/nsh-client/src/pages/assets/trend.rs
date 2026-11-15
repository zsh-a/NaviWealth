use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use finance_core::{assets, journal::Transaction, money};
use nsh_base::plot::{Curve, Scale, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};

pub fn history_page() -> nsh_core::element::Screen {
    use crate::{
        data::{clock, finance},
        nav,
    };
    let recorded = signal(false);
    let notice = signal(String::new());
    let shown = signal(30_usize);
    nsh_base::nav_page()
        .title(|| s().asset_history)
        .header_visible(false)
        .status_bar(super::super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::super::parts::top_bar(
                    || s().asset_history.into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(crate::ui::space::GUTTER))
                            .pt_4()
                            .gap_4()
                            .child(crate::ui::segmented::segmented(
                                vec![
                                    crate::ui::segmented::Segment::new(false, || copy("Recalculated", "重新计算").into()),
                                    crate::ui::segmented::Segment::new(true, || copy("Recorded", "已留存").into()),
                                ], move || recorded.get(), move |v| recorded.set(v),
                            ))
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(move || {
                                if recorded.get() { return recorded_panel(notice,shown); }
                                let entries = finance::transactions();
                                let portfolio = finance::holdings();
                                let today = clock::today();
                                let _rates = finance::rates();
                                untracked(move || {
                                    view()
                                        .gap_5()
                                        .child(text(copy("History recalculated from current records and dated prices. Edits can change these values.", "按当前账本与对应日期行情重新计算；修改记录后，历史数值会变化。")).typo(Type::Subhead).text_color(color::MUTED))
                                        .child(chart(&entries, &portfolio, today))
                                        .child(crate::ui::Btn::secondary().label(|| copy("Fill 30-day price & FX history", "补全近30天价格与汇率").into()).busy(||crate::data::history::status().running).on_press(move || {crate::data::tasks::spawn_app(async move {crate::data::history::backfill(today.plus_days(-29).0,today.0,true).await;});}))
                                        .child(dynamic(|| { let status=crate::data::history::status(); text(if status.running {copy("Fetching historical data…", "正在获取历史数据…").to_owned()} else if status.updated==0 && status.failed==0 {String::new()} else {format!("{} {} · {} {}", copy("Updated", "已更新"),status.updated,copy("Failed", "失败"),status.failed)}).typo(Type::Caption).text_color(color::MUTED) }))
                                        .child(
                                            text(if portfolio.securities.is_empty() {
                                                s().assets_basis
                                            } else {
                                                s().portfolio_basis
                                            })
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED),
                                        )
                                        .child(
                                            text(|| s().asset_history_note)
                                                .typo(Type::Subhead)
                                                .text_color(color::MUTED),
                                        ).into_element()
                                })
                            })),
                    ),
                ),
        )
}

pub fn chart(
    entries: &[Transaction],
    portfolio: &finance_core::holdings::Book,
    today: Day,
) -> AnyElement {
    let rates = crate::data::finance::rates();
    let has_holdings = !portfolio.securities.is_empty();
    let points: Vec<Option<_>> = assets::trend(entries, today.plus_days(-29).0, today.0)
        .into_iter()
        .map(|(day, _)| {
            portfolio
                .overview_with_rates(entries, day, &rates)
                .ok()
                .filter(|v| v.missing.is_empty())
                .map(|v| (day, v.snapshot.net))
        })
        .collect();
    if points.iter().any(Option::is_none) {
        return text(crate::i18n::statement_import::copy(
            "Historical rates are missing. Add dated rates to see the full trend.",
            "缺少历史汇率，补充对应日期的汇率后可查看完整趋势。",
        ))
        .typo(Type::Subhead)
        .text_color(color::MUTED)
        .into_element();
    }
    let points: Vec<_> = points.into_iter().flatten().collect();
    if points.len() < 2 {
        return text(|| s().assets_trend_empty)
            .typo(Type::Subhead)
            .text_color(color::MUTED)
            .into_element();
    }
    plot_points(
        points,
        today,
        if has_holdings {
            s().portfolio_trend
        } else {
            s().assets_trend
        },
    )
}

fn plot_points(
    points: Vec<(jiff::civil::Date, i64)>,
    today: Day,
    title: &'static str,
) -> AnyElement {
    let first = Day(points[0].0);
    let last = points.last().unwrap().1;
    let first_value = points[0].1;
    let days: Vec<f64> = points
        .iter()
        .map(|(d, _)| f64::from(Day(*d).days_since(first)))
        .collect();
    let values: Vec<f64> = points.iter().map(|(_, v)| *v as f64 / 100.0).collect();
    let low = values.iter().copied().fold(f64::INFINITY, f64::min);
    let high = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let pad = ((high - low) * 0.1).max(1.0);
    let label = format!(
        "{}: {} ¥{} → {} ¥{}",
        title,
        s().long_date(first),
        money::format(first_value),
        s().long_date(today),
        money::format(last)
    );
    view()
        .gap_2()
        .child(text(title).typo(Type::Headline).text_color(color::BODY))
        .child(
            text(format!(
                "{} ¥{} – ¥{}",
                s().value_range,
                super::display_money(points.iter().map(|p| p.1).min().unwrap()),
                super::display_money(points.iter().map(|p| p.1).max().unwrap())
            ))
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            plot()
                .h(px(180.0))
                .data(Rows::from_columns(
                    points.len(),
                    [("day".into(), days), ("value".into(), values)],
                ))
                .x(Some(RowAccessor::from("day")))
                .y(Some(RowAccessor::from("value")))
                .x_scale(Scale::Linear {
                    domain: Some([0.0, f64::from(today.days_since(first)).max(1.0)]),
                    reverse: false,
                })
                .y_scale(Scale::Linear {
                    domain: Some([low - pad, high + pad]),
                    reverse: false,
                })
                .interactive(false)
                .accessibility_label(move || Some(label.clone().into()))
                .child(
                    line()
                        .curve(Curve::Linear)
                        .text_color(color::INK)
                        .stroke_width(px(2.0)),
                ),
        )
        .child(
            view()
                .flex_row()
                .child(
                    text(s().long_date(first))
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .flex_1(),
                )
                .child(
                    text(s().long_date(today))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                ),
        )
        .into_element()
}

fn copy(en: &'static str, zh: &'static str) -> &'static str {
    crate::i18n::statement_import::copy(en, zh)
}

fn recorded_panel(notice: Signal<String>, shown: Signal<usize>) -> AnyElement {
    let snapshots = crate::data::valuation::all();
    let mut panel=view().gap_4()
        .child(text(copy("Observations captured at the time shown. Later edits do not change them. These are not end-of-day closing values.", "留存的是所示时刻的估值，后续修改不会改变它们；并非当日收盘净值。")).typo(Type::Subhead).text_color(color::MUTED))
        .child(crate::ui::Btn::secondary().label(||copy("Record current valuation", "留存当前估值").into()).on_press(move || {
            notice.set(match crate::data::valuation::capture(true) {Ok(())=>copy("Valuation recorded", "估值已留存").into(),Err(e)=>format!("{}: {e}",copy("Could not record", "留存失败"))});
        }))
        .child(when(move||!notice.get().is_empty(),move||text(move ||notice.get()).typo(Type::Caption).text_color(color::MUTED)));
    if snapshots.is_empty() {
        return panel
            .child(
                text(copy(
                    "No recorded valuations yet. Record the current value to start a history.",
                    "尚无留存估值。留存当前估值后开始积累历史。",
                ))
                .typo(Type::Body)
                .text_color(color::MUTED),
            )
            .into_element();
    }
    let daily = finance_core::valuation::daily_latest(&snapshots);
    // A partial observation must never appear on the chart as a full net worth.
    if daily.iter().all(|s| s.body.missing.is_empty()) && daily.len() >= 2 {
        let last = Day(daily.last().unwrap().body.day);
        panel = panel.child(plot_points(
            daily.iter().map(|s| (s.body.day, s.body.net)).collect(),
            last,
            copy("Recorded net worth", "留存净值"),
        ));
    } else if daily.iter().any(|s| !s.body.missing.is_empty()) {
        panel=panel.child(text(copy("Some observations lack FX rates. Partial values are listed below and excluded from the chart.", "部分留存缺少汇率，仅列出已知金额，暂不绘制净值曲线。")).typo(Type::Subhead).text_color(color::MUTED));
    }
    let total = snapshots.len();
    for snap in snapshots.into_iter().rev().take(shown.get()) {
        let b = snap.body;
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
        panel = panel.child(
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
                                        "{} ¥{}{}",
                                        if b.missing.is_empty() {
                                            copy("Net worth", "净值")
                                        } else {
                                            copy("Known value", "已知金额")
                                        },
                                        money::format(b.net),
                                        partial
                                    ))
                                    .typo(Type::Body)
                                    .text_color(color::INK),
                                ),
                        ),
                )
                .child(dynamic(move || {
                    let mut v = view().gap_2();
                    if details.get() {
                        v = v.child(
                            text(format!(
                                "{} ¥{} · {} ¥{}",
                                copy("Assets", "资产"),
                                money::format(b.assets),
                                copy("Debt", "负债"),
                                money::format(b.debt)
                            ))
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                        );
                        for a in b.balances.iter().filter(|a| a.account.is_cash()) {
                            v = v.child(
                                text(format!(
                                    "{} {} {}",
                                    a.account.name(),
                                    a.account.currency(),
                                    money::format(a.native)
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
                                    finance_core::holdings::format_units(h.quantity),
                                    copy("Cost", "成本"),
                                    money::format(h.cost),
                                    h.price_day
                                        .map(|d| format!(
                                            "{d} / {} / {}",
                                            h.price
                                                .map(finance_core::holdings::format_units)
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
                                    finance_core::holdings::format_units(r.rate),
                                    source_name(&r.source)
                                ))
                                .typo(Type::Caption)
                                .text_color(color::MUTED),
                            );
                        }
                    }
                    v.into_element()
                })),
        );
    }
    if total > shown.get() {
        panel = panel.child(
            crate::ui::Btn::ghost()
                .label(|| copy("Show more", "显示更多").into())
                .on_press(move || shown.update(|n| *n += 30)),
        );
    }
    panel.into_element()
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
