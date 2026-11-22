//! Inspect dated observations without changing their stored precision.
use super::{Type, Typo, chip, color, currency, surface::card};
use crate::{
    domain::meal::Day,
    i18n::{s, statement_import::copy},
};
use jiff::civil::Date;
use navi_finance::{currency::Currency, holdings};
use nsh_core::prelude::*;

mod plot;
pub(crate) use plot::{InspectionPlot, Sample};

pub type Point = (Date, Option<i64>);

#[derive(Clone, Copy)]
pub enum Unit {
    Money,
    Price(Currency),
    Rate,
}

impl Unit {
    fn last_record_label(self) -> &'static str {
        match self {
            Self::Price(_) => copy("Last quote", "最近报价"),
            Self::Rate => copy("Last rate", "最近汇率"),
            Self::Money => copy("Last valuation", "最近估值"),
        }
    }

    fn format(self, n: i64) -> String {
        match self {
            Self::Money => currency::format(n, Currency::CNY),
            Self::Price(c) => currency::unit_price(n, c),
            Self::Rate => holdings::format_units(n),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Default)]
pub enum Window {
    Week,
    #[default]
    Month,
    All,
    Comparison {
        from: Date,
        to: Date,
    },
}

impl Window {
    pub(crate) fn available(self, today: Date, earliest: Date) -> Self {
        if self == Self::All && Day(today).days_since(Day(earliest)) < 30 {
            Self::Month
        } else {
            self
        }
    }
    pub(crate) fn start(self, today: Date, earliest: Date) -> Date {
        match self {
            Self::Week => Day(today).plus_days(-6).0,
            Self::Month => Day(today).plus_days(-29).0,
            Self::All => earliest,
            Self::Comparison { from, .. } => from,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Week => copy("7D", "7天"),
            Self::Month => copy("30D", "30天"),
            Self::All => copy("All", "全部"),
            Self::Comparison { .. } => copy("Comparison", "本次对比"),
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) struct ChartDates {
    pub today: Date,
    pub earliest: Date,
    pub comparison: Option<(Date, Date)>,
}

impl ChartDates {
    pub fn bounds(self, window: Window) -> (Date, Date) {
        if let Window::Comparison { from, to } = window {
            (from, to)
        } else {
            let from = window
                .available(self.today, self.earliest)
                .start(self.today, self.earliest);
            (from, self.today)
        }
    }

    /// Use an existing control if it already covers the comparison's observations.
    fn comparison_control(self) -> Option<Window> {
        let (from, to) = self.comparison?;
        let regular = [Window::Month, Window::Week, Window::All]
            .into_iter()
            .find(|w| {
                let (start, end) = self.bounds(*w);
                w.available(self.today, self.earliest) == *w
                    && start.max(self.earliest) == from
                    && end == to
            });
        Some(regular.unwrap_or(Window::Comparison { from, to }))
    }
}

/// Inputs are in ascending date order. An explicit missing valuation breaks its line.
pub fn chart(
    title: String,
    points: Vec<Point>,
    unit: Unit,
    window: Signal<Window>,
    today: Date,
) -> AnyElement {
    let earliest = points.first().map_or(today, |p| p.0.min(today));
    chart_from(
        title,
        points,
        unit,
        window,
        ChartDates {
            today,
            earliest,
            comparison: None,
        },
        None,
    )
}

/// Estimates can query only the requested days while still offering all available history.
pub(crate) fn chart_from(
    title: String,
    points: Vec<Point>,
    unit: Unit,
    window: Signal<Window>,
    dates: ChartDates,
    selection: Option<Signal<Option<Date>>>,
) -> AnyElement {
    let span = Day(dates.today).days_since(Day(dates.earliest));
    let comparison = dates.comparison_control();
    let active = move || match window.get() {
        w @ Window::Comparison { .. } => comparison.unwrap_or(w),
        w => w.available(dates.today, dates.earliest),
    };
    let has_history =
        points.first().is_some_and(|p| p.0 <= dates.today) || dates.earliest < dates.today;
    let extra = comparison.filter(|w| matches!(w, Window::Comparison { .. }));
    let options = extra
        .into_iter()
        .chain([Window::Week, Window::Month, Window::All])
        .filter(move |w| has_history && (*w != Window::All || span >= 30));
    let title = stored(title);
    let data = stored(points);
    card()
        .p_4()
        .gap_2()
        .child(
            view()
                .flex_row()
                .items_center()
                .flex_wrap()
                .gap_2()
                .child(
                    text(move || title.get())
                        .typo(Type::Headline)
                        .text_color(color::BODY)
                        .flex_1()
                        .style_when(
                            move || extra.is_some() || font_scale() > 1.2,
                            |s| s.basis(relative(1.0)).flex_grow(0.0),
                        ),
                )
                .children(options.map(move |w| {
                    chip(
                        move || w.label().into(),
                        move || active() == w,
                        move || {
                            if active() != w {
                                if let Some(date) = selection {
                                    date.set(None);
                                }
                                window.set(w);
                            }
                        },
                    )
                    .min_w(px(42.0))
                    .px_2()
                })),
        )
        .child(dynamic(move || {
            let (from, to) = dates.bounds(window.get());
            data.with(|points| {
                let points = &points[..points.partition_point(|p| p.0 <= to)];
                let visible = &points[points.partition_point(|p| p.0 < from)..];
                untracked(|| {
                    if visible.is_empty() {
                        let message = match points.last() {
                            Some((day, value)) => {
                                let value =
                                    value.map(|v| unit.format(v)).unwrap_or_else(|| "—".into());
                                let day = s().short_date(Day(*day));
                                format!(
                                    "{} · {} {value} · {day}",
                                    copy("No observations in this period", "时段内暂无记录"),
                                    unit.last_record_label()
                                )
                            }
                            None => copy("No observations yet", "暂无历史记录").to_owned(),
                        };
                        return empty(message);
                    }
                    series(title.get(), visible, unit, from, to, selection)
                })
            })
        }))
        .into_element()
}

fn empty(message: String) -> AnyElement {
    text(message)
        .typo(Type::Subhead)
        .text_color(color::MUTED)
        .py_4()
        .into_element()
}

fn series(
    title: String,
    points: &[Point],
    unit: Unit,
    from: Date,
    end: Date,
    selection: Option<Signal<Option<Date>>>,
) -> AnyElement {
    let Some(low) = points.iter().filter_map(|p| p.1).min() else {
        return empty(
            copy(
                "No complete observations in this period",
                "此时段暂无完整数据",
            )
            .into(),
        );
    };
    let high = points.iter().filter_map(|p| p.1).max().unwrap();
    // Offset in integer space before projecting to pixels (one cent near i64::MAX still matters).
    let offset = |v| (i128::from(v) - i128::from(low)) as f64;
    let extent = offset(high);
    let pad = (extent * 0.13).max(1.0);
    let baseline = points.first().and_then(|p| p.1);
    let samples = points
        .iter()
        .map(|&(day, value)| {
            let mut caption = date_caption(day, from, end);
            if let Some(delta) = value
                .zip(baseline)
                .and_then(|(v, first)| v.checked_sub(first))
                .filter(|d| *d != 0)
            {
                caption = format!(
                    "{caption}  ·  {} {}{}",
                    s().net_change_since(Day(points[0].0)),
                    if delta > 0 { "+" } else { "" },
                    unit.format(delta)
                );
            }
            Sample {
                day,
                y: value.map(offset),
                caption,
                value: value.map(|v| unit.format(v)).unwrap_or_else(|| "—".into()),
            }
        })
        .collect();
    let height = if points.len() == 1 { 64.0 } else { 152.0 };
    // The axis starts at the first observation in the window, so a short
    // history fills the plot instead of leaving an empty band on the left.
    let axis_from = points.first().map_or(from, |p| p.0.max(from));
    view()
        .gap_1()
        .child(
            InspectionPlot {
                title,
                from: axis_from,
                end,
                domain: [-pad, extent + pad],
                samples,
                color: color::ACCENT,
                goal: None,
            }
            .draw_with_selection(move || height, selection),
        )
        .child((low != high).then(|| {
            text(format!(
                "{} {} – {}",
                s().value_range,
                unit.format(low),
                unit.format(high)
            ))
            .pt_1()
            .typo(Type::Caption)
            .tabular_nums()
            .text_color(color::MUTED)
        }))
        .into_element()
}

pub(crate) fn date_caption(day: Date, from: Date, end: Date) -> String {
    if from.year() == end.year() {
        s().long_date(Day(day))
    } else {
        s().axis_date(Day(day), true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn TrendProbe() -> impl IntoElement {
        let day = Day(jiff::civil::date(2026, 11, 20));
        series(
            "Net worth".into(),
            &[
                (day.plus_days(-2).0, Some(100)),
                (day.plus_days(-1).0, None),
                (day.0, Some(-200)),
            ],
            Unit::Money,
            day.plus_days(-2).0,
            day.0,
            None,
        )
    }

    #[component]
    fn StalePrice() -> impl IntoElement {
        let today = Day(jiff::civil::date(2026, 3, 1));
        chart(
            "Unit price".into(),
            vec![
                (today.plus_days(-30).0, Some(1_000_000)),
                (today.plus_days(-7).0, Some(2_000_000)),
                (today.plus_days(1).0, Some(3_000_000)),
            ],
            Unit::Price(Currency::CNY),
            signal(Window::Month),
            today.0,
        )
    }

    #[test]
    fn calendar_windows_keep_stale_quotes_out_and_offer_the_saved_history() {
        let today = jiff::civil::date(2026, 3, 1);
        let oldest = jiff::civil::date(2025, 12, 20);
        assert_eq!(
            Window::Week.start(today, oldest),
            jiff::civil::date(2026, 2, 23)
        );
        assert_eq!(
            Window::Month.start(today, oldest),
            jiff::civil::date(2026, 1, 31)
        );
        assert_eq!(Window::All.start(today, oldest), oldest);
        let mut app = Headless::start(EngineConfig::new(Root::of::<StalePrice>())).unwrap();
        app.wait_for("text:¥2").unwrap();
        app.press("7D").unwrap();
        app.wait_for("text:No observations in this period · Last quote ¥2 · Sun, Feb 22")
            .unwrap();
        assert!(!app.shows("id:trend-value"));
        app.press("All").unwrap();
        app.wait_for("text:¥2").unwrap();
        // The axis starts at the first observation, not the older journal start.
        app.wait_for("text:Jan 30").unwrap();
        assert!(!app.shows("text:¥3"));
    }

    #[test]
    fn keyboard_and_touch_inspect_the_same_gap_without_inventing_a_value() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<TrendProbe>())).unwrap();
        app.wait_for("text:−¥2.00").unwrap();
        app.set_environment("desktop keyboard", |e| e.os = nsh_core::platform::Os::Linux)
            .unwrap();
        app.press_key("tab").unwrap();
        app.press_key("home").unwrap();
        app.wait_for("text:¥1.00").unwrap();
        app.press_key("right").unwrap();
        app.wait_for("text:—").unwrap();
        app.press_key("end").unwrap();
        app.wait_for("text:−¥2.00").unwrap();
        app.drag_and_hold(
            "id:trend-inspector",
            nsh_core::geometry::point(px(1.0), px(0.0)),
        )
        .unwrap();
        app.wait_for("text:—").unwrap();
        app.drop_held().unwrap();
    }
}
