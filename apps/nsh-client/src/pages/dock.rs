//! The home's floating dock, after prism_ui's `NavigationDock` (FlClash):
//! one glass bar of the four tabs beside one round glass capture button.
//!
//! The chosen tab rests on a soft accent platter, its glyph and label in
//! the accent. A press lifts the platter into a clear lens that grows and
//! magnifies the glyph under it; the lens follows the finger across the
//! tabs, stretching like jelly as it travels, and lifting the finger
//! chooses the tab under it. Every tab stays an ordinary `Tab` of one
//! `Tabs` list, so taps, keyboard focus and screen readers work as before.

use nsh_base::{tab, tabs};
use nsh_core::{
    Haptic, TouchEvent, TouchPhase, TransformKind,
    element::{ElementRef, LayoutTransition, Spring},
    prelude::*,
};

use super::home::Sheets;
use crate::{
    i18n::s,
    nav::{self, Tab},
    ui::{
        Icon, IconBtn, Lift, Type, Typo, Variant, color, icon,
        material::{self, Glass},
        motion, space,
        theme::shadow,
    },
};

/// The bar's height.
pub(super) const BAR: f32 = 62.0;
/// The bar's padding around the lens.
const PAD: f32 = 4.0;
/// A lifted lens grows by this factor: about 8 pt on its 54 pt height.
const LIFT_SCALE: f32 = 1.14;
/// The glyph under a lifted lens is magnified by this factor.
const MAGNIFY: f32 = 1.12;
/// The jelly's stretch per tab travelled, at most two tabs' worth; the
/// lens flattens by 1.4 times its stretch.
const STRETCH: f32 = 0.09;
const SQUASH: f32 = 1.4;

/// The lens's travel to another tab: 400 ms, a little springy.
fn travel() -> LayoutTransition {
    LayoutTransition::spring(Spring::new(400.0).damping_ratio(0.85))
}

pub(super) fn tab_name(tab: Tab) -> &'static str {
    match tab {
        Tab::Today => s().today,
        Tab::Records => s().records,
        Tab::Review => s().review,
        Tab::Assets => s().assets,
    }
}

/// A tab's place in the dock.
pub(super) fn tab_index(tab: Tab) -> usize {
    Tab::ALL
        .iter()
        .position(|known| *known == tab)
        .unwrap_or_default()
}

/// The tab under `x` points from the bar's leading edge, `width` wide.
fn tab_at(x: f32, width: f32) -> Tab {
    let span = (width - 2.0 * PAD).max(1.0);
    let slot = ((x - PAD) / span * Tab::ALL.len() as f32).floor();
    Tab::ALL[slot.clamp(0.0, (Tab::ALL.len() - 1) as f32) as usize]
}

/// A finger on the bar: the lens goes where it is; lifting it after a drag
/// onto another tab chooses that tab. A tap is left to the tab's own press,
/// so the bar never second-guesses it.
#[derive(Debug, Default)]
struct Steer {
    start: Option<Tab>,
    dragged: bool,
}

impl Steer {
    /// The tab the lens should be on while the finger is down, and the tab
    /// to choose once it lifts.
    fn touch(&mut self, phase: TouchPhase, under: Tab) -> (Option<Tab>, Option<Tab>) {
        match phase {
            TouchPhase::Start => {
                *self = Steer {
                    start: Some(under),
                    dragged: false,
                };
                (Some(under), None)
            }
            TouchPhase::Move if self.start.is_some() => {
                self.dragged |= self.start != Some(under);
                (Some(under), None)
            }
            TouchPhase::End if self.start.is_some() => {
                let commit = self.dragged.then_some(under);
                *self = Steer::default();
                (None, commit)
            }
            _ => {
                *self = Steer::default();
                (None, None)
            }
        }
    }
}

pub(super) fn dock(sheets: Sheets, targets: [ElementRef; 4]) -> impl IntoElement {
    // The tab a finger is on, while one is down on the bar.
    let pressed: Signal<Option<Tab>> = signal(None);
    let lens_tab = move || pressed.get().unwrap_or_else(nav::tab);
    // The bar's leading edge and width, in its row.
    let bar = stored((0.0_f32, 0.0_f32));
    let steer = stored(Steer::default());
    let covered = move || sheets.any_open() || !nav::open().is_empty();

    view()
        .absolute()
        .left(px(space::GUTTER))
        .right(px(space::GUTTER))
        .bottom(move || px(safe_area().bottom.0 + super::home::DOCK_GAP))
        .flex_row()
        .items_center()
        .gap(px(8.0))
        .child(
            // The touches of the whole bar steer the lens; the tabs inside
            // keep their own presses.
            view()
                .flex_1()
                .on_layout(move |b: &Bounds<Points>| {
                    bar.replace((b.origin.x.0, b.size.width.0));
                })
                .on_touch(move |e: &TouchEvent| {
                    let Some(point) = e.points.iter().find(|p| p.changed) else {
                        return;
                    };
                    let (left, width) = bar.get();
                    if width <= 0.0 {
                        return; // Not laid out yet: the tabs' own presses suffice.
                    }
                    let under = tab_at(point.page.x.0 - space::GUTTER - left, width);
                    let was = pressed.get_untracked();
                    let (now, commit) = steer.with(|steer| steer.touch(e.phase, under));
                    if now != was {
                        if was.is_some() && now.is_some() {
                            haptic(Haptic::Selection);
                        }
                        pressed.set(now);
                    }
                    if let Some(chosen) = commit.filter(|t| *t != nav::tab()) {
                        haptic(Haptic::Selection);
                        nav::select(chosen);
                    }
                })
                .child(
                    tabs()
                        .flex_row()
                        .h(px(BAR))
                        .p(px(PAD))
                        .rounded_full()
                        .style_with(|s| material::glass(s, Glass::Dock))
                        .style_when(covered, |s| s.bg(color::GLASS).backdrop_filter_none())
                        .child(lens(targets, pressed, lens_tab))
                        .children(
                            Tab::ALL.iter().zip(targets).map(|(tab_of, target)| {
                                tab_item(*tab_of, target, pressed, lens_tab)
                            }),
                        ),
                ),
        )
        .child(
            // The plus dips toward the rising capture sheet and settles
            // back, one motion shared with what it opened.
            IconBtn::new(Icon::Plus, || s().new_entry.into())
                .variant(Variant::Dock)
                .side(BAR)
                .on_press(move || {
                    sheets.capture_draft.set(None);
                    sheets.capture.set(true);
                })
                .style_when(covered, |s| s.bg(color::GLASS).backdrop_filter_none())
                .bind_scale(&capture_lift(sheets.capture)),
        )
}

/// The platter under the chosen tab, which a press lifts into a lens that
/// follows the finger. It takes no presses and screen readers skip it.
fn lens(
    targets: [ElementRef; 4],
    pressed: Signal<Option<Tab>>,
    lens_tab: impl Fn() -> Tab + Copy + 'static,
) -> impl IntoElement {
    let lift = animated_value(1.0);
    let stretch_x = animated_value(1.0);
    let stretch_y = animated_value(1.0);
    effect(move || {
        let down = pressed.get().is_some();
        if reduce_motion() {
            lift.set(1.0);
        } else {
            lift.spring(if down { LIFT_SCALE } else { 1.0 }, motion::LIFT);
        }
    });
    // Jelly: the lens stretches along its travel and wobbles back into
    // shape on an underdamped spring.
    let was = stored(untracked(|| tab_index(lens_tab())));
    effect(move || {
        let now = tab_index(lens_tab());
        let from = was.replace(now);
        if now == from || untracked(reduce_motion) {
            return;
        }
        let stretch = (STRETCH * now.abs_diff(from) as f32).min(2.0 * STRETCH);
        spawn(async move {
            let _ = stretch_x.timing(1.0 + stretch, motion::INSTANT, Easing::EaseOut);
            let _ = stretch_y
                .timing(1.0 - stretch * SQUASH, motion::INSTANT, Easing::EaseOut)
                .await;
            stretch_x.spring(1.0, motion::JELLY);
            stretch_y.spring(1.0, motion::JELLY);
        });
    });
    let lifted = move || pressed.get().is_some();
    view()
        .absolute()
        .pointer_events(PointerEvents::None)
        .accessibility_elements_hidden(true)
        // `follow` places it along the bar; its height is the bar's inside.
        .follow(move || Some(targets[tab_index(lens_tab())]))
        .follow_transition(move || (!reduce_motion()).then(travel))
        .top(px(PAD))
        .bottom(px(PAD))
        .rounded_full()
        .bg(color::ACCENT_SOFT)
        .border(px(0.75))
        .border_color(AdaptiveColor::TRANSPARENT)
        .transition_colors()
        .duration(motion::FAST)
        .style_when(lifted, |s| {
            s.bg(color::SURFACE.opacity(0.46))
                .border_color(color::GLASS_EDGE)
                .lift(&shadow::LENS)
        })
        .bind_transform(TransformKind::ScaleX, &lift.mul(&stretch_x))
        .bind_transform(TransformKind::ScaleY, &lift.mul(&stretch_y))
}

fn tab_item(
    tab_of: Tab,
    target: ElementRef,
    pressed: Signal<Option<Tab>>,
    lens_tab: impl Fn() -> Tab + Copy + 'static,
) -> impl IntoElement {
    let chosen = move || nav::tab() == tab_of;
    // The accent goes with the lens: whatever it covers takes its color.
    let tint = move || {
        if lens_tab() == tab_of {
            color::ACCENT_INK
        } else {
            color::ON_GLASS_MUTED
        }
    };
    let glyph = match tab_of {
        Tab::Today => Icon::TabToday,
        Tab::Records => Icon::TabRecords,
        Tab::Review => Icon::TabReview,
        Tab::Assets => Icon::TabAssets,
    };
    let magnify = animated_value(1.0);
    effect(move || {
        let under = pressed.get() == Some(tab_of);
        if reduce_motion() {
            magnify.set(1.0);
        } else {
            magnify.spring(if under { MAGNIFY } else { 1.0 }, motion::LIFT);
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
        .flex_1()
        .h(px(BAR - 2.0 * PAD))
        .rounded_full()
        // The lens's target: the whole tab.
        .child(view().absolute().inset_0().element_ref(&target))
        .child(
            view()
                .flex_1()
                .items_center()
                .justify_center()
                .gap(px(2.0))
                .bind_scale(&magnify)
                .child(icon(glyph, 24.0, tint))
                .child(
                    text(move || tab_name(tab_of))
                        .typo(Type::Caption)
                        .text_size(px(11.0))
                        .text_color(tint),
                ),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_touch_maps_to_the_tab_under_it_and_clamps_at_the_ends() {
        let width = 280.0;
        assert_eq!(tab_at(-20.0, width), Tab::Today);
        assert_eq!(tab_at(10.0, width), Tab::Today);
        assert_eq!(tab_at(100.0, width), Tab::Records);
        assert_eq!(tab_at(170.0, width), Tab::Assets);
        assert_eq!(tab_at(270.0, width), Tab::Review);
        assert_eq!(tab_at(400.0, width), Tab::Review);
    }

    #[test]
    fn a_tap_is_left_to_the_tab_and_only_a_drag_onto_another_tab_chooses() {
        let mut steer = Steer::default();
        assert_eq!(
            steer.touch(TouchPhase::Start, Tab::Records),
            (Some(Tab::Records), None)
        );
        assert_eq!(steer.touch(TouchPhase::End, Tab::Records), (None, None));

        assert_eq!(
            steer.touch(TouchPhase::Start, Tab::Today),
            (Some(Tab::Today), None)
        );
        assert_eq!(
            steer.touch(TouchPhase::Move, Tab::Records),
            (Some(Tab::Records), None)
        );
        assert_eq!(
            steer.touch(TouchPhase::Move, Tab::Assets),
            (Some(Tab::Assets), None)
        );
        assert_eq!(
            steer.touch(TouchPhase::End, Tab::Assets),
            (None, Some(Tab::Assets))
        );

        // Dragging away and back still chooses where the finger lifts.
        steer.touch(TouchPhase::Start, Tab::Today);
        steer.touch(TouchPhase::Move, Tab::Review);
        assert_eq!(
            steer.touch(TouchPhase::End, Tab::Today),
            (None, Some(Tab::Today))
        );

        // A cancelled touch chooses nothing, nor does a stray end.
        steer.touch(TouchPhase::Start, Tab::Today);
        steer.touch(TouchPhase::Move, Tab::Review);
        assert_eq!(steer.touch(TouchPhase::Cancel, Tab::Review), (None, None));
        assert_eq!(steer.touch(TouchPhase::End, Tab::Review), (None, None));
    }
}
