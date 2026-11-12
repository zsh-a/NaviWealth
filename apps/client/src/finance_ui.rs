//! Finance workspace primitives. Business values stay exact; animation is presentation only.
use crate::{state::Services, ui};
use nsh_base::PickedDate;
use nsh_base::{DatePickerValue, SheetEvent, date_picker, theme};
use nsh_core::prelude::*;
use rust_decimal::{Decimal, prelude::ToPrimitive};
use std::{collections::BTreeMap, future::Future, pin::Pin, rc::Rc, sync::Arc};

#[derive(Clone, Copy)]
pub(crate) struct Navigation(pub Signal<Vec<String>>);
#[derive(Clone, Copy)]
pub(crate) struct Feedback(pub Signal<String>);

/// One acknowledged change: where its receipt lives, what it says, and the
/// record whose row should light up beside the message.
#[derive(Clone, PartialEq)]
pub struct Fact {
    pub path: String,
    pub message: String,
    pub record_id: Option<String>,
}
#[derive(Clone, Copy)]
pub(crate) struct ChangedFact(pub Signal<Option<Fact>>);

/// The quiet-workspace wash (theme.json custom role; soft as the fallback).
pub fn wash() -> AdaptiveColor {
    theme().color("wash").unwrap_or_else(|| theme().secondary)
}
pub fn warning() -> AdaptiveColor {
    theme()
        .color("warning")
        .unwrap_or_else(|| theme().destructive)
}
pub fn data_investment() -> AdaptiveColor {
    theme()
        .color("data-investment")
        .unwrap_or_else(|| theme().primary)
}

pub fn gain() -> AdaptiveColor {
    theme().color("up").unwrap_or_else(|| theme().foreground)
}
pub fn data_cash() -> AdaptiveColor {
    theme()
        .color("data-cash")
        .unwrap_or_else(|| theme().muted_foreground)
}

pub use crate::ui::page_px;

mod feedback;
pub use feedback::*;

#[derive(Clone, Copy)]
pub(crate) struct LeaveGuard(pub Signal<Option<GuardCallback>>);
#[derive(Clone)]
pub(crate) struct GuardCallback {
    pub check: Rc<dyn Fn() -> bool>,
}
impl PartialEq for GuardCallback {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.check, &other.check)
    }
}
fn request_back() {
    if let Some(guard) = use_context::<LeaveGuard>()
        && guard.0.get().is_some_and(|check| (check.check)())
    {
        return;
    }
    back();
}
fn notice_default(message: &str) {
    if use_context::<Feedback>().is_some_and(|f| f.0.get().is_empty()) {
        notice(message);
    }
}

pub fn services() -> Arc<Services> {
    use_context::<Arc<Services>>().expect("services")
}
pub fn navigate(path: impl Into<String>) {
    let path = path.into();
    clear_acknowledgement();
    dismiss_keyboard();
    if let Some(nav) = use_context::<Navigation>() {
        if let Some(index) = root_tab(&path)
            && let Some(tab) = use_context::<crate::ShellTab>()
        {
            tab.0.set(index);
            nav.0.set(Vec::new());
            return;
        }
        nav.0.update(|routes| {
            if let Some(index) = routes.iter().position(|route| route == &path) {
                routes.truncate(index + 1);
            } else {
                routes.push(path);
            }
        });
    }
}
fn root_tab(path: &str) -> Option<u8> {
    match path {
        "/today" => Some(0),
        "/activity" => Some(1),
        "/wealth" => Some(2),
        "/plan" => Some(3),
        _ => None,
    }
}
pub(crate) fn dismiss_route(path: &str) {
    if let Some(nav) = use_context::<Navigation>() {
        nav.0.update(|routes| {
            if routes.last().is_some_and(|current| current == path) {
                routes.pop();
            }
        });
    }
}
pub fn back() {
    dismiss_keyboard();
    if let Some(nav) = use_context::<Navigation>() {
        nav.0.update(|routes| {
            routes.pop();
        });
    }
}
pub fn refresh() {
    if let Some(v) = use_context::<crate::state::DataVersion>() {
        v.0.update(|v| *v += 1);
    }
}
pub fn notice(message: impl Into<String>) {
    if let Some(f) = use_context::<Feedback>() {
        f.0.set(message.into());
    }
}
pub fn feedback_overlay(bottom: f32) -> AnyElement {
    view()
        .absolute()
        .left_4()
        .right_4()
        .bottom(move || px(safe_area().bottom.0 + bottom))
        .child(feedback())
        .into_element()
}
fn feedback() -> AnyElement {
    let message = use_context::<Feedback>()
        .map(|v| v.0)
        .unwrap_or_else(|| signal(String::new()));
    let undo = use_context::<UndoOffer>();
    when(
        // While an undo offer is up it owns the bottom slot; the toast
        // returns once the window is gone (for example after undoing).
        move || !message.get().is_empty() && !undo.is_some_and(|u| u.pending.get().is_some()),
        move || {
            let offset = animated_value(0.0);
            if !reduce_motion() {
                offset.set(6.0);
                offset.spring(0.0, ui::settle_spring());
            }
            view()
                .flex_row()
                .items_center()
                .px_4()
                .py_2()
                .gap_2()
                .rounded(px(12.0))
                .bg(move || theme().primary)
                .bind_translate_y(&offset)
                .test_id("finance-feedback")
                .child(
                    text(move || message.get())
                        .text_size(move || px(crate::ui::token("type-section")))
                        .text_color(move || theme().primary_foreground)
                        .flex_1(),
                )
                .child(
                    view()
                        .role(AccessibilityRole::Button)
                        .label("收起反馈")
                        .test_id("finance-notice-dismiss")
                        .w(px(48.0))
                        .h(px(48.0))
                        .items_center()
                        .justify_center()
                        .on_press(move || message.set(String::new()))
                        .child(
                            ui::icon(ui::Icon::Close)
                                .text_color(move || theme().primary_foreground),
                        ),
                )
        },
    )
    .into_element()
}
pub fn finish(target: Option<String>, pop: bool) {
    let nav = use_context::<Navigation>();
    let version = use_context::<crate::state::DataVersion>();
    let root = target
        .as_deref()
        .and_then(root_tab)
        .zip(use_context::<crate::ShellTab>());
    if let Some((index, tab)) = root {
        tab.0.set(index);
    }
    if let Some(version) = version {
        version.0.update(|v| *v += 1);
    }
    if let Some(nav) = nav {
        nav.0.update(|routes| {
            if root.is_some() {
                routes.clear();
                return;
            }
            if pop {
                routes.pop();
            }
            if let Some(path) = target {
                if let Some(index) = routes.iter().position(|route| route == &path) {
                    routes.truncate(index + 1);
                } else {
                    routes.push(path);
                }
            }
        });
    }
}
fn friendly_error(error: String) -> String {
    error
        .strip_prefix("invalid data: ")
        .unwrap_or(&error)
        .to_owned()
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum PageKind {
    Root,
    Detail,
}
pub fn page(title: impl Into<String>, body: impl IntoElement) -> AnyElement {
    let title = title.into();
    let nav = use_context::<Navigation>();
    let root = use_context::<PageKind>() == Some(PageKind::Root);
    view()
        .flex_1()
        .bg(move || theme().background)
        .child(
            view()
                .style_when(
                    move || root && nav.is_none_or(|n| n.0.get().is_empty()),
                    |s| s.hidden(),
                )
                .flex_row()
                .items_center()
                .gap_2()
                .px(move || px(page_px()()))
                .min_h(px(52.0))
                .child(when(
                    move || nav.is_some_and(|v| !v.0.get().is_empty()),
                    || ui::icon_button(ui::Icon::Back, "返回", "finance-back", request_back),
                ))
                .child(
                    text(title)
                        .text_size(move || px(crate::ui::token("type-page")))
                        .font_weight(FontWeight::MEDIUM)
                        .flex_1(),
                ),
        )
        .child(
            ui::interactive_scroll().flex_1().child(
                view()
                    .px(move || px(page_px()()))
                    .pt_2()
                    .pb_safe_area_plus(px(48.0))
                    .gap(move || px(ui::token("space-group")))
                    .child(body),
            ),
        )
        .child(feedback_overlay(16.0))
        .into_element()
}
pub fn section(title: impl Into<String>, body: impl IntoElement) -> AnyElement {
    view()
        .gap_3()
        .pt_4()
        .child(
            text(title.into())
                .text_size(move || px(crate::ui::token("type-section")))
                .font_weight(FontWeight::SEMIBOLD),
        )
        .child(body)
        .into_element()
}
pub use crate::ui::{metric, row};

pub fn action(
    label: impl Into<String>,
    id: &'static str,
    on_press: impl Fn() + 'static,
) -> AnyElement {
    ui::text_button(label, id, on_press, false).into_element()
}

mod charts;
pub use charts::*;

mod forms;
pub use forms::*;

mod date;
pub use date::*;

#[cfg(test)]
#[path = "finance_ui/page_tests.rs"]
mod page_tests;
