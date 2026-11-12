//! A transient message with an optional action (Undo) at the bottom of the
//! page that hosts it. One at a time: a newer message replaces the older.
//! [`show_toast`] works from any listener, even on a page that is closing;
//! the host owns the timer that dismisses it.

use std::{cell::RefCell, rc::Rc, time::Duration};

use nsh_base::button;
use nsh_core::prelude::*;

use super::{
    Typo,
    theme::{Type, color, motion, radius},
};

/// How long a message stays.
pub const SHOWN_FOR: Duration = Duration::from_millis(4500);

#[derive(Clone, Default, PartialEq)]
struct Message {
    id: u64,
    text: SharedString,
    action: Option<SharedString>,
}

#[derive(Clone, Default, PartialEq)]
struct State {
    current: Option<Message>,
    next: u64,
}

thread_local! {
    static ACTION: RefCell<Option<Rc<dyn Fn()>>> = const { RefCell::new(None) };
}

fn state() -> Signal<State> {
    global::<State>()
}

/// Shows `text`, with an action labelled `label` running `run` when given.
pub fn show_toast(text: impl Into<SharedString>, action: Option<(SharedString, Rc<dyn Fn()>)>) {
    let text = text.into();
    let (label, run) = match action {
        Some((label, run)) => (Some(label), Some(run)),
        None => (None, None),
    };
    ACTION.with(|slot| *slot.borrow_mut() = run);
    announce_for_accessibility(text.to_string());
    state().update(|state| {
        state.next += 1;
        state.current = Some(Message {
            id: state.next,
            text,
            action: label,
        });
    });
}

fn dismiss(id: u64) {
    if state().with_untracked(|s| s.current.as_ref().is_some_and(|m| m.id == id)) {
        ACTION.with(|slot| slot.borrow_mut().take());
        state().update(|state| state.current = None);
    }
}

/// The host: place it once over the bottom of a long-lived page, `bottom`
/// points above that page's bottom edge.
pub fn toast_host(bottom: impl Fn() -> f32 + 'static) -> impl IntoElement {
    // Each new message restarts the timer; the effect's rerun cancels the
    // last one.
    effect(move || {
        if let Some(id) = state().with(|s| s.current.as_ref().map(|m| m.id)) {
            spawn(async move {
                timer(SHOWN_FOR).await;
                dismiss(id);
            });
        }
    });
    view()
        .absolute()
        .left_0()
        .right_0()
        .bottom(move || px(bottom()))
        .items_center()
        .pointer_events(PointerEvents::BoxNone)
        .child(each(
            move || state().with(|s| s.current.clone().into_iter().collect::<Vec<_>>()),
            |message: &Message| message.id,
            |message, _| bubble(message.get_untracked()),
        ))
}

fn bubble(message: Message) -> impl IntoElement {
    let still = reduce_motion();
    let shown = animated_value(if still { 1.0 } else { 0.0 });
    if !still {
        shown.timing(1.0, motion::SLOW, Easing::EaseOut);
    }
    let id = message.id;
    view()
        .bind_opacity(&shown)
        .bind_translate_y(&shown.interpolate(&[0.0, 1.0], &[16.0, 0.0]))
        .flex_row()
        .items_center()
        .gap_3()
        .mx_4()
        .pl_4()
        .pr(px(if message.action.is_some() { 6.0 } else { 16.0 }))
        .min_h(px(48.0))
        .rounded(px(radius::CONTROL))
        .bg(color::INK)
        .shadow_lg()
        .child(
            text(message.text.clone())
                .typo(Type::Callout)
                .text_color(color::CANVAS)
                .flex_shrink(1.0),
        )
        .child(message.action.map(|label| {
            button()
                .on_press(move || {
                    let run = ACTION.with(|slot| slot.borrow_mut().take());
                    dismiss(id);
                    if let Some(run) = run {
                        run();
                    }
                })
                .px_3()
                .min_h(px(36.0))
                .justify_center()
                .rounded(px(radius::SMALL))
                .hit_slop(EdgeInsets::all(px(6.0)))
                .active(|s| s.opacity(0.6))
                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
                .child(
                    text(label)
                        .typo(Type::Headline)
                        .text_color(color::ACCENT_SOFT),
                )
        }))
}
