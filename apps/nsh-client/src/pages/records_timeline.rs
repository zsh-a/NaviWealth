//! The current page holds references into the day index. NSH builds a view
//! only when a heading, disclosure or individual record enters its window.
use super::*;
use crate::ui::surface::row_button;

#[derive(Clone, PartialEq)]
pub(super) enum Row {
    Header(DayHeader),
    Entry {
        entry: Entry,
        first: bool,
        leading: f32,
    },
    Weight(Weight),
    Run {
        newest: Weight,
        oldest: Weight,
        count: usize,
        open: bool,
    },
}

impl Row {
    pub(super) fn key(&self) -> String {
        match self {
            Self::Header(d) => format!("day:{}", d.day),
            Self::Entry { entry, .. } => match entry {
                Entry::Meal(m) => format!("meal:{}", m.id),
                Entry::Transaction(t) => format!("transaction:{}", t.id),
            },
            Self::Weight(w) => format!("weight:{}", w.day),
            Self::Run { newest, .. } => format!("run:{}", newest.day),
        }
    }

    fn render(&self, top: bool, expanded: Signal<BTreeSet<Day>>) -> AnyElement {
        match self {
            Self::Header(day) => view()
                .pt(if top { px(0.0) } else { px(20.0) })
                .child(day_header(day))
                .into_element(),
            Self::Entry {
                entry,
                first,
                leading,
            } => {
                let row = match entry {
                    Entry::Meal(meal) => {
                        if let Some(photo) = &meal.photo {
                            spawn(photos::load(vec![photo.clone()]));
                        }
                        meal_row(meal.as_ref().clone(), *leading).into_element()
                    }
                    Entry::Transaction(t) => {
                        let sheets = Sheets::get();
                        let id = t.id.clone();
                        transaction_row(t.as_ref().clone(), *leading, move || {
                            sheets.finance.set(Some(id.clone()))
                        })
                        .into_element()
                    }
                };
                view()
                    .pt(if *first { px(12.0) } else { px(0.0) })
                    .child((!*first).then(|| divider(text_inset(*leading))))
                    .child(row)
                    .into_element()
            }
            Self::Weight(w) => {
                let sheets = Sheets::get();
                let day = w.day;
                view()
                    .pt_3()
                    .child(weight_row(*w, move || sheets.weight.set(Some(day))))
                    .into_element()
            }
            Self::Run {
                newest,
                oldest,
                count,
                open,
            } => view()
                .pt(if top { px(0.0) } else { px(20.0) })
                .child(disclosure(*newest, *oldest, *count, *open, expanded))
                .into_element(),
        }
    }
}

#[derive(PartialEq)]
pub(super) struct Timeline {
    pub(super) rows: Vec<Row>,
    pub(super) has_earlier: bool,
}

pub(super) fn project(
    days: &[DayRecords],
    filter: Filter,
    focus: Option<Day>,
    shown: usize,
    expanded: &BTreeSet<Day>,
) -> Timeline {
    let mut matching = days.iter().filter(|d| {
        focus.is_none_or(|day| d.day == day)
            && match filter {
                Filter::All => true,
                Filter::Transactions => d.entries.len() > d.meals,
                Filter::Meals => d.meals > 0,
                Filter::Weight => d.weight.is_some(),
            }
    });
    let page: Vec<_> = matching.by_ref().take(shown).collect();
    let collapse = filter == Filter::All && focus.is_none();
    let mut rows = Vec::new();
    for group in page.chunk_by(|a, b| collapse && a.entries.is_empty() && b.entries.is_empty()) {
        if let [first, .., last] = group
            && let (Some(newest), Some(oldest)) = (first.weight, last.weight)
        {
            let open = expanded.contains(&newest.day);
            rows.push(Row::Run {
                newest,
                oldest,
                count: group.len(),
                open,
            });
            if open {
                rows.extend(group.iter().map(|day| Row::Header(day.header(filter))));
            }
        } else {
            for day in group {
                append_day(&mut rows, day, filter);
            }
        }
    }
    Timeline {
        rows,
        has_earlier: matching.next().is_some(),
    }
}

fn append_day(rows: &mut Vec<Row>, day: &DayRecords, filter: Filter) {
    rows.push(Row::Header(day.header(filter)));
    if filter == Filter::Weight {
        if let Some(weight) = day.weight {
            rows.push(Row::Weight(weight));
        }
        return;
    }
    let leading = leading_width(
        filter != Filter::Transactions
            && day
                .entries
                .iter()
                .any(|e| matches!(e, Entry::Meal(m) if m.photo.is_some())),
    );
    let mut first = true;
    for entry in &day.entries {
        if matches!(
            (filter, entry),
            (Filter::Meals, Entry::Transaction(_)) | (Filter::Transactions, Entry::Meal(_))
        ) {
            continue;
        }
        rows.push(Row::Entry {
            entry: entry.clone(),
            leading,
            first,
        });
        first = false;
    }
}

pub(super) fn list(timeline: Memo<Timeline>, expanded: Signal<BTreeSet<Day>>) -> impl IntoElement {
    virtual_list(
        move || timeline.with(|t| t.rows.len()),
        move |at| {
            let cell = computed(move || {
                let index = at.index();
                timeline.with(|t| t.rows.get(index).cloned().map(|r| (r, index == 0)))
            });
            dynamic(move || {
                cell.with(|value| {
                    value
                        .as_ref()
                        .map(|(row, top)| untracked(|| row.render(*top, expanded)))
                })
            })
        },
    )
    .keys(move || timeline.with(|t| t.rows.iter().map(Row::key).collect::<Vec<_>>()))
    .estimated_item_size(px(72.0))
    .viewport(nsh_core::ListViewport::Parent)
}

fn disclosure(
    newest: Weight,
    oldest: Weight,
    count: usize,
    open: bool,
    expanded: Signal<BTreeSet<Day>>,
) -> impl IntoElement {
    let span = if oldest.day.0.year() == newest.day.0.year() {
        s().week_span(oldest.day, newest.day)
    } else {
        format!("{} – {}", oldest.day, newest.day)
    };
    let detail = format!(
        "{} · {} → {} kg",
        s().weight_only_days.replace("{n}", &count.to_string()),
        s().kg(oldest.kg),
        s().kg(newest.kg)
    );
    let summary = format!("{span} · {detail}");
    row_button(move || {
        expanded.update(|days| {
            if !days.remove(&newest.day) {
                days.insert(newest.day);
            }
        })
    })
    .px_1()
    .py_2()
    .min_h(px(48.0))
    .gap_2()
    .accessibility_label(move || {
        Some(
            format!(
                "{summary}, {}",
                if open {
                    s().collapse_records
                } else {
                    s().expand_records
                }
            )
            .into(),
        )
    })
    .selected(open)
    .child(
        view()
            .flex_1()
            .min_w(px(0.0))
            .gap_1()
            .child(
                text(span)
                    .typo(Type::Headline)
                    .text_color(color::INK)
                    .number_of_lines(1),
            )
            .child(
                text(detail)
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(color::MUTED),
            ),
    )
    .child(icon(
        if open {
            Icon::ChevronDown
        } else {
            Icon::ChevronRight
        },
        18.0,
        color::MUTED,
    ))
}
