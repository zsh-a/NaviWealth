//! The home, at the bottom of the navigation stack: the four tabs over one
//! canvas (each kept alive while hidden, so its scroll position stays), a
//! floating glass tab bar beside the one capture button, and the sheets any
//! tab can open. Pages pushed over the home cover the bar.

use nsh_base::{nav_page, tab, tabs};
use nsh_core::{Haptic, element::Screen, prelude::*};

use super::{
    capture::capture_editor,
    finance::finance_editor,
    parts::status_bar,
    records::records_tab,
    records_jump::jump_sheet,
    today::{garmin_sheet, setup_sheet, today_tab, weight_editor},
    week_review::review_tab,
};
use crate::{
    data::clock,
    domain::meal::Day,
    i18n::s,
    nav::{self, Route, Tab},
    ui::{
        Icon, IconBtn, Type, Typo, Variant, color, icon,
        material::{self, Glass},
        sheet::bottom_sheet,
        space,
        toast::toast_host,
    },
};

/// The bar's height.
const DOCK: f32 = 64.0;
/// The bar's gap above the safe area.
const DOCK_GAP: f32 = 14.0;

/// The space a tab's scrolling content leaves under its last item so it
/// clears the bar.
pub fn dock_clearance() -> f32 {
    DOCK + DOCK_GAP + safe_area().bottom.0 + 28.0
}

/// The sheets the home owns, for its tabs to open (context).
#[derive(Clone, Copy)]
pub struct Sheets {
    pub capture: Signal<bool>,
    pub capture_draft: Signal<Option<String>>,
    pub setup: Signal<bool>,
    /// The day whose weight the editor shows.
    pub weight: Signal<Option<Day>>,
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

pub fn home_page() -> Screen {
    let sheets = Sheets {
        capture: signal(false),
        capture_draft: signal(None),
        setup: signal(false),
        weight: signal(None),
        finance: signal(None),
        garmin: signal(false),
        jump: signal(false),
        jump_to: signal(None),
        records_all: signal(false),
    };
    provide_context(sheets);
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
                .child(fade())
                .child(dock(sheets))
                .child(
                    view()
                        .absolute()
                        .inset_0()
                        .pointer_events(PointerEvents::BoxNone)
                        .style_when(
                            move || sheets.capture.get() || sheets.finance.get().is_some(),
                            |s| s.hidden(),
                        )
                        .child(toast_host(|| DOCK + DOCK_GAP + safe_area().bottom.0 + 12.0)),
                )
                .child(capture_editor(sheets))
                .child(setup_sheet(sheets))
                .child(finance_editor(sheets.finance))
                .child(bottom_sheet(
                    move || sheets.weight.with(Option::is_some),
                    move || sheets.weight.set(None),
                    weight_editor(sheets.weight),
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

/// A tab's content, laid out only while it is chosen.
fn pane(tab: Tab, content: impl IntoElement) -> impl IntoElement {
    view()
        .absolute()
        .inset_0()
        .style_when(move || nav::tab() != tab, |s| s.hidden())
        .accessibility_elements_hidden(move || nav::tab() != tab)
        .child(content)
}

/// The content fades into the canvas under the bar.
fn fade() -> impl IntoElement {
    view()
        .absolute()
        .left_0()
        .right_0()
        .bottom_0()
        .h(move || px(DOCK + DOCK_GAP + safe_area().bottom.0))
        .pointer_events(PointerEvents::None)
        .bg_linear_to_t()
        .gradient_from(color::CANVAS)
        .gradient_via(color::CANVAS.opacity(0.35))
        .gradient_to(color::CANVAS.opacity(0.0))
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
                        .bg(color::SURFACE_2)
                })
                .children(Tab::ALL.map(tab_item)),
        )
        .child(
            IconBtn::new(Icon::Plus, || s().new_entry.into())
                .variant(Variant::Primary)
                .side(56.0)
                .on_press(move || {
                    sheets.capture_draft.set(None);
                    sheets.capture.set(true);
                }),
        )
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
    tab()
        .selected(chosen)
        .on_press(move |_: &()| {
            if !chosen() {
                haptic(Haptic::Selection);
                nav::select(tab_of);
            }
        })
        .accessibility_label(move || Some(tab_name(tab_of).into()))
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
