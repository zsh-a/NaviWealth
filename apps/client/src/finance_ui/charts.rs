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
        .test_id("finance-trend-section")
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
                    ui::trend_plot(points.clone(), currency.clone(), cash)
                        .flex_1()
                        .min_w(px(0.0)),
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
