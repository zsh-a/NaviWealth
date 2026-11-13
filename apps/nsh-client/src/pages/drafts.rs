//! Recognition drafts as cards edged in the AI's light, pinned on Today
//! and atop Records: being read (a shimmer), ready to confirm, or needing
//! the owner (no food found, failed). Pressing one opens it.

use nsh_core::prelude::*;

use super::today::slot_name;
use crate::{
    data::{pending, photos},
    domain::pending::{PendingMeal, PendingStatus},
    i18n::s,
    nav::{self, Route},
    ui::{
        Icon, Lift, Type, Typo, color,
        feedback::{appear, shimmer, skeleton},
        icon, motion, radius,
        theme::shadow,
    },
};

const THUMB: f32 = 52.0;

/// The drafts, newest first, with a heading when `heading` (Records).
pub fn drafts_section(heading: bool) -> impl IntoElement {
    let list = computed(pending::all);
    effect(move || {
        let names: Vec<String> = list.with(|l| l.iter().map(|p| p.photo.clone()).collect());
        if !names.is_empty() {
            spawn(photos::load(names));
        }
    });
    when(
        move || list.with(|l| !l.is_empty()),
        move || {
            view()
                .gap(px(10.0))
                .child(heading.then(|| {
                    view()
                        .flex_row()
                        .items_baseline()
                        .justify_between()
                        .px(px(4.0))
                        .child(
                            text(|| s().to_confirm)
                                .typo(Type::Headline)
                                .text_color(color::INK)
                                .role(AccessibilityRole::Header),
                        )
                        .child(
                            text(move || list.with(Vec::len).to_string())
                                .typo(Type::Subhead)
                                .tabular_nums()
                                .text_color(color::MUTED),
                        )
                }))
                .child(each(
                    move || list.get(),
                    |p: &PendingMeal| p.id.clone(),
                    |p, index| {
                        appear(
                            index.get_untracked() as u32,
                            dynamic(move || {
                                let p = p.get();
                                untracked(move || card(p))
                            }),
                        )
                    },
                ))
        },
    )
}

fn card(draft: PendingMeal) -> impl IntoElement {
    let id = draft.id.clone();
    let slot = slot_name(s(), draft.slot);
    let headline = s().draft_headline(slot, draft.status);
    let detail = match draft.status {
        PendingStatus::Analyzing => None,
        PendingStatus::Ready => Some(s().draft_detail(draft.foods.len(), draft.kcal())),
        PendingStatus::NoFood => Some(s().draft_add.to_owned()),
        PendingStatus::Failed => Some(s().draft_retry.to_owned()),
    };
    let analyzing = draft.status == PendingStatus::Analyzing;
    let scale = animated_value(1.0);
    // The AI's light as a 1.5 pt edge: a gradient behind an inset surface.
    view()
        .role(AccessibilityRole::Button)
        .label(SharedString::from(match &detail {
            Some(detail) => format!("{headline}, {detail}"),
            None => headline.clone(),
        }))
        .on_press_down(move || {
            if !reduce_motion() {
                scale.spring(motion::PRESS_SCALE_CARD, motion::PRESS);
            }
        })
        .on_press_up(move || {
            scale.spring(1.0, motion::PRESS);
        })
        .on_press(move || nav::push(Route::Pending(id.clone())))
        .bind_scale(&scale)
        .p(px(1.5))
        .rounded(px(radius::CARD))
        .bg_linear_to_br()
        .gradient_from(color::AI_FROM)
        .gradient_to(color::AI_TO)
        .lift(&shadow::CARD)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap(px(14.0))
                .p(px(10.5))
                .pr(px(14.0))
                .rounded(px(radius::CARD - 1.5))
                .bg(color::SURFACE)
                .child(thumbnail(draft.photo.clone()))
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap(px(5.0))
                        .child(
                            text(headline)
                                .typo(if analyzing {
                                    Type::Subhead
                                } else {
                                    Type::Headline
                                })
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(if analyzing {
                                    color::AI_FROM
                                } else {
                                    color::INK
                                })
                                .number_of_lines(1),
                        )
                        .child(match detail {
                            Some(detail) => text(detail)
                                .typo(Type::Subhead)
                                .tabular_nums()
                                .text_color(color::MUTED)
                                .number_of_lines(1)
                                .into_element(),
                            None => {
                                let sweep = shimmer();
                                view()
                                    .gap(px(6.0))
                                    .child(skeleton(Some(150.0), 8.0, sweep))
                                    .child(skeleton(Some(90.0), 8.0, sweep))
                                    .into_element()
                            }
                        }),
                )
                .child(trailing(draft.status)),
        )
}

fn trailing(status: PendingStatus) -> AnyElement {
    match status {
        PendingStatus::Ready => view()
            .h(px(36.0))
            .px_4()
            .rounded_full()
            .justify_center()
            .bg(color::ACTION)
            .child(
                text(|| s().confirm)
                    .typo(Type::Subhead)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(color::ON_ACTION),
            )
            .into_element(),
        PendingStatus::Analyzing => icon(Icon::Sparkle, 22.0, color::AI_FROM).into_element(),
        PendingStatus::NoFood | PendingStatus::Failed => {
            icon(Icon::ChevronRight, 18.0, color::FAINT).into_element()
        }
    }
}

fn thumbnail(name: String) -> impl IntoElement {
    let uri = move || photos::uri(&name);
    view()
        .size(px(THUMB))
        .rounded(px(radius::THUMB))
        .overflow_hidden()
        .bg(color::SURFACE_2)
        .child(dynamic(move || match uri() {
            Some(uri) => untracked(|| {
                image(uri)
                    .object_fit(ResizeMode::Cover)
                    .size(px(THUMB))
                    .accessibility_elements_hidden(true)
                    .into_element()
            }),
            None => view().into_element(),
        }))
}
