//! One transient message, shared by the page and its active modal surface.
//! The long-lived host advances NSH's manager, so moving Undo into a sheet
//! does not restart its lifetime.

use std::{rc::Rc, time::Duration};

use nsh_base::{
    Anchor, ToastManager, ToastMotion, ToastOptions, ToastTransitionStatus, button, toast,
    toast_stack,
};
use nsh_core::{
    prelude::*,
    time::{Instant, now},
};

use super::{
    Lift, Typo,
    theme::{Type, color, motion, shadow},
};

/// How long a message stays, including its entrance.
pub const SHOWN_FOR: Duration = Duration::from_millis(4500);
const EXIT_FOR: Duration = Duration::from_millis(220);

type Action = (SharedString, Rc<dyn Fn()>);

#[derive(Clone)]
struct Message {
    text: SharedString,
    action: Option<Action>,
    view: Option<Action>,
    shown_at: Instant,
    motion: ToastMotion,
}

#[derive(Clone)]
struct State {
    manager: ToastManager<u64, Message>,
    next: u64,
    hide_view: bool,
}

impl Default for State {
    fn default() -> Self {
        Self {
            manager: ToastManager::new(toast_motion()),
            next: 0,
            hide_view: false,
        }
    }
}

fn toast_motion() -> ToastMotion {
    ToastMotion {
        duration: if reduce_motion() {
            Duration::ZERO
        } else {
            Duration::from_millis(motion::SLOW as u64)
        },
        exit_duration: if reduce_motion() {
            Duration::ZERO
        } else {
            EXIT_FOR
        },
        ..ToastMotion::default()
    }
}

fn state() -> Signal<State> {
    global::<State>()
}

/// Shows `text`, with an optional action.
pub fn show_toast(text: impl Into<SharedString>, action: Option<Action>) {
    show(text, action, None);
}

/// Capture offers Undo and a shortcut to the saved records. Starting another
/// draft retires the navigation shortcut while preserving the Undo action.
pub fn show_capture_receipt(text: impl Into<SharedString>, undo: Action, view: Action) {
    show(text, Some(undo), Some(view));
}

fn show(text: impl Into<SharedString>, action: Option<Action>, view: Option<Action>) {
    let text = text.into();
    // The home surface remains mounted while a modal mirrors the toast. Announce
    // on creation, rather than on each Toast mount, to read this message once.
    announce_for_accessibility(text.to_string());
    state().update(|s| {
        let motion = toast_motion();
        let shown_at = now();
        s.next += 1;
        s.hide_view = false;
        s.manager = ToastManager::new(motion);
        s.manager.push(
            s.next,
            Message {
                text,
                action,
                view,
                shown_at,
                motion,
            },
            ToastOptions::timeout(Some(SHOWN_FOR.saturating_sub(motion.duration))),
            shown_at,
        );
        // Reduced motion has no starting phase to wait for.
        s.manager.advance(shown_at, false);
    });
}

/// Opening a new task clears a notice and a receipt's View shortcut; Undo
/// keeps the manager's existing deadline, including while drawn in a sheet.
pub fn clear_notice() {
    state().update(|s| {
        s.hide_view = true;
        if s.manager
            .iter()
            .next()
            .is_some_and(|(_, m, _)| m.action.is_none())
        {
            s.manager = ToastManager::new(toast_motion());
        }
    });
}

/// Place once on the long-lived page, above its bottom edge.
pub fn toast_host(bottom: impl Fn() -> f32 + 'static) -> impl IntoElement {
    let active = computed(|| state().with(|s| s.manager.iter().next().map(|(id, _, _)| *id)));
    effect(move || {
        if let Some(id) = active.get() {
            let message = state()
                .with_untracked(|s| s.manager.get(&id).cloned())
                .unwrap();
            // Advance at the manager's phase boundaries, even after suspension.
            // Polling at `now` would discard elapsed time beyond Starting in
            // NSH 0.7.1 and extend Undo when the app resumes after its deadline.
            // Only this host schedules work; modal mounts never restart it.
            spawn(async move {
                for elapsed in [
                    message.motion.duration,
                    SHOWN_FOR,
                    SHOWN_FOR + message.motion.exit_duration,
                ] {
                    let deadline = message.shown_at + elapsed;
                    timer_until(deadline).await;
                    state().update(|s| {
                        if s.manager.get(&id).is_some() {
                            s.manager.advance(deadline, false);
                        }
                    });
                }
            });
        }
    });
    toast_view(bottom)
}

#[derive(Clone, PartialEq)]
struct Visible {
    id: u64,
    text: SharedString,
    action: Option<SharedString>,
    view: Option<SharedString>,
    status: ToastTransitionStatus,
}

/// Mirrors the manager into a modal; it never owns a lifetime timer.
pub fn toast_view(bottom: impl Fn() -> f32 + 'static) -> impl IntoElement {
    let shown = computed(|| {
        state().with(|s| {
            s.manager
                .iter()
                .map(|(id, m, status)| Visible {
                    id: *id,
                    text: m.text.clone(),
                    action: m.action.as_ref().map(|(label, _)| label.clone()),
                    view: if s.hide_view {
                        None
                    } else {
                        m.view.as_ref().map(|(label, _)| label.clone())
                    },
                    status,
                })
                .collect::<Vec<_>>()
        })
    });
    view()
        .absolute()
        .left_0()
        .right_0()
        .bottom(move || px(bottom()))
        .items_center()
        .px_4()
        .pointer_events(PointerEvents::BoxNone)
        .child(
            toast_stack()
                .placement(Anchor::BottomCenter)
                .motion(toast_motion())
                .close_on_escape(false)
                .w_full()
                .pointer_events(PointerEvents::BoxNone)
                .child(each(
                    shown,
                    |message: &Visible| message.id,
                    |message, _| {
                        view()
                            .items_center()
                            .pointer_events(PointerEvents::BoxNone)
                            .child(bubble(message))
                    },
                )),
        )
}

fn bubble(message: ReadSignal<Visible>) -> impl IntoElement {
    let initial = message.get_untracked();
    let id = initial.id;
    toast()
        .transition_status(move || message.get().status)
        .swipe_direction(None)
        .transition_all()
        .duration(move || {
            if reduce_motion() {
                0.0
            } else if message.get().status == ToastTransitionStatus::Ending {
                motion::FAST
            } else {
                motion::SLOW
            }
        })
        .ease_out()
        .starting_class("opacity-0 translate-y-4")
        .ending_class("opacity-0 translate-y-4 ease-in")
        .flex_row()
        .items_center()
        .gap_3()
        .max_w(relative(1.0))
        .py_2()
        .pl_5()
        .pr(px(if initial.action.is_some() { 8.0 } else { 20.0 }))
        .min_h(px(52.0))
        .rounded_full()
        .bg(color::INK)
        .lift(&shadow::FLOAT)
        .child(
            text(initial.text)
                .typo(Type::Callout)
                .text_color(color::CANVAS)
                .min_w(px(0.0))
                .flex_shrink(1.0),
        )
        .child(when(
            move || message.get().view.is_some(),
            move || action_button(id, message.get_untracked().view.unwrap_or_default(), true),
        ))
        .child(initial.action.map(|label| action_button(id, label, false)))
}

fn action_button(id: u64, label: SharedString, view: bool) -> impl IntoElement {
    button()
        .flex_shrink_0()
        .on_press(move || {
            let run = state().with_untracked(|s| {
                let message = s.manager.get(&id)?;
                if view {
                    (!s.hide_view).then_some(message.view.as_ref()).flatten()
                } else {
                    message.action.as_ref()
                }
                .map(|(_, run)| run.clone())
            });
            // Clear before calling: an action can show a new retry message.
            if run.is_some() {
                state().update(|s| s.manager = ToastManager::new(toast_motion()));
            }
            if let Some(run) = run {
                run();
            }
        })
        .px_2()
        .min_h(px(40.0))
        .justify_center()
        .rounded_full()
        .hit_slop(EdgeInsets::all(px(4.0)))
        .active(|s| s.opacity(0.6))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ON_ACTION))
        .child(
            text(label)
                .typo(Type::Headline)
                .text_color(color::ON_ACTION),
        )
}

#[cfg(test)]
mod tests;
