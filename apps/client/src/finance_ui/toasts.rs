//! One hosted official ToastStack; existing feedback signals feed its lifecycle.
use super::*;
use nsh_base::{
    Anchor, ToastManager, ToastMotion, ToastOptions, ToastStackState, ToastTransitionStatus, toast,
    toast_stack,
};
use nsh_core::time::now;
use std::time::Duration;
#[derive(Clone, PartialEq)]
struct Notice {
    message: String,
    status: ToastTransitionStatus,
}
pub fn feedback_overlay(bottom: f32) -> AnyElement {
    let source = use_context::<Feedback>()
        .map(|f| f.0)
        .unwrap_or_else(|| signal(String::new()));
    let undo = use_context::<UndoOffer>();
    let nav = use_context::<Navigation>();
    let mut motion = ToastMotion::sonner();
    motion.duration = Duration::from_millis(200);
    motion.exit_duration = Duration::from_millis(160);
    let manager = stored(ToastManager::<u64, String>::new(motion));
    let entries = signal(Vec::<Notice>::new());
    let stack = ToastStackState::new();
    let sync = move || {
        entries.set(manager.with(|m| {
            m.visible(1)
                .map(|(_, message, status)| Notice {
                    message: message.clone(),
                    status,
                })
                .collect()
        }))
    };
    effect(move || {
        let message = source.get();
        manager.with(|m| {
            if message.is_empty() {
                m.dismiss(&0, now());
            } else {
                m.push(
                    0,
                    message,
                    ToastOptions::timeout(Some(Duration::from_secs(8))),
                    now(),
                );
            }
        });
        sync();
    });
    set_interval(Duration::from_millis(50), move || {
        let result = manager.with(|m| m.advance(now(), stack.is_expanded()));
        if result
            .removed
            .iter()
            .any(|(_, s)| *s == source.get_untracked())
        {
            source.set(String::new());
        }
        if result.changed {
            sync();
        }
    });
    view()
        .absolute()
        .left_4()
        .right_4()
        .bottom(move || {
            px(safe_area().bottom.0
                + bottom
                + if nav.is_some_and(|n| n.0.get().is_empty()) {
                    ui::token("tab-height")
                } else {
                    0.0
                })
        })
        .child(when(
            move || !undo.is_some_and(|u| u.pending.get().is_some()),
            move || {
                toast_stack()
                    .placement(Anchor::BottomCenter)
                    .motion(motion)
                    .state(stack)
                    .w_full()
                    .on_cancel(move || source.set(String::new()))
                    .child(each(
                        move || entries.get(),
                        |_: &Notice| 0_u64,
                        move |entry: ReadSignal<Notice>, _| {
                            ui::NativeControl(
                                toast()
                                    .transition_status(move || entry.get().status)
                                    .accessibility_label(move || {
                                        Some(SharedString::from(entry.get().message))
                                    })
                                    .on_dismiss_request(move || source.set(String::new()))
                                    .starting_class("opacity-0 translate-y-2")
                                    .ending_class("opacity-0 translate-y-2 pointer-events-none")
                                    .transition_all()
                                    .duration(if reduce_motion() { 0.0 } else { 200.0 }),
                            )
                            .test_id("finance-feedback")
                            .flex_row()
                            .items_center()
                            .gap_2()
                            .px_4()
                            .py_2()
                            .rounded_lg()
                            .border_1()
                            .border_color(move || theme().border)
                            .bg(move || theme().popover)
                            .shadow_md()
                            .child(
                                text(move || entry.get().message)
                                    .text_sm()
                                    .text_color(move || theme().popover_foreground)
                                    .flex_1(),
                            )
                            .child(ui::icon_button(
                                ui::Icon::Close,
                                "收起反馈",
                                "finance-notice-dismiss",
                                move || source.set(String::new()),
                            ))
                        },
                    ))
            },
        ))
        .into_element()
}
