//! Inspect dated observations without changing their stored precision.
use super::{Icon, Type, Typo, chip, color, currency, field::select_input, icon, surface::card};
use crate::{
    domain::meal::Day,
    i18n::{s, statement_import::copy},
};
use jiff::civil::Date;
use navi_finance::{currency::Currency, holdings};
use nsh_base::{OpenChangeReason, SelectEvent, SelectItem};
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

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Window {
    Week,
    #[default]
    Month,
    Quarter,
    YearToDate,
    Year,
    All,
    Comparison {
        from: Date,
        to: Date,
    },
}

impl Window {
    pub(crate) fn start(self, today: Date, earliest: Date) -> Date {
        match self {
            Self::Week => today.saturating_sub(jiff::Span::new().days(6)),
            Self::Month => today.saturating_sub(jiff::Span::new().days(29)),
            Self::Quarter => today.saturating_sub(jiff::Span::new().days(89)),
            Self::YearToDate => today.first_of_year().yesterday().unwrap_or(Date::MIN),
            Self::Year => today
                .checked_sub(jiff::Span::new().years(1))
                .and_then(Date::tomorrow)
                .unwrap_or(Date::MIN),
            Self::All => earliest,
            Self::Comparison { from, .. } => from,
        }
    }

    /// A partial year names its first complete valuation as the comparison
    /// date. Every other range keeps its original opening observation.
    pub(crate) fn baseline(self, points: &[Point]) -> Option<Point> {
        if self == Self::YearToDate {
            points.iter().copied().find(|p| p.1.is_some())
        } else {
            points.first().copied()
        }
    }

    /// Longer windows request dated observations on demand. All can extend
    /// earlier than one year when the ledger starts before that window.
    pub(crate) fn backfill_start(self, today: Date, earliest: Date) -> Option<Date> {
        match self {
            Self::Quarter | Self::YearToDate | Self::Year => Some(self.start(today, earliest)),
            Self::All => Some(earliest.min(Self::Year.start(today, earliest))),
            _ => None,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Week => copy("7D", "7天"),
            Self::Month => copy("30D", "30天"),
            Self::Quarter => copy("90D", "90天"),
            Self::YearToDate => copy("YTD", "今年以来"),
            Self::Year => copy("1Y", "1年"),
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
            (window.start(self.today, self.earliest), self.today)
        }
    }

    /// Use an existing control if it already covers the comparison's observations.
    fn comparison_control(self, unit: Unit) -> Option<Window> {
        let (from, to) = self.comparison?;
        let regular = [
            Window::Month,
            Window::Week,
            Window::All,
            Window::Quarter,
            Window::Year,
            Window::YearToDate,
        ]
        .into_iter()
        .find(|w| {
            let (start, end) = self.bounds(*w);
            (*w != Window::YearToDate || matches!(unit, Unit::Money))
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
    let title = stored(title);
    let data = stored(points);
    card()
        .p_4()
        .gap_2()
        .child(
            text(move || title.get())
                .typo(Type::Headline)
                .text_color(color::BODY),
        )
        .child(period_picker(unit, window, dates, selection))
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
                    series(
                        title.get(),
                        visible,
                        unit,
                        from,
                        to,
                        window.get(),
                        selection,
                    )
                })
            })
        }))
        .into_element()
}

/// The same controls serve plots, compact single prices and empty periods.
pub(crate) fn period_picker(
    unit: Unit,
    window: Signal<Window>,
    dates: ChartDates,
    selection: Option<Signal<Option<Date>>>,
) -> AnyElement {
    let comparison = dates.comparison_control(unit);
    let active = move || match window.get() {
        w @ Window::Comparison { .. } => comparison.unwrap_or(w),
        w => w,
    };
    let choose = move |next| {
        if window.get_untracked() != next {
            if let Some(day) = selection {
                day.set(None);
            }
            window.set(next);
        }
    };
    let more = stored(
        comparison
            .filter(|w| matches!(w, Window::Comparison { .. }))
            .into_iter()
            .chain(matches!(unit, Unit::Money).then_some(Window::YearToDate))
            .chain([Window::Year, Window::All])
            .collect::<Vec<_>>(),
    );
    let chosen = move || more.with(|options| options.iter().position(|w| *w == active()));
    let label = move || {
        if chosen().is_some() {
            active().label()
        } else {
            copy("More", "更多")
        }
    };
    let tint = move || {
        if chosen().is_some() {
            color::ACCENT_INK
        } else {
            color::BODY
        }
    };
    nsh_base::toggle_group()
        .flex_row()
        .flex_wrap()
        .items_center()
        .gap_x(px(4.0))
        .gap_y(px(6.0))
        .children(
            [Window::Week, Window::Month, Window::Quarter].map(move |w| {
                chip(
                    move || w.label().into(),
                    move || active() == w,
                    move || choose(w),
                )
                .min_w(px(48.0))
                .px_2()
            }),
        )
        .child(
            select_input(label)
                .margin(px(8.0))
                .align(nsh_core::overlay::Align::End)
                // A desktop list anchors to the compact chip. Give its rows
                // enough room independently; the touch sheet fills the width.
                .popup_class(move || {
                    is_desktop().then(|| {
                        let available = (nsh_core::prelude::window().width.0 - 16.0).max(1.0);
                        let width = (136.0 * font_scale().max(1.0)).min(available).floor();
                        format!("min-w-[{width}px]").into()
                    })
                })
                .accessibility_label(|| Some(copy("More periods", "更多周期").into()))
                .trigger(
                    view()
                        .test_id("trend-period-more")
                        .flex_row()
                        .items_center()
                        .justify_center()
                        .min_h(px(38.0))
                        .min_w(px(48.0))
                        .hit_slop(EdgeInsets::all(px(5.0)))
                        .px_2()
                        .gap_1()
                        .rounded_full()
                        .hover(|s| s.bg(color::SUNKEN))
                        .active(|s| s.bg(color::SUNKEN))
                        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                        .style_when(move || chosen().is_some(), |s| s.bg(color::ACCENT_SOFT))
                        .child(
                            text(label)
                                .typo(Type::Subhead)
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(tint),
                        )
                        .child(icon(Icon::ChevronDown, 14.0, color::MUTED)),
                )
                .items(move || {
                    more.with(|opts| {
                        opts.iter()
                            .enumerate()
                            .map(|(i, w)| SelectItem::new(i.to_string(), w.label()))
                            .collect::<Vec<_>>()
                    })
                })
                .value(move || chosen().map(|i| SharedString::from(i.to_string())))
                // Choosing the already displayed standard period commits that
                // period too, so an explicit All can load earlier history.
                .on_open_change(move |event: &SelectEvent| {
                    if matches!(
                        event,
                        SelectEvent::OpenChange(false, OpenChangeReason::Select)
                    ) && matches!(window.get_untracked(), Window::Comparison { .. })
                        && let Some(standard) = comparison
                    {
                        choose(standard);
                    }
                })
                .on_change(move |v: &Option<SharedString>| {
                    if let Some(next) = v
                        .as_deref()
                        .and_then(|id| id.parse::<usize>().ok())
                        .and_then(|i| more.with(|options| options.get(i).copied()))
                    {
                        choose(next);
                    }
                }),
        )
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
    window: Window,
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
    let baseline = window
        .baseline(points)
        .and_then(|(day, v)| v.map(|value| (day, value)));
    let samples = points
        .iter()
        .map(|&(day, value)| {
            let mut caption = date_caption(day, from, end);
            if let Some((start, first)) = baseline
                && let Some(delta) = value.and_then(|v| v.checked_sub(first))
                && (delta != 0 || (window == Window::YearToDate && day > start))
            {
                caption = format!(
                    "{caption}  ·  {} {}{}",
                    s().net_change_since(Day(start)),
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
            Window::Month,
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
        app.press("id:trend-period-more").unwrap();
        app.press("text:All").unwrap();
        app.wait_for("text:¥2").unwrap();
        // The axis starts at the first observation, not the older journal start.
        app.wait_for("text:Jan 30").unwrap();
        assert!(!app.shows("text:¥3"));
    }

    #[test]
    fn long_periods_follow_the_calendar_and_only_fetch_when_requested() {
        use jiff::civil::date;
        let leap = date(2024, 2, 29);
        let old = date(2020, 7, 1);
        assert_eq!(Window::Year.start(leap, old), date(2023, 3, 1));
        assert_eq!(
            Window::Year.start(date(2025, 2, 28), old),
            date(2024, 2, 29)
        );
        assert_eq!(
            Window::YearToDate.start(date(2025, 1, 1), old),
            date(2024, 12, 31)
        );
        assert_eq!(Window::Quarter.start(leap, old), date(2023, 12, 2));
        assert_eq!(
            Window::Quarter.backfill_start(leap, leap),
            Some(date(2023, 12, 2))
        );
        assert_eq!(
            Window::YearToDate.backfill_start(leap, old),
            Some(date(2023, 12, 31))
        );
        assert_eq!(
            Window::Year.backfill_start(leap, leap),
            Some(date(2023, 3, 1))
        );
        assert_eq!(
            Window::All.backfill_start(leap, leap),
            Some(date(2023, 3, 1))
        );
        assert_eq!(Window::All.backfill_start(leap, old), Some(old));
        assert_eq!(Window::Month.backfill_start(leap, old), None);
        let observations = [(date(2023, 12, 31), None), (date(2024, 1, 1), Some(42))];
        assert_eq!(
            Window::YearToDate.baseline(&observations),
            Some(observations[1])
        );
        assert_eq!(Window::Year.baseline(&observations), Some(observations[0]));
    }

    #[component]
    fn ShortHistory() -> impl IntoElement {
        let today = jiff::civil::date(2026, 5, 12);
        let window = signal(Window::Month);
        view()
            .child(chart(
                "Net worth".into(),
                vec![(today, Some(5_000))],
                Unit::Money,
                window,
                today,
            ))
            .child(text(move || format!("Current {:?}", window.get())))
    }

    #[test]
    fn short_history_keeps_all_selected_and_the_picker_wraps_and_closes() {
        use nsh_core::{
            geometry::{Points, Size},
            platform::Os,
        };
        let mut app = Headless::start(EngineConfig::new(Root::of::<ShortHistory>())).unwrap();
        app.set_environment("large Android text", |e| {
            e.os = Os::Android;
            e.font_scale = 1.8;
            e.reduce_motion = true;
        })
        .unwrap();
        app.set_viewport(Size::new(Points(320.0), Points(720.0)))
            .unwrap();
        let trigger = "id:trend-period-more";
        app.press(trigger).unwrap();
        app.wait_for("text:YTD").unwrap();
        app.back().unwrap();
        app.wait_for_gone("text:YTD", std::time::Duration::from_secs(2))
            .unwrap();
        app.wait_for("Current Month").unwrap();
        app.press(trigger).unwrap();
        app.press("text:All").unwrap();
        app.wait_for("Current All").unwrap();
        app.wait_for("id:trend-period-more >> text:All").unwrap();
        assert_eq!(
            app.screen().accessibility_state(trigger).unwrap().expanded,
            Some(false)
        );
        for label in ["7D", "30D", "90D", "All"] {
            let nodes = app.screen().layout_nodes();
            let frame = nodes
                .iter()
                .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == label))
                .unwrap()
                .bounds;
            assert!(
                frame.origin.x.0 >= 0.0 && frame.origin.x.0 + frame.size.width.0 <= 320.0,
                "{label}: {frame:?}"
            );
        }
        app.press("90D").unwrap();
        app.wait_for("Current Quarter").unwrap();
        app.wait_for("id:trend-period-more >> text:More").unwrap();
    }

    #[component]
    fn EntireComparison() -> impl IntoElement {
        let today = jiff::civil::date(2026, 5, 12);
        let earliest = today.saturating_sub(jiff::Span::new().days(30));
        let window = signal(Window::Comparison {
            from: earliest,
            to: today,
        });
        let dates = ChartDates {
            today,
            earliest,
            comparison: Some((earliest, today)),
        };
        view()
            .child(period_picker(Unit::Money, window, dates, None))
            .child(text(move || format!("Current {:?}", window.get())))
    }

    #[component]
    fn FullMenu() -> impl IntoElement {
        let today = jiff::civil::date(2026, 5, 12);
        let dates = ChartDates {
            today,
            earliest: jiff::civil::date(2025, 8, 1),
            comparison: Some((jiff::civil::date(2026, 4, 12), today)),
        };
        view().items_end().p_2().child(period_picker(
            Unit::Money,
            signal(Window::Month),
            dates,
            None,
        ))
    }

    #[test]
    fn desktop_menu_fits_localized_option_text_and_the_viewport() {
        use nsh_core::{
            ApproxTextEngine, TextEngine,
            geometry::{Points, Size},
            platform::{Locale, LocaleSettings, Os},
        };
        let mut app = Headless::start(EngineConfig::new(Root::of::<FullMenu>())).unwrap();
        for (language, title) in [("zh-CN", "今年以来"), ("en", "Comparison")] {
            let locale = Locale::parse(language).unwrap();
            for (width, scale) in [(390.0, 1.0), (320.0, 1.0), (320.0, 1.8)] {
                app.set_environment("desktop language and type size", |e| {
                    e.os = Os::Linux;
                    e.locale = locale;
                    e.locale_settings = LocaleSettings::of(locale);
                    e.font_scale = scale;
                    e.reduce_motion = true;
                })
                .unwrap();
                app.set_viewport(Size::new(Points(width), Points(720.0)))
                    .unwrap();
                app.press("id:trend-period-more").unwrap();
                app.wait_for(&format!("role:option[{title}]")).unwrap();
                let nodes = app.screen().layout_nodes();
                let text = nodes
                    .iter()
                    .find_map(|node| {
                        node.text
                            .as_ref()
                            .filter(|layout| layout.text.text == title)
                    })
                    .unwrap();
                let single_line =
                    ApproxTextEngine.measure(&ApproxTextEngine.prepare(&text.text), None);
                assert!(
                    single_line.width.0 <= text.content.size.width.0 + 1.0,
                    "{language} {width}pt ×{scale}: {title} needs {:?}, actual {:?}",
                    single_line.width,
                    text.content
                );
                let content = text.content;
                assert!(
                    content.origin.x.0 >= 0.0
                        && content.origin.x.0 + content.size.width.0 <= width + 0.5
                );
                let trigger = nodes
                    .iter()
                    .find(|node| node.test_id.as_deref() == Some("trend-period-more"))
                    .unwrap();
                assert!(
                    trigger.bounds.size.width.0 < content.size.width.0,
                    "menu sizing must preserve the compact trigger"
                );
                app.press_key("escape").unwrap();
                app.wait_for_gone("role:listbox", std::time::Duration::from_secs(2))
                    .unwrap();
            }
        }
    }

    #[test]
    fn reselecting_all_from_a_matching_comparison_requests_all_history() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<EntireComparison>())).unwrap();
        app.wait_for("id:trend-period-more >> text:All").unwrap();
        app.press("id:trend-period-more").unwrap();
        assert!(!app.shows("text:Comparison"));
        app.press("role:option[All]").unwrap();
        app.wait_for("Current All").unwrap();
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
            Default::default(),
        )
        .unwrap();
        app.wait_for("text:—").unwrap();
        app.drop_held().unwrap();
    }
}
