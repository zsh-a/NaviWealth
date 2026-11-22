//! The home, at the bottom of the navigation stack: the four tabs over one
//! canvas (each kept alive while hidden, so its scroll position stays), a
//! floating glass tab bar beside the one capture button, and the sheets any
//! tab can open. Pages pushed over the home cover the bar.

use nsh_base::{nav_page, tab, tabs};
use nsh_core::{
    Haptic,
    element::{Easing, Screen},
    prelude::*,
};

use super::{
    capture::capture_editor,
    finance::finance_editor,
    parts::status_bar,
    records::records_tab,
    records_jump::jump_sheet,
    today::{body_overview, garmin_sheet, setup_sheet, today_tab, weight_editor},
    week_review::review_tab,
};
use crate::{
    data::{
        clock,
        incoming::{self, Opened},
    },
    domain::meal::Day,
    i18n::s,
    nav::{self, Route, Tab},
    ui::{
        Icon, IconBtn, Type, Typo, Variant, color, icon,
        material::{self, Glass},
        motion,
        sheet::{bottom_sheet, retained, task_host_with_keyboard},
        space,
        toast::{show_toast, toast_host},
    },
};

/// The bar's height.
const DOCK: f32 = 64.0;
/// The bar's gap above the safe area.
const DOCK_GAP: f32 = 14.0;

#[derive(Clone, PartialEq)]
enum BodyPanel {
    Overview(Day),
    Edit(Day),
}

/// Top edge of the dock, measured from the bottom of the home surface.
pub(crate) fn dock_top_inset() -> f32 {
    DOCK + DOCK_GAP + safe_area().bottom.0
}

/// The sheets the home owns, for its tabs to open (context).
#[derive(Clone, Copy)]
pub struct Sheets {
    pub capture: Signal<bool>,
    pub capture_draft: Signal<Option<String>>,
    pub setup: Signal<bool>,
    /// The day whose weight the editor shows.
    pub weight: Signal<Option<Day>>,
    /// Today opens an overview before editing an individual day's weight.
    pub body: Signal<Option<Day>>,
    /// Empty id creates a transaction; an existing id opens its editor.
    pub finance: Signal<Option<String>>,
    pub garmin: Signal<bool>,
    /// The Records calendar for going to a day.
    pub jump: Signal<bool>,
    /// The day Records should scroll to, set by the calendar.
    pub jump_to: Signal<Option<Day>>,
    /// A saved batch can span several days; show all records without old filters.
    pub records_all: Signal<bool>,
}

impl Sheets {
    /// Whether a home sheet is showing (tracked); it may hold unsaved input.
    fn any_open(&self) -> bool {
        self.capture.get()
            || self.setup.get()
            || self.weight.with(Option::is_some)
            || self.body.with(Option::is_some)
            || self.finance.with(Option::is_some)
            || self.garmin.get()
            || self.jump.get()
    }
}

impl Sheets {
    /// The home's sheets; only the home's tabs call it.
    pub fn get() -> Self {
        use_context::<Sheets>().expect("the home provides its sheets")
    }

    /// A new meal by hand, today.
    pub fn manual(self) {
        nav::push(Route::NewMeal {
            day: clock::today(),
            capture: None,
        });
    }
}

/// Shows what another app shared. A statement opens its review at once;
/// pushing a page closes nothing. The capture draft (unsent) and notices
/// show on the home, so they wait until no page or home sheet covers it:
/// nothing unsaved is closed and every notice is seen.
fn open_shared(sheets: Sheets) {
    effect(move || {
        let Some(opened) = incoming::request() else {
            return;
        };
        if opened != Opened::Statement && (!nav::open().is_empty() || sheets.any_open()) {
            return;
        }
        untracked(|| {
            incoming::clear();
            match opened {
                Opened::Statement => nav::push(Route::StatementImport),
                Opened::Capture(id) => {
                    sheets.capture_draft.set(Some(id));
                    sheets.capture.set(true);
                }
                Opened::StatementBusy => show_toast(s().incoming_statement_busy(), None),
                Opened::Unsupported => show_toast(s().incoming_unsupported(), None),
            }
        });
    });
}

pub fn home_page() -> Screen {
    let sheets = Sheets {
        capture: signal(false),
        capture_draft: signal(None),
        setup: signal(false),
        weight: signal(None),
        body: signal(None),
        finance: signal(None),
        garmin: signal(false),
        jump: signal(false),
        jump_to: signal(None),
        records_all: signal(false),
    };
    provide_context(sheets);
    open_shared(sheets);
    // Keep the departing editor's budget until its native host unmounts;
    // setting weight=None alone must not expand it during the exit slide.
    let body_editing = signal(false);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::preview::home_opened(
        sheets.capture,
        sheets.capture_draft,
        sheets.jump,
        sheets.jump_to,
        sheets.finance,
    );
    nav_page()
        .title(|| SharedString::from(tab_name(nav::tab())))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(pane(Tab::Today, today_tab()))
                .child(pane(Tab::Records, records_tab()))
                .child(pane(Tab::Assets, super::assets::assets_tab()))
                .child(pane(Tab::Review, review_tab()))
                .child(dock(sheets))
                .child(
                    view()
                        .absolute()
                        .inset_0()
                        .pointer_events(PointerEvents::BoxNone)
                        .style_when(
                            move || {
                                sheets.capture.get()
                                    || sheets.finance.get().is_some()
                                    || sheets.body.get().is_some()
                                    || sheets.weight.get().is_some()
                            },
                            |s| s.hidden(),
                        )
                        .child(toast_host(|| dock_top_inset() + 12.0)),
                )
                .child(capture_editor(sheets))
                .child(setup_sheet(sheets))
                .child(finance_editor(sheets.finance))
                .child(task_host_with_keyboard(
                    move || sheets.weight.get().is_some() || sheets.body.get().is_some(),
                    move || {
                        sheets.weight.set(None);
                        sheets.body.set(None);
                    },
                    move || body_editing.get(),
                    move || {
                        retained(
                            move || {
                                sheets
                                    .weight
                                    .get()
                                    .map(BodyPanel::Edit)
                                    .or_else(|| sheets.body.get().map(BodyPanel::Overview))
                            },
                            move |panel| match panel {
                                BodyPanel::Edit(_) => {
                                    body_editing.set(true);
                                    weight_editor(sheets.weight).into_element()
                                }
                                BodyPanel::Overview(day) => {
                                    body_editing.set(false);
                                    body_overview(day).into_element()
                                }
                            },
                        )
                        .into_element()
                    },
                ))
                .child(bottom_sheet(
                    move || sheets.garmin.get(),
                    move || sheets.garmin.set(false),
                    garmin_sheet(),
                ))
                .child(bottom_sheet(
                    move || sheets.jump.get(),
                    move || sheets.jump.set(false),
                    jump_sheet(sheets),
                )),
        )
}

fn tab_name(tab: Tab) -> &'static str {
    match tab {
        Tab::Today => s().today,
        Tab::Records => s().records,
        Tab::Review => s().review,
        Tab::Assets => s().assets,
    }
}

/// A tab's content, laid out only while it is chosen. Content scrolls
/// beneath the glass dock; the tab's tail keeps its own clearance. A chosen
/// tab fades in over the previous one, quick enough to read as a state
/// change rather than a wait.
fn pane(tab: Tab, content: impl IntoElement) -> impl IntoElement {
    let shown = animated_value(1.0);
    let mounted = stored(false);
    let was_index = stored(untracked(|| tab_index(nav::tab())));
    // The incoming pane arrives from where the user went: right for a step
    // right, left for a step left, so the tabs read as places on one line.
    let slide = animated_value(0.0);
    effect(move || {
        let now = nav::tab();
        let prev = was_index.replace(tab_index(now));
        if now != tab {
            return;
        }
        if !mounted.replace(true) {
            return; // The first tab is already on screen; it does not arrive.
        }
        if reduce_motion() {
            shown.set(1.0);
            slide.set(0.0);
            return;
        }
        shown.set(0.0);
        slide.set(if tab_index(now) >= prev { 12.0 } else { -12.0 });
        shown.timing(1.0, motion::FAST, Easing::EaseOut);
        slide.timing(0.0, motion::FAST, motion::SETTLE);
    });
    view()
        .absolute()
        .inset_0()
        .bind_opacity(&shown)
        .bind_translate_x(&slide)
        .style_when(move || nav::tab() != tab, |s| s.hidden())
        .accessibility_elements_hidden(move || nav::tab() != tab)
        .child(content)
}

/// A tab's place in the dock, for the direction of its arrival.
fn tab_index(tab: Tab) -> usize {
    Tab::ALL
        .iter()
        .position(|known| *known == tab)
        .unwrap_or_default()
}

fn dock(sheets: Sheets) -> impl IntoElement {
    view()
        .absolute()
        .left(px(space::GUTTER))
        .right(px(space::GUTTER))
        .bottom(move || px(safe_area().bottom.0 + DOCK_GAP))
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            tabs()
                .flex_1()
                .flex_row()
                .h(px(DOCK))
                .p(px(6.0))
                .gap(px(2.0))
                .rounded_full()
                .style_with(|s| material::glass(s, Glass::Dock))
                .style_when(
                    move || {
                        sheets.capture.get()
                            || sheets.setup.get()
                            || sheets.finance.get().is_some()
                            || sheets.weight.get().is_some()
                            || sheets.garmin.get()
                            || sheets.jump.get()
                            || !nav::open().is_empty()
                    },
                    |s| s.bg(color::SURFACE).backdrop_filter_none(),
                )
                .indicator_style(|s| {
                    s.top(px(6.0))
                        .bottom(px(6.0))
                        .rounded_full()
                        // An ink tint reads on translucent glass in both
                        // appearances; an opaque well read as a grey patch.
                        .bg(color::INK.opacity(0.07))
                })
                .children(Tab::ALL.map(tab_item)),
        )
        .child(
            // The plus dips toward the rising capture sheet and settles
            // back, one motion shared with what it opened.
            IconBtn::new(Icon::Plus, || s().new_entry.into())
                .variant(Variant::Primary)
                .side(56.0)
                .on_press(move || {
                    sheets.capture_draft.set(None);
                    sheets.capture.set(true);
                })
                .bind_scale(&capture_lift(sheets.capture)),
        )
}

/// Scales the plus down while the capture sheet it opened rises; reduced
/// motion keeps it still.
fn capture_lift(open: Signal<bool>) -> AnimatedValue {
    let lift = animated_value(1.0);
    effect(move || {
        if open.get() && !reduce_motion() {
            lift.set(0.92);
            lift.timing(1.0, motion::FAST, motion::SETTLE);
        }
    });
    lift
}

fn tab_item(tab_of: Tab) -> impl IntoElement {
    let chosen = move || nav::tab() == tab_of;
    let tint = move || {
        if chosen() {
            color::INK
        } else {
            color::ON_GLASS_MUTED
        }
    };
    let glyph = match tab_of {
        Tab::Today => Icon::Sun,
        Tab::Records => Icon::List,
        Tab::Review => Icon::Chart,
        Tab::Assets => Icon::Wallet,
    };
    // The freshly chosen icon pops once, on the press spring, and the
    // indicator keeps its native slide.
    let pop = animated_value(1.0);
    let was_chosen = stored(untracked(|| nav::tab() == tab_of));
    effect(move || {
        let chosen_now = chosen();
        let was = was_chosen.replace(chosen_now);
        if chosen_now && !was && !reduce_motion() {
            pop.set(1.08);
            pop.timing(1.0, motion::FAST, motion::SETTLE);
        }
    });
    tab()
        .selected(chosen)
        .on_press(move |_: &()| {
            if !chosen() {
                haptic(Haptic::Selection);
                nav::select(tab_of);
            }
        })
        .accessibility_label(move || Some(tab_name(tab_of).into()))
        .bind_scale(&pop)
        .flex_1()
        .h(px(DOCK - 12.0))
        .items_center()
        .justify_center()
        .gap(px(2.0))
        .rounded_full()
        .child(icon(glyph, 22.0, tint))
        .child(
            text(move || tab_name(tab_of))
                .typo(Type::Caption)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(tint),
        )
}
