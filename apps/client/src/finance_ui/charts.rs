use super::*;

pub fn line_chart(
    points: Vec<(String, Option<Decimal>)>,
    label: String,
    currency: String,
) -> AnyElement {
    chart(points, label, false, true, currency)
}
pub fn cash_chart(
    points: Vec<(String, Option<Decimal>)>,
    label: String,
    currency: String,
) -> AnyElement {
    chart(points, label, true, true, currency)
}
pub fn history_chart(
    points: Vec<(String, Option<Decimal>)>,
    label: String,
    currency: String,
) -> AnyElement {
    chart(points, label, false, false, currency)
}
fn chart(
    points: Vec<(String, Option<Decimal>)>,
    label: String,
    cash: bool,
    show_latest: bool,
    currency: String,
) -> AnyElement {
    let values = points.iter().filter_map(|(_, v)| *v).collect::<Vec<_>>();
    if values.len() < 3 {
        let mut body = view()
            .test_id("finance-trend-empty")
            .gap_2()
            .py_3()
            .child(
                text(label)
                    .text_size(move || px(ui::token("type-body")))
                    .font_weight(FontWeight::MEDIUM),
            )
            .child(ui::quiet_text(format!(
                "已有 {} 个完整时点，累计 3 个后显示趋势。",
                values.len()
            )));
        if show_latest
            && let Some((date, Some(value))) = points.iter().rev().find(|(_, v)| v.is_some())
        {
            body = body.child(ui::quiet_text(format!(
                "{date} · {} {currency}",
                ui::money_for(*value, &currency)
            )));
        }
        return body.into_element();
    }
    let low = *values.iter().min().unwrap();
    let high = *values.iter().max().unwrap();
    let low_float = low.to_f64().unwrap_or(0.0);
    let high_float = high.to_f64().unwrap_or(0.0);
    let spread = (high_float - low_float).max(0.000001);
    let denominator = points.len().saturating_sub(1).max(1) as f64;
    let mut paths = String::new();
    let mut dots = String::new();
    let mut active = false;
    for (index, (_, value)) in points.iter().enumerate() {
        if let Some(v) = value.and_then(|v| v.to_f64()) {
            let x = 8.0 + index as f64 / denominator * 264.0;
            let y = if high == low {
                56.0
            } else {
                104.0 - (v - low_float) / spread * 96.0
            };
            paths.push_str(&format!(
                "{} {x:.2} {y:.2} ",
                if active { "L" } else { "M" }
            ));
            dots.push_str(&format!(
                "<circle cx='{x:.2}' cy='{y:.2}' r='2.5' fill='currentColor'/>"
            ));
            active = true;
        } else {
            active = false;
        }
    }
    let image = format!(
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 280 112'><path d='M8 8H272M8 104H272' opacity='.18' stroke='currentColor'/><path d='{paths}' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/>{dots}</svg>"
    );
    let first = points
        .iter()
        .find_map(|(d, v)| v.map(|v| (d.clone(), v)))
        .unwrap();
    let last = points
        .iter()
        .rev()
        .find_map(|(d, v)| v.map(|v| (d.clone(), v)))
        .unwrap();
    let gaps = points.iter().any(|(_, v)| v.is_none());
    view()
        .gap_2()
        .test_id("finance-trend-plot")
        .child(
            text(label)
                .text_size(move || px(ui::token("type-body")))
                .font_weight(FontWeight::MEDIUM),
        )
        .child(
            view()
                .flex_row()
                .gap_2()
                .child(
                    view()
                        .justify_between()
                        .py_1()
                        .min_w(move || px(68.0 * font_scale()))
                        .child(ui::quiet_text(ui::money_for(high, &currency)))
                        .child(ui::quiet_text(ui::money_for(low, &currency))),
                )
                .child(
                    svg(nsh_core::element::ImageSrc::svg_markup(&image))
                        .flex_1()
                        .min_w(px(0.0))
                        .h(px(96.0))
                        .text_color(move || if cash { data_cash() } else { data_investment() }),
                ),
        )
        .child(
            view()
                .flex_row()
                .gap_4()
                .child(
                    view()
                        .flex_1()
                        .gap_1()
                        .items_end()
                        .child(ui::quiet_text(format!(
                            "起点 {}",
                            first.0.get(5..).unwrap_or(&first.0)
                        )))
                        .child(ui::amount_text(
                            ui::money_for(first.1, &currency),
                            currency.clone(),
                            "type-body",
                        )),
                )
                .child(
                    view()
                        .flex_1()
                        .gap_1()
                        .items_end()
                        .child(ui::quiet_text(format!(
                            "末点 {}",
                            last.0.get(5..).unwrap_or(&last.0)
                        )))
                        .child(ui::amount_text(
                            ui::money_for(last.1, &currency),
                            currency,
                            "type-body",
                        )),
                ),
        )
        .child(when(move || gaps, || ui::quiet_text("缺失时点不连线")))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    #[component]
    fn TwoPoints() -> impl IntoElement {
        history_chart(
            vec![
                ("1".into(), Some(1000.into())),
                ("2".into(), Some(1200.into())),
            ],
            "历史".into(),
            "CNY".into(),
        )
    }
    #[component]
    fn ThreePoints() -> impl IntoElement {
        history_chart(
            vec![
                ("1".into(), Some(1000.into())),
                ("2".into(), Some(1200.into())),
                ("3".into(), Some(1100.into())),
            ],
            "历史".into(),
            "CNY".into(),
        )
    }
    #[test]
    fn fewer_than_three_points_never_draws_a_trend() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<TwoPoints>())).unwrap();
        app.wait_for("id:finance-trend-empty").unwrap();
        assert_eq!(app.screen().count("id:finance-trend-plot").unwrap(), 0);
    }
    #[test]
    fn three_points_show_axes_and_exact_endpoint_values() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<ThreePoints>())).unwrap();
        app.wait_for("id:finance-trend-plot").unwrap();
        app.wait_for("text:1,000.00 CNY").unwrap();
        app.wait_for("text:1,100.00 CNY").unwrap();
        app.wait_for("text:1,200.00").unwrap();
    }
}
