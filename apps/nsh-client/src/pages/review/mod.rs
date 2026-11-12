//! Reviewing a meal before it is kept: the photo, the model's estimate as
//! editable foods, the meal's slot and total, and Save. A new meal can also
//! start without a photo; a saved meal opens here to be corrected or
//! deleted (with Undo on Today).

mod consent;
mod draft;
mod food_editor;
mod foods;
mod photo;

pub use foods::failure_copy;

use std::{rc::Rc, time::Duration};

use nsh_base::{alert_dialog, nav_page};
use nsh_core::{element::Screen, prelude::*};

use self::{
    consent::consent_sheet,
    draft::{Draft, Editing, Phase, Photo},
    food_editor::food_editor,
};
use super::{
    parts::{bottom_bar, bottom_clearance, status_bar, top_bar},
    today::slot_name,
};
use crate::{
    data::{clock, meals, photos},
    domain::meal::{Day, MealSlot},
    i18n::s,
    nav,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, color, icon,
        segmented::{Segment, segmented},
        sheet::bottom_sheet,
        space,
        toast::show_toast,
    },
};

/// A new meal on `day`, from the picked photo `capture` or by hand.
pub fn new_meal_page(day: Day, capture: Option<u64>) -> Screen {
    let draft = Draft::new(day);
    match capture {
        Some(capture) => draft.prepare(capture),
        None => {
            // Straight to the first food, once the page has slid in.
            set_timeout(Duration::from_millis(380), move || {
                draft.editing.set(Some(Editing::New));
            });
        }
    }
    page(draft)
}

/// The saved meal `id`, to correct or delete.
pub fn edit_meal_page(id: &str) -> Screen {
    let draft = match untracked(|| meals::get(id)) {
        Some(meal) => Draft::editing_meal(&meal),
        None => Draft::new(untracked(clock::today)),
    };
    if let Some(name) = draft.kept_photo() {
        spawn(photos::load(vec![name.clone()]));
        effect(move || {
            if let Some(uri) = photos::uri(&name)
                && draft.photo.with_untracked(Option::is_none)
            {
                draft.photo.set(Some(Photo {
                    uri,
                    upload: None,
                    keep: None,
                }));
            }
        });
    }
    page(draft)
}

fn page(draft: Draft) -> Screen {
    provide_context(draft);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if crate::preview::wants_editor() {
        let opened = stored(false);
        effect(move || {
            let first = draft.foods.with(|foods| foods.first().map(|food| food.id));
            if draft.phase.get() == Phase::Ready
                && let Some(id) = first
                && !opened.replace(true)
            {
                set_timeout(Duration::from_millis(500), move || {
                    draft.editing.set(Some(Editing::Food(id)));
                });
            }
        });
    }
    let back = move || request_back(draft);
    nav_page()
        .title(move || SharedString::from(title(draft)))
        .header_visible(false)
        .status_bar(status_bar)
        .pop_on_back(move || !draft.has_unsaved_work())
        .on_back_press(back)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(
                    move || title(draft).into(),
                    back,
                    draft.is_saved_meal().then(|| {
                        IconBtn::new(Icon::Trash, || s().delete_meal.into())
                            .on_press(move || delete(draft))
                            .mr_1()
                            .into_element()
                    }),
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_2()
                            .pb(move || px(bottom_clearance()))
                            .gap_5()
                            .child(photo::photo_card(draft))
                            .child(status_line(draft))
                            .child(segmented(
                                MealSlot::ALL
                                    .into_iter()
                                    .map(|slot| {
                                        Segment::new(slot, move || slot_name(s(), slot).into())
                                    })
                                    .collect(),
                                move || draft.slot.get(),
                                move |slot| {
                                    draft.slot.set(slot);
                                    draft.dirty.set(true);
                                },
                            ))
                            .child(foods::foods_section(draft)),
                    ),
                )
                .child(bottom_bar(
                    Btn::primary()
                        .size(Size::Large)
                        .icon(Icon::Check)
                        .label(|| s().save_meal.into())
                        .disabled(move || !draft.can_save())
                        .on_press(move || draft.save()),
                ))
                .child(bottom_sheet(
                    move || draft.consent_open.get(),
                    move || draft.consent_declined(),
                    consent_sheet(),
                ))
                .child(bottom_sheet(
                    move || draft.editing.with(Option::is_some),
                    move || draft.editing.set(None),
                    food_editor(),
                )),
        )
}

fn title(draft: Draft) -> &'static str {
    if draft.is_saved_meal() {
        s().edit_meal
    } else {
        s().new_meal
    }
}

/// Where the photo went while analyzing; that the foods are an estimate
/// once they arrive.
fn status_line(draft: Draft) -> impl IntoElement {
    let content = move || match draft.phase.get() {
        Phase::Analyzing => draft
            .sent_to
            .get()
            .map(|(host, model)| (Icon::Lock, s().sent_to(&host, &model))),
        Phase::Ready if draft.model.with(Option::is_some) && !draft.is_saved_meal() => {
            Some((Icon::Sparkle, s().estimate_hint.to_owned()))
        }
        _ => None,
    };
    when(
        move || content().is_some(),
        move || {
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .mt(px(-8.0))
                .px_1()
                .child(dynamic(move || {
                    let glyph = content().map(|(glyph, _)| glyph).unwrap_or(Icon::Lock);
                    untracked(|| icon(glyph, 16.0, color::MUTED))
                }))
                .child(
                    text(move || content().map(|(_, line)| line).unwrap_or_default())
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .number_of_lines(2)
                        .flex_shrink(1.0),
                )
        },
    )
}

/// Back: straight away when nothing would be lost, else after asking.
fn request_back(draft: Draft) {
    if !untracked(|| draft.has_unsaved_work()) {
        nav::pop();
        return;
    }
    let answer = alert_dialog()
        .title(s().discard_title)
        .description(s().discard_body)
        .cancel("keep", s().keep_editing)
        .destructive("discard", s().discard)
        .show();
    spawn(async move {
        if answer
            .await
            .is_ok_and(|answer| answer.action.as_deref() == Some("discard"))
        {
            draft.dirty.set(false);
            nav::pop();
        }
    });
}

/// Deletes the saved meal, closes the page and offers Undo on Today.
fn delete(draft: Draft) {
    let Some(id) = draft.meal_id.with(|id| id.clone()) else {
        return;
    };
    let Some(meal) = meals::remove(&id) else {
        return;
    };
    draft.dirty.set(false);
    nav::pop();
    let restored = meal.clone();
    show_toast(
        s().meal_deleted,
        Some((
            s().undo.into(),
            Rc::new(move || meals::restore(restored.clone())),
        )),
    );
}
