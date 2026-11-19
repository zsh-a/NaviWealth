//! Consecutive weight-only timeline entries disclose their daily editors.
use super::*;
use crate::ui::surface::row_button;

#[derive(Clone, PartialEq)]
pub(super) enum Item {
    Day(DayRecords),
    Weights(Vec<DayRecords>),
}
impl Item {
    pub(super) fn day(&self) -> Day {
        match self {
            Self::Day(d) => d.day,
            Self::Weights(d) => d[0].day,
        }
    }
}
pub(super) fn group(days: Vec<DayRecords>, collapse: bool) -> Vec<Item> {
    let mut result = Vec::new();
    let mut pending = Vec::new();
    let flush = |pending: &mut Vec<DayRecords>, result: &mut Vec<Item>| {
        if pending.len() == 1 {
            result.push(Item::Day(pending.remove(0)));
        } else if !pending.is_empty() {
            result.push(Item::Weights(std::mem::take(pending)));
        }
    };
    for day in days {
        if collapse && day.weight.is_some() && day.entries.is_empty() {
            pending.push(day);
        } else {
            flush(&mut pending, &mut result);
            result.push(Item::Day(day));
        }
    }
    flush(&mut pending, &mut result);
    result
}
pub(super) fn render(item: Item) -> AnyElement {
    let Item::Weights(days) = item else {
        let Item::Day(day) = item else { unreachable!() };
        return day_section(day).into_element();
    };
    let oldest = days.last().unwrap();
    let latest = &days[0];
    let span = if oldest.day.0.year() == latest.day.0.year() {
        s().week_span(oldest.day, latest.day)
    } else {
        format!("{} – {}", oldest.day, latest.day)
    };
    let detail = format!(
        "{} · {} → {} kg",
        s().weight_only_days.replace("{n}", &days.len().to_string()),
        s().kg(oldest.weight.unwrap().kg),
        s().kg(latest.weight.unwrap().kg)
    );
    let summary = format!("{span} · {detail}");
    let expanded = signal(false);
    view()
        .gap_3()
        .child(
            row_button(move || expanded.update(|v| *v = !*v))
                .px_1()
                .py_2()
                .min_h(px(48.0))
                .gap_2()
                .accessibility_label({
                    let summary = summary.clone();
                    move || {
                        Some(
                            format!(
                                "{summary}, {}",
                                if expanded.get() {
                                    s().collapse_records
                                } else {
                                    s().expand_records
                                }
                            )
                            .into(),
                        )
                    }
                })
                .selected(move || expanded.get())
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap_1()
                        .child(
                            text(span)
                                .typo(Type::Headline)
                                .tabular_nums()
                                .text_color(color::INK),
                        )
                        .child(
                            text(detail)
                                .typo(Type::Caption)
                                .tabular_nums()
                                .text_color(color::MUTED),
                        ),
                )
                .child(dynamic(move || {
                    icon(
                        if expanded.get() {
                            Icon::ChevronDown
                        } else {
                            Icon::ChevronRight
                        },
                        18.0,
                        color::MUTED,
                    )
                    .into_element()
                })),
        )
        .child(when(
            move || expanded.get(),
            move || {
                view()
                    .gap_5()
                    .children(days.iter().cloned().map(day_section))
            },
        ))
        .into_element()
}
