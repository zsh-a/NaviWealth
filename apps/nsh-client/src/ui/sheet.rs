//! The app's bottom sheet: `nsh_base`'s sheet (slide, backdrop, Escape,
//! back, swipe down) in the app's surface, with a grabber, the safe area
//! and the keyboard taken into account.

use nsh_base::{OpenChangeReason, SheetEvent, sheet};
use nsh_core::prelude::*;
use std::rc::Rc;

#[derive(Clone)]
struct Lifecycle {
    opened: Signal<bool>,
    closed: Rc<dyn Fn()>,
}

#[derive(Clone)]
struct TaskHost {
    /// The active panel's step back (its Back button and the system back).
    close: Stored<Option<Rc<dyn Fn()>>>,
    /// The active panel's guarded exit from the whole task (swipe, backdrop).
    dismiss: Stored<Option<Rc<dyn Fn()>>>,
    open: Rc<dyn Fn() -> bool>,
}

#[derive(Clone)]
struct ConversationKeyboard;

#[derive(Clone)]
struct KeyboardBudget(Rc<dyn Fn() -> bool>);

/// Inside a task host, how a swipe or a backdrop press leaves the whole task
/// from the current panel (after its own discard guard). Back still steps
/// back. Cleared when the panel unmounts; outside a host it does nothing.
pub fn task_dismiss(dismiss: impl Fn() + 'static) {
    let Some(host) = use_context::<TaskHost>() else {
        return;
    };
    let dismiss: Rc<dyn Fn()> = Rc::new(dismiss);
    host.dismiss.replace(Some(dismiss.clone()));
    cleanup(move || {
        if host
            .dismiss
            .with(|d| d.as_ref().is_some_and(|d| Rc::ptr_eq(d, &dismiss)))
        {
            host.dismiss.replace(None);
        }
    });
}

/// Retain the task and its reactive scope until the native sheet has finished
/// leaving. Closing the requested value must never remove its animation owner.
pub fn retained<T: Clone + PartialEq + 'static>(
    requested: impl Fn() -> Option<T> + 'static,
    render: impl Fn(T) -> AnyElement + 'static,
) -> impl IntoElement {
    let requested = Rc::new(requested);
    let render = Rc::new(render);
    let mounted = signal(None::<T>);
    let watch = requested.clone();
    let host = use_context::<TaskHost>();
    let embedded = host.is_some();
    effect(move || {
        if let Some(next) = watch() {
            mounted.set(Some(next));
        } else if host.as_ref().is_some_and(|h| (h.open)()) {
            // Inner Back changes only the frame; closing the host retains it.
            mounted.set(None);
        }
    });
    dynamic(move || {
        let Some(value) = mounted.get() else {
            return view().into_element();
        };
        let requested = requested.clone();
        let render = render.clone();
        untracked(move || {
            if !embedded {
                provide_context(Lifecycle {
                    opened: signal(false),
                    closed: Rc::new(move || {
                        if requested().is_none() {
                            mounted.set(None);
                        }
                    }),
                });
            }
            render(value)
        })
    })
}

/// Focus only after the real Sheet Open lifecycle, never during its entrance.
/// Inner task panels already have an open host, so focus follows their mount.
pub fn initial_focus() -> nsh_core::element::ElementRef {
    let target = element_ref();
    if let Some(lifecycle) = use_context::<Lifecycle>() {
        effect(move || {
            if lifecycle.opened.get() {
                spawn(async move {
                    next_frame().await;
                    if lifecycle.opened.get_untracked() {
                        target.focus();
                    }
                });
            }
        });
    }
    target
}

pub fn is_task_panel() -> bool {
    use_context::<TaskHost>().is_some()
}

/// One native sheet for a menu and all of its task panels. Embedded task sheets
/// contribute their layout and dismissal guard without making another overlay.
/// A reading panel can use the full sheet. Switching to entry reserves the
/// keyboard's space using the same native host, without stacked overlays.
pub fn task_host_with_keyboard(
    open: impl Fn() -> bool + Copy + 'static,
    close: impl Fn() + Copy + 'static,
    editing: impl Fn() -> bool + Copy + 'static,
    content: impl Fn() -> AnyElement + 'static,
) -> impl IntoElement {
    retained(
        move || open().then_some(()),
        move |_| {
            provide_context(KeyboardBudget(Rc::new(editing)));
            let host = TaskHost {
                close: stored(None),
                dismiss: stored(None),
                open: Rc::new(open),
            };
            provide_context(host.clone());
            shell(
                open,
                move |reason| {
                    // A swipe or backdrop press means "leave"; declining it
                    // would bounce the sheet back up with a different panel.
                    let leave = matches!(
                        reason,
                        OpenChangeReason::Swipe | OpenChangeReason::BackdropPress
                    );
                    let handler = if leave {
                        host.dismiss.with(|f| f.clone())
                    } else {
                        host.close.with(|f| f.clone())
                    };
                    match handler {
                        Some(handler) => handler(),
                        None => close(),
                    }
                },
                content(),
            )
            .into_element()
        },
    )
}

use super::{
    material::{self, Glass},
    theme::{color, radius, space},
};

/// A sheet shown while `open` reads true; `close` is asked to set it false
/// when the user dismisses it. `content` is made on each opening (use a
/// `#[component]` for state that should start fresh).
pub fn bottom_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    content: impl IntoElement,
) -> impl IntoElement {
    shell(
        open,
        move |_| close(),
        scroll().flex_shrink(1.0).child(
            view()
                .px(px(space::GUTTER))
                .pt_2()
                .pb_safe_area_plus(px(16.0))
                .gap_4()
                .child(content),
        ),
    )
}

/// A task sheet with a fixed header and actions; only its body scrolls.
/// The available height excludes the keyboard, including on small phones.
pub fn task_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    header: impl IntoElement,
    body: impl IntoElement,
    actions: impl IntoElement,
) -> impl IntoElement {
    task_layout(open, close, header, body, actions, || Some(540.0))
}

/// Content-led capture: short drafts stay compact; long results scroll under
/// the fixed header and action. The keyboard limits the same available space.
pub fn fitted_task_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    header: impl IntoElement,
    body: impl IntoElement,
    actions: impl IntoElement,
) -> impl IntoElement {
    task_layout(open, close, header, body, actions, || None)
}

/// Capture starts content-sized. A conversation occupies the available screen
/// above the live keyboard, including when reopened directly into review.
pub fn conversation_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    expanded: impl Fn() -> bool + Copy + 'static,
    header: impl IntoElement,
    body: impl IntoElement,
    actions: impl IntoElement,
) -> impl IntoElement {
    provide_context(ConversationKeyboard);
    task_layout(open, close, header, body, actions, move || {
        expanded().then_some(f32::INFINITY)
    })
}

fn task_layout(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    header: impl IntoElement,
    body: impl IntoElement,
    actions: impl IntoElement,
    fill_height: impl Fn() -> Option<f32> + Copy + 'static,
) -> impl IntoElement {
    // One height calculation, shared with the outer shell. The grabber uses 20pt.
    let planned = untracked(planned_keyboard);
    let height = height_budget(planned);
    let available = move || (height() - 20.0).max(100.0);
    let layout = view()
        .max_h(move || px(available()))
        .style_when(
            move || fill_height().is_some(),
            move |s| s.h(move || px(available().min(fill_height().unwrap_or_default()))),
        )
        .child(
            view()
                .test_id("task-header")
                .flex_shrink(0.0)
                .px(px(space::GUTTER))
                .py_2()
                .child(header),
        )
        .child(
            scroll()
                .flex_shrink(1.0)
                .style_when(move || fill_height().is_some(), |s| s.flex_1())
                .min_h(px(0.0))
                .child(view().px(px(space::GUTTER)).py_2().child(body)),
        )
        .child(
            view()
                .test_id("task-actions")
                .flex_shrink(0.0)
                .px(px(space::GUTTER))
                .pt_2()
                .pb_safe_area_plus(px(12.0))
                .child(actions)
                .child(super::toast::toast_view(|| 68.0)),
        );
    if let Some(host) = use_context::<TaskHost>() {
        host.close.replace(Some(Rc::new(close)));
        layout.into_element()
    } else {
        shell(open, move |_| close(), layout).into_element()
    }
}

/// Space kept between a sheet and the keyboard above it.
const KEYBOARD_GAP: f32 = 20.0;
/// Before the keyboard has ever shown, the share of the window it is
/// assumed to cover.
const KEYBOARD_GUESS: f32 = 0.38;

fn height_budget(planned: Option<f32>) -> impl Fn() -> f32 + Copy {
    let conversation = use_context::<ConversationKeyboard>().is_some();
    let budget = stored(use_context::<KeyboardBudget>());
    move || {
        if conversation || budget.with(|b| b.as_ref().is_some_and(|b| !(b.0)())) {
            (window().height.0 * 0.92 - keyboard_height().0).max(140.0)
        } else {
            sheet_height(planned)
        }
    }
}

/// The keyboard height a sheet plans for, read once when it opens so the
/// sheet keeps its size: the last height the keyboard reached, if it has
/// shown. Without one, [`sheet_height`] guesses from the current window.
fn planned_keyboard() -> Option<f32> {
    Some(crate::data::keyboard::last_height()).filter(|h| *h > 0.0)
}

/// A sheet's height limit. It already leaves room for the planned keyboard,
/// so showing the keyboard only moves the sheet (its margin follows the
/// keyboard natively) instead of resizing its panel, scroll area and
/// actions on every frame of the keyboard's motion. Only a keyboard taller
/// than planned (a larger input method) still shrinks it.
fn sheet_height(planned: Option<f32>) -> f32 {
    let window = window().height.0;
    let top = window * 0.92;
    let planned = planned.unwrap_or(window * KEYBOARD_GUESS);
    let keyboard = keyboard_height().0;
    let live = if keyboard > 0.0 {
        top - keyboard - KEYBOARD_GAP
    } else {
        top
    };
    (top - planned - KEYBOARD_GAP).min(live).max(140.0)
}

fn shell(
    open: impl Fn() -> bool + 'static,
    close: impl Fn(OpenChangeReason) + 'static,
    content: impl IntoElement,
) -> impl IntoElement {
    let lifecycle = use_context::<Lifecycle>();
    let live_keyboard = use_context::<ConversationKeyboard>().is_some();
    let opened = lifecycle.as_ref().map(|l| l.opened);
    let planned = untracked(planned_keyboard);
    let height = height_budget(planned);
    sheet()
        .open(move || Some(open()))
        .on_open(move |_: &()| {
            if let Some(opened) = opened {
                opened.set(true);
            }
        })
        .on_close(move |_: &()| {
            if let Some(lifecycle) = &lifecycle {
                lifecycle.opened.set(false);
                (lifecycle.closed)();
            }
        })
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(false, reason) = event {
                if live_keyboard && *reason == OpenChangeReason::Cancel && keyboard_height().0 > 0.0
                {
                    dismiss_keyboard();
                } else {
                    close(*reason);
                }
            }
        })
        .close_on_swipe(true)
        .backdrop_style(|s| s.bg(color::SCRIM.opacity(0.32)))
        .popup_style(|s| {
            material::glass(s, Glass::Sheet)
                .rounded_t(px(radius::SHEET))
                .border_curve(BorderCurve::Continuous)
                // The whole panel rides above the keyboard (a native env()
                // term); its size does not change while the keyboard moves.
                .mb_keyboard()
        })
        .child(
            view()
                .test_id("task-sheet")
                .max_h(move || px(height()))
                .child(
                    view()
                        .w(px(36.0))
                        .h(px(5.0))
                        .mt_2()
                        .mb_1()
                        .self_center()
                        .rounded_full()
                        .bg(color::LINE_STRONG)
                        .accessibility_elements_hidden(true),
                )
                .child(content),
        )
}
