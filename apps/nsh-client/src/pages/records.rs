//! Records timeline, newest day first. Filters share one daily index; the
//! scrolling window constructs headers and individual entries on demand.

#[path = "records_data.rs"]
mod data;
#[path = "records_timeline.rs"]
mod timeline;
use data::group;
use std::{
    collections::{BTreeMap, BTreeSet},
    rc::Rc,
};

use navi_finance::{journal::Transaction, money};
use nsh_base::button;
use nsh_core::{geometry::Point, prelude::*};

use super::{
    drafts::drafts_section,
    finance::transaction_row,
    home::Sheets,
    rows::{divider, leading_width, meal_row, text_inset, weight_row},
};
use crate::{
    data::{clock, finance, meals, photos, weights},
    domain::{
        format,
        meal::{Day, Meal},
        weight::Weight,
    },
    i18n::s,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color,
        feedback::empty_state,
        icon,
        segmented::{Segment, segmented},
        space,
        surface::card,
    },
};

/// Days shown at first, and added by Show earlier.
const PAGE: usize = 21;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Filter {
    All,
    Meals,
    Weight,
    Transactions,
}

/// One row of a day.
#[derive(Clone, PartialEq)]
enum Entry {
    Meal(Rc<Meal>),
    Transaction(Rc<Transaction>),
}

/// A day with entries, newest entry first.
#[derive(Clone, PartialEq)]
struct DayRecords {
    day: Day,
    kcal: f64,
    meals: usize,
    weight: Option<Weight>,
    spending: Option<money::Minor>,
    foreign_spending: Vec<(navi_finance::currency::Currency, i64)>,
    entries: Vec<Entry>,
}

/// Only the totals and actions visible in this filter.
#[derive(Clone, PartialEq)]
struct DayHeader {
    day: Day,
    kcal: Option<f64>,
    weight: Option<Weight>,
    spending: Option<money::Minor>,
    foreign_spending: Vec<(navi_finance::currency::Currency, i64)>,
}

impl DayRecords {
    fn header(&self, filter: Filter) -> DayHeader {
        let money = matches!(filter, Filter::All | Filter::Transactions);
        let meals = matches!(filter, Filter::All | Filter::Meals);
        DayHeader {
            day: self.day,
            weight: self.weight.filter(|_| filter == Filter::All),
            kcal: (meals && self.meals > 0).then_some(self.kcal),
            spending: self.spending.filter(|_| money),
            foreign_spending: if money {
                self.foreign_spending.clone()
            } else {
                Vec::new()
            },
        }
    }
}

pub fn records_tab() -> impl IntoElement {
    let filter = signal(Filter::All);
    let shown = signal(PAGE);
    let days = computed(move || {
        group(
            meals::all(),
            weights::all(),
            finance::transactions(),
            &clock::zone(),
        )
    });
    let sheets = Sheets::get();
    // The one day the calendar opened, shown alone until All days.
    let focus = signal(None::<Day>);
    let expanded = signal(BTreeSet::<Day>::new());
    let list = element_ref();
    effect(move || {
        let Some(day) = sheets.jump_to.get() else {
            return;
        };
        untracked(|| {
            sheets.jump_to.set(None);
            expanded.update(BTreeSet::clear);
            filter.set(Filter::All);
            focus.set(Some(day));
        });
        list.scroll_to(
            Point {
                x: px(0.0),
                y: px(0.0),
            },
            false,
        );
    });
    // A focused day whose records are all gone falls back to every day.
    effect(move || {
        if let Some(day) = focus.get()
            && !days.with(|d| d.iter().any(|r| r.day == day))
        {
            untracked(|| focus.set(None));
        }
    });
    let timeline = computed(move || {
        let (filter, focus, shown) = (filter.get(), focus.get(), shown.get());
        days.with(|days| expanded.with(|open| timeline::project(days, filter, focus, shown, open)))
    });
    scroll().flex_1().element_ref(&list).child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb(move || px(crate::pages::home::dock_top_inset() + 12.0))
            .gap_5()
            .child(
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .pt_2()
                    .child(
                        text(|| s().records)
                            .flex_1()
                            .min_w(px(0.0))
                            .typo(Type::LargeTitle)
                            .text_color(color::INK)
                            .role(AccessibilityRole::Header),
                    )
                    .child(
                        IconBtn::new(Icon::Calendar, || s().go_to_day.into())
                            .variant(Variant::Ghost)
                            .on_press(move || sheets.jump.set(true)),
                    )
                    .child(
                        // The primary way money is recorded gets words, not
                        // an icon to guess.
                        Btn::ghost()
                            .label(|| crate::i18n::statement_import::title().into())
                            .on_press(|| crate::nav::push(crate::nav::Route::StatementImport))
                            .min_h(px(48.0)),
                    ),
            )
            .child(
                when(
                    move || focus.get().is_some(),
                    move || focus_bar(focus, days),
                )
                .otherwise(move || {
                    segmented(
                        vec![
                            Segment::new(Filter::All, || s().all_records.into()),
                            Segment::new(Filter::Transactions, || s().transactions.into()),
                            Segment::new(Filter::Meals, || s().meals.into()),
                            Segment::new(Filter::Weight, || s().weight.into()),
                        ],
                        move || filter.get(),
                        move |f| {
                            expanded.update(BTreeSet::clear);
                            filter.set(f);
                        },
                    )
                }),
            )
            .child(drafts_section(true))
            .child(
                when(
                    move || timeline.with(|t| t.rows.is_empty()),
                    move || {
                        // The header's 导入账单 already names the import path;
                        // the empty state offers the one universal entry.
                        card().child(
                            empty_state(Icon::List, || s().no_records.into()).action(
                                Btn::primary()
                                    .label(|| s().new_entry.into())
                                    .on_press(move || {
                                        sheets.capture_draft.set(None);
                                        sheets.capture.set(true);
                                    }),
                            ),
                        )
                    },
                )
                .otherwise(move || {
                    view()
                        .gap_5()
                        .child(timeline::list(timeline, expanded))
                        .child(when(
                            move || timeline.with(|t| t.has_earlier),
                            move || {
                                Btn::secondary()
                                    .label(|| s().show_earlier.into())
                                    .on_press(move || shown.update(|n| *n += PAGE))
                            },
                        ))
                }),
            ),
    )
}

/// Over a focused day: its short date, steps to the days with records before and after it,
/// and All days back to the whole list.
fn focus_bar(focus: Signal<Option<Day>>, days: Memo<Vec<DayRecords>>) -> impl IntoElement {
    // Days are newest first: the next index is the earlier day.
    let step = move |earlier: bool| {
        let day = focus.get()?;
        days.with(|d| {
            let at = d.iter().position(|r| r.day == day)?;
            let to = if earlier {
                at.checked_add(1)?
            } else {
                at.checked_sub(1)?
            };
            d.get(to).map(|r| r.day)
        })
    };
    view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(
            IconBtn::new(Icon::ChevronLeft, || s().previous_day.into())
                .on_press(move || {
                    if let Some(day) = untracked(|| step(true)) {
                        focus.set(Some(day));
                    }
                })
                .disabled(move || step(true).is_none()),
        )
        .child(
            text(move || focus.get().map(|d| s().short_date(d)).unwrap_or_default())
                .typo(Type::Headline)
                .text_color(color::INK)
                .text_center()
                .number_of_lines(1)
                .flex_1(),
        )
        .child(
            IconBtn::new(Icon::ChevronRight, || s().next_day.into())
                .on_press(move || {
                    if let Some(day) = untracked(|| step(false)) {
                        focus.set(Some(day));
                    }
                })
                .disabled(move || step(false).is_none()),
        )
        .child(
            Btn::tonal()
                .size(Size::Small)
                .label(|| s().all_days.into())
                .on_press(move || focus.set(None)),
        )
}

fn day_header(records: &DayHeader) -> impl IntoElement + use<> {
    let sheets = Sheets::get();
    let today = untracked(clock::today);
    let title = match today.days_since(records.day) {
        0 => s().today.to_owned(),
        1 => s().yesterday.to_owned(),
        _ => s().long_date(records.day),
    };
    let kcal = records
        .kcal
        .map(|kcal| format!("{} {}", format::kcal(kcal), s().kcal));
    let weight = records.weight.map(|w| {
        button()
            .on_press(move || sheets.weight.set(Some(w.day)))
            .flex_row()
            .items_center()
            .gap(px(4.0))
            .min_h(px(48.0))
            .px(px(10.0))
            .rounded_full()
            .bg(color::SURFACE_2)
            .active(|s| s.bg(color::SUNKEN))
            .accessibility_label({
                let label = format!(
                    "{}, {}, {} kg",
                    s().edit_weight,
                    s().long_date(w.day),
                    s().kg(w.kg)
                );
                move || Some(label.clone().into())
            })
            .child(icon(Icon::Scale, 13.0, color::MUTED))
            .child(
                text(format!("{} kg", s().kg(w.kg)))
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::BODY),
            )
    });
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .min_h(px(32.0))
                .px(px(4.0))
                .child(
                    text(title)
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .number_of_lines(1)
                        .flex_1()
                        .role(AccessibilityRole::Header),
                )
                .child(weight),
        )
        // One meta row under the day's title: spending, intake, each foreign
        // currency's own line. No negative margins.
        .child(
            (records.spending.is_some() || kcal.is_some() || !records.foreign_spending.is_empty())
                .then(|| {
                    view()
                        .flex_row()
                        .flex_wrap()
                        .gap_3()
                        .px(px(4.0))
                        .child(records.spending.map(|amount| {
                            text(format!(
                                "{} ¥{}",
                                s().spending,
                                crate::ui::currency::grouped(amount)
                            ))
                            .typo(Type::Subhead)
                            .tabular_nums()
                            .text_color(color::MUTED)
                        }))
                        .child(kcal.map(|kcal| {
                            text(kcal)
                                .typo(Type::Subhead)
                                .tabular_nums()
                                .text_color(color::MUTED)
                        }))
                        .children(records.foreign_spending.iter().map(|(currency, amount)| {
                            text(format!(
                                "{} {}",
                                s().spending,
                                crate::ui::currency::format(*amount, *currency)
                            ))
                            .typo(Type::Subhead)
                            .tabular_nums()
                            .text_color(color::MUTED)
                        }))
                }),
        )
}
