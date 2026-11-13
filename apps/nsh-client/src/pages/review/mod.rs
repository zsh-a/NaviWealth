//! Reviewing a meal before it is kept: the photo, the model's estimate as
//! editable foods, the meal's slot and total, and Save. A new meal can also
//! start without a photo; a saved meal opens here to be corrected or
//! deleted (with Undo on Today).

mod consent;
mod day;
mod draft;
mod food_editor;
mod foods;
mod pending;
mod photo;

pub use foods::failure_copy;
pub use pending::pending_meal_page;

use std::{rc::Rc, time::Duration};

use nsh_base::{alert_dialog, nav_page};
use nsh_core::{
    Haptic, HapticNotification,
    element::{AnimatedValue, Screen},
    prelude::*,
};

use self::{
    consent::consent_sheet,
    day::{day_chip, day_sheet},
    draft::{Draft, Editing, Phase, Photo},
    food_editor::food_editor,
};
use super::{
    parts::{bottom_bar, bottom_clearance, status_bar},
    today::slot_name,
};
use crate::{
    data::{clock, favorites, meals, photos},
    domain::{
        format,
        meal::{Day, MealSlot},
        nutrition::total,
    },
    i18n::s,
    nav,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color, icon, motion, radius,
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

/// A new meal on `day` from the favorite `id`, to adjust before Save.
pub fn favorite_meal_page(day: Day, id: &str) -> Screen {
    let draft = match favorites::get(id) {
        Some(favorite) => Draft::from_favorite(&favorite, day),
        None => Draft::new(day),
    };
    show_kept_photo(draft);
    page(draft)
}

/// The saved meal `id`, to correct or delete.
pub fn edit_meal_page(id: &str) -> Screen {
    let draft = match untracked(|| meals::get(id)) {
        Some(meal) => Draft::editing_meal(&meal),
        None => Draft::new(untracked(clock::today)),
    };
    show_kept_photo(draft);
    page(draft)
}

/// Shows the draft's kept photo once it is loaded.
fn show_kept_photo(draft: Draft) {
    let Some(name) = draft.kept_photo() else {
        return;
    };
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

fn page(draft: Draft) -> Screen {
    provide_context(draft);
    draft.follow_pending();
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
    let scroll_y = animated_value(0.0);
    // Over the photo, the top bar frosts in (its buttons turning solid) once
    // the panel slides under it, and clears when the photo comes back: two
    // settled states, never one half-faded over the photo.
    let edge =
        move || photo::header_height(window().width.0) - photo::OVERLAP - (safe_area().top.0 + BAR);
    let immersive =
        move || draft.photo.with(Option::is_some) || draft.phase.get() == Phase::Preparing;
    let past_photo = signal(false);
    let frost = animated_value(0.0);
    effect(move || {
        let to = if past_photo.get() { 1.0 } else { 0.0 };
        if untracked(reduce_motion) {
            frost.set(to);
        } else {
            frost.timing(to, motion::FAST, motion::SETTLE);
        }
    });
    nav_page()
        .title(move || SharedString::from(title(draft)))
        .header_visible(false)
        .status_bar(move || {
            if immersive() && !past_photo.get() {
                StatusBarSetting::from(StatusBarStyle::Light)
            } else {
                status_bar()
            }
        })
        .pop_on_back(move || !draft.has_unsaved_work())
        .on_back_press(back)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(
                    scroll()
                        .flex_1()
                        .scroll_value(&scroll_y)
                        .on_scroll(move |event: &ScrollEvent| {
                            let past = event.offset.y.0 > untracked(edge);
                            if past != past_photo.get_untracked() {
                                past_photo.set(past);
                            }
                        })
                        .child(
                            view()
                                .child(
                                    when(immersive, move || photo::photo_header(draft, scroll_y))
                                        .otherwise(|| {
                                            view().h(move || px(safe_area().top.0 + 60.0))
                                        }),
                                )
                                .child(content(draft, immersive)),
                        ),
                )
                .child(chrome(draft, frost, past_photo, immersive, back))
                .child(bottom_bar(
                    Btn::primary()
                        .size(Size::Large)
                        .icon(Icon::Check)
                        .label(move || save_label(draft))
                        .disabled(move || !draft.can_save())
                        .on_press(move || draft.save()),
                ))
                .child(bottom_sheet(
                    move || draft.consent_open.get(),
                    move || draft.consent_declined(),
                    consent_sheet(),
                ))
                .child(bottom_sheet(
                    move || draft.choosing_day.get(),
                    move || draft.choosing_day.set(false),
                    day_sheet(draft),
                ))
                .child(bottom_sheet(
                    move || draft.editing.with(Option::is_some),
                    move || draft.editing.set(None),
                    food_editor(),
                )),
        )
}

/// The panel under the photo (rising over its bottom edge), or the page's
/// content under the top bar when there is no photo.
fn content(draft: Draft, immersive: impl Fn() -> bool + Copy + 'static) -> impl IntoElement {
    view()
        .mt(move || px(if immersive() { -photo::OVERLAP } else { 0.0 }))
        .rounded_t(px(radius::SHEET))
        .bg(color::CANVAS)
        .px(px(space::GUTTER))
        .pt(move || px(if immersive() { 22.0 } else { 6.0 }))
        .pb(move || px(bottom_clearance()))
        .gap_5()
        .child(status_line(draft))
        .child(day_chip(draft))
        .child(segmented(
            MealSlot::ALL
                .into_iter()
                .map(|slot| Segment::new(slot, move || slot_name(s(), slot).into()))
                .collect(),
            move || draft.slot.get(),
            move |slot| {
                draft.slot.set(slot);
                draft.dirty.set(true);
            },
        ))
        .child(foods::foods_section(draft))
}

/// The top bar's height under the status bar: its padding and buttons.
const BAR: f32 = 6.0 + 44.0 + 8.0;

/// The top bar: Back, the title, and for a saved meal Favorite and Delete. Over a photo its buttons are
/// frosted glass and its background is clear; past the photo it is the
/// frosted canvas with solid buttons, like the bar of a page without one.
fn chrome(
    draft: Draft,
    frost: AnimatedValue,
    past_photo: Signal<bool>,
    immersive: impl Fn() -> bool + Copy + 'static,
    back: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    dynamic(move || {
        let over_photo = immersive();
        let solid = !over_photo || past_photo.get();
        let saved = draft.is_saved_meal();
        let is_draft = draft.pending.get().is_some();
        let favorite = saved
            && draft
                .meal_id
                .with(|id| id.as_deref().and_then(favorites::of_meal))
                .is_some();
        untracked(move || {
            let variant = if solid {
                Variant::Secondary
            } else {
                Variant::Glass
            };
            let background = view()
                .absolute()
                .inset_0()
                // Opaque enough where there is no blur (Android before 12).
                .bg(color::CANVAS.opacity(0.94))
                .backdrop_blur(px(20.0))
                .border_b(px(0.75))
                .border_b_color(color::LINE);
            let heading = text(move || title(draft))
                .typo(Type::Headline)
                .text_color(color::INK)
                .number_of_lines(1)
                .text_center()
                .flex_1();
            let (background, heading) = if over_photo {
                (
                    background.bind_opacity(&frost),
                    heading.bind_opacity(&frost),
                )
            } else {
                (background, heading)
            };
            view()
                .absolute()
                .top_0()
                .left_0()
                .right_0()
                .flex_row()
                .items_center()
                .gap_2()
                .px_3()
                .pt_safe_area_plus(px(6.0))
                .pb_2()
                .child(background)
                .child(
                    IconBtn::new(Icon::ChevronLeft, || s().back.into())
                        .variant(variant)
                        .on_press(back),
                )
                // Balances the two buttons on the right, keeping the title centered.
                .child(saved.then(|| view().size(px(44.0))))
                .child(heading)
                .child(if saved {
                    let (glyph, label): (Icon, fn() -> SharedString) = if favorite {
                        (Icon::BookmarkFilled, || s().remove_favorite.into())
                    } else {
                        (Icon::Bookmark, || s().save_favorite.into())
                    };
                    view()
                        .flex_row()
                        .gap_2()
                        .child(
                            IconBtn::new(glyph, label)
                                .variant(variant)
                                .on_press(move || toggle_favorite(draft)),
                        )
                        .child(
                            IconBtn::new(Icon::Trash, || s().delete_meal.into())
                                .variant(variant)
                                .on_press(move || delete(draft)),
                        )
                        .into_element()
                } else if is_draft {
                    IconBtn::new(Icon::Trash, || s().discard_draft.into())
                        .variant(variant)
                        .on_press(move || pending::discard(draft))
                        .into_element()
                } else {
                    view().size(px(44.0)).into_element()
                })
        })
    })
}

/// Save, with what the meal adds up to.
fn save_label(draft: Draft) -> SharedString {
    let kcal = draft.foods.with(|foods| total(foods).kcal);
    if kcal > 0.0 {
        format!("{} · {} {}", s().save_meal, format::kcal(kcal), s().kcal).into()
    } else {
        s().save_meal.into()
    }
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
        // A photo sent from this page waits on Today as a draft: say so
        // (not when an existing draft is only looked at).
        let kept = draft.started_draft();
        nav::pop();
        if kept {
            show_toast(s().draft_kept, None);
        }
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

/// Keeps the meal as shown as a favorite, or removes the favorite saved
/// from it. The filled bookmark is the confirmation (toasts show on Today),
/// pressing it again undoes.
fn toggle_favorite(draft: Draft) {
    let Some(id) = draft.meal_id.with(|id| id.clone()) else {
        return;
    };
    if let Some(favorite) = untracked(|| favorites::of_meal(&id)) {
        if favorites::remove(&favorite.id).is_some() {
            haptic(Haptic::Selection);
            announce_for_accessibility(s().favorite_removed.to_owned());
        }
        return;
    }
    match draft.snapshot().as_ref().and_then(favorites::save_from) {
        Some(_) => {
            haptic(Haptic::Notification(HapticNotification::Success));
            announce_for_accessibility(s().favorite_saved.to_owned());
        }
        None => haptic(Haptic::Notification(HapticNotification::Error)),
    }
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
