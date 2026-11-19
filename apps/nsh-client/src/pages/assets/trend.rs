use crate::data::valuation as observations;
use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use navi_finance::{journal::Transaction, money, valuation};
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
                                    crate::ui::segmented::Segment::new(false, || copy("Historical estimates", "历史估算").into()),
                                    crate::ui::segmented::Segment::new(true, || copy("Net worth snapshots", "净值快照").into()),
                                ], move || recorded.get(), move |v| recorded.set(v),
                            ))
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(move || {
                                if recorded.get() { return recorded_panel(notice); }
                                let entries = finance::transactions_snapshot();
                                let portfolio = finance::holdings_snapshot();
                                let today = clock::today();
                                let rates = finance::rates_snapshot();
                                untracked(move || {
                                    view()
                                        .gap_5()
                                        .child(text(copy("History recalculated from current records and dated prices. Edits can change these values.", "按当前账本与对应日期行情重新计算；修改记录后，历史数值会变化。")).typo(Type::Subhead).text_color(color::MUTED))
                                        .child(chart(&entries, &portfolio, &rates, today))
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
    portfolio: &navi_finance::holdings::Book,
    rates: &[navi_finance::currency::FxRate],
    today: Day,
) -> AnyElement {
    let has_holdings = !portfolio.securities.is_empty();
    let mut points = Vec::new();
    let mut missing = std::collections::BTreeMap::new();
    let mut errors = 0;
    for (day, valuation) in
        portfolio.valuation_range(entries, rates, today.plus_days(-29).0, today.0)
    {
        let value = match valuation {
            Ok(v) if v.missing.is_empty() => Some(v.snapshot.net),
            Ok(v) => {
                for currency in v.missing {
                    *missing.entry(currency).or_insert(0usize) += 1;
                }
                None
            }
            Err(_) => {
                errors += 1;
                None
            }
        };
        points.push((day, value));
    }
    let mut panel = view().gap_2();
    if points.len() < 2 {
        panel = panel.child(
            text(|| s().assets_trend_empty)
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        );
    } else if points.iter().any(|p| p.1.is_some()) {
        panel = panel.child(plot_points(
            points,
            if has_holdings {
                s().portfolio_trend
            } else {
                s().assets_trend
            },
        ));
    }
    let can_backfill = errors == 0 || !missing.is_empty();
    for (currency, count) in missing {
        panel = panel.child(
            text(s().missing_rate_days(currency.code(), count))
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        );
    }
    if errors > 0 {
        panel = panel.child(
            text(copy(
                "Some dates could not be valued.",
                "部分日期估值失败。",
            ))
            .typo(Type::Subhead)
            .text_color(color::DANGER),
        );
    }
    if can_backfill {
        panel = panel.child(history_refresh(today));
    }
    panel.into_element()
}

fn history_refresh(today: Day) -> impl IntoElement {
    use crate::data::{history, tasks};
    view()
        .gap_2()
        .child(
            crate::ui::Btn::secondary()
                .label(|| copy("Fill 30-day price & FX history", "补全近30天价格与汇率").into())
                .busy(|| history::status().running)
                .on_press(move || {
                    tasks::spawn_app(async move {
                        history::backfill(today.plus_days(-29).0, today.0, true).await;
                    })
                }),
        )
        .child(dynamic(|| {
            let status = history::status();
            let message = if status.running {
                copy("Fetching historical data…", "正在获取历史数据…").to_owned()
            } else if status.updated > 0 || status.failed > 0 {
                format!(
                    "{} {} · {} {}",
                    copy("Updated", "已更新"),
                    status.updated,
                    copy("Failed", "失败"),
                    status.failed
                )
            } else {
                return view().into_element();
            };
            text(message)
                .typo(Type::Caption)
                .text_color(color::MUTED)
                .into_element()
        }))
}

fn plot_points(points: Vec<(jiff::civil::Date, Option<i64>)>, title: &'static str) -> AnyElement {
    let first = Day(points[0].0);
    let today = Day(points.last().unwrap().0);
    let known: Vec<_> = points
        .iter()
        .filter_map(|(d, v)| v.map(|v| (*d, v)))
        .collect();
    let (start, first_value) = known[0];
    let (end, last) = *known.last().unwrap();
    let values: Vec<f64> = known.iter().map(|(_, v)| *v as f64 / 100.0).collect();
    let segments = points
        .split(|p| p.1.is_none())
        .filter(|run| !run.is_empty())
        .map(|run| {
            let days = run
                .iter()
                .map(|(d, _)| f64::from(Day(*d).days_since(first)))
                .collect();
            let values = run.iter().map(|(_, v)| v.unwrap() as f64 / 100.0).collect();
            line()
                .data(Some(Rows::from_columns(
                    run.len(),
                    [("day".into(), days), ("value".into(), values)],
                )))
                .x(Some(RowAccessor::from("day")))
                .y(Some(RowAccessor::from("value")))
                .dot(run.len() == 1)
                .curve(Curve::Linear)
                .text_color(color::INK)
                .stroke_width(px(2.0))
        });
    let low = values.iter().copied().fold(f64::INFINITY, f64::min);
    let high = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let pad = ((high - low) * 0.1).max(1.0);
    let label = format!(
        "{}: {} ¥{} → {} ¥{}",
        title,
        s().long_date(Day(start)),
        money::format(first_value),
        s().long_date(Day(end)),
        money::format(last)
    );
    view()
        .gap_2()
        .child(text(title).typo(Type::Headline).text_color(color::BODY))
        .child(
            text(format!(
                "{} ¥{} – ¥{}",
                s().value_range,
                super::display_money(known.iter().map(|p| p.1).min().unwrap()),
                super::display_money(known.iter().map(|p| p.1).max().unwrap())
            ))
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            plot()
                .h(px(180.0))
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
                .children(segments),
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

fn recorded_panel(notice: Signal<String>) -> AnyElement {
    observations::watch();
    let mut panel = view().gap_4()
        .child(text(copy("Observations captured at the time shown. Later edits do not change them. These are not end-of-day closing values.", "留存的是所示时刻的估值，后续修改不会改变它们；并非当日收盘净值。")).typo(Type::Subhead).text_color(color::MUTED))
        .child(crate::ui::Btn::secondary().label(||copy("Record current valuation", "留存当前估值").into()).on_press(move || {
            notice.set(match crate::data::valuation::capture(true) {Ok(())=>copy("Valuation recorded", "估值已留存").into(),Err(e)=>format!("{}: {e}",copy("Could not record", "留存失败"))});
        }))
        .child(when(move||!notice.get().is_empty(),move||text(move ||notice.get()).typo(Type::Caption).text_color(color::MUTED)));
    let Ok(daily) = observations::read(valuation::recorded_trend) else {
        return panel.child(history_read_error()).into_element();
    };
    if daily.is_empty() {
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
    let partial = daily.iter().any(|p| p.1.is_none());
    if daily.len() >= 2 && daily.iter().any(|p| p.1.is_some()) {
        panel = panel.child(plot_points(daily, copy("Recorded net worth", "留存净值")));
    }
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
                                "{} ¥{}{}",
                                if b.missing.is_empty() {
                                    copy("Net worth", "净值")
                                } else {
                                    copy("Known value", "已知金额")
                                },
                                crate::ui::currency::grouped(b.net),
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
                        "{} ¥{} · {} ¥{}",
                        copy("Assets", "资产"),
                        crate::ui::currency::grouped(b.assets),
                        copy("Debt", "负债"),
                        crate::ui::currency::grouped(b.debt)
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
                            crate::ui::currency::grouped(a.native)
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
