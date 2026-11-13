//! Favorites in the capture sheet: meals the owner eats often, as a row of
//! photo tiles. A tap logs one today at once (with Undo on Today); holding
//! one offers to adjust it before logging, or to remove it.

use std::rc::Rc;

use nsh_base::alert_dialog;
use nsh_core::{Haptic, HapticImpact, HapticNotification, prelude::*};

use crate::{
    data::{clock, favorites, meals, photos},
    domain::{favorite::Favorite, format},
    i18n::s,
    nav::{self, Route},
    ui::{Icon, Type, Typo, color, icon, motion, radius, space, toast::show_toast},
};

/// A tile's width and its photo's height.
const TILE: f32 = 132.0;
const PHOTO: f32 = 96.0;

/// The favorites section, while there are any; `close` closes the sheet.
pub fn favorites_row(close: impl Fn() + Copy + 'static) -> impl IntoElement {
    when(favorites::any, move || {
        view()
            .gap_3()
            .child(
                view()
                    .flex_row()
                    .items_baseline()
                    .justify_between()
                    .gap_3()
                    .px(px(2.0))
                    .child(
                        text(|| s().favorites)
                            .typo(Type::Headline)
                            .text_color(color::INK)
                            .role(AccessibilityRole::Header),
                    )
                    .child(
                        text(|| s().favorites_hint())
                            .typo(Type::Caption)
                            .text_color(color::MUTED)
                            .number_of_lines(1)
                            .flex_shrink(1.0),
                    ),
            )
            .child(dynamic(move || {
                let list = favorites::all();
                untracked(move || {
                    spawn(photos::load(
                        list.iter().filter_map(|f| f.photo.clone()).collect(),
                    ));
                    scroll()
                        .horizontal()
                        .scrollbar(false)
                        .test_id("favorites")
                        .mx(px(-space::GUTTER))
                        .child(
                            view()
                                .flex_row()
                                .gap(px(10.0))
                                .px(px(space::GUTTER))
                                .children(list.into_iter().map(move |f| tile(f, close))),
                        )
                })
            }))
    })
}

fn tile(favorite: Favorite, close: impl Fn() + Copy + 'static) -> impl IntoElement {
    let id = favorite.id.clone();
    let held = favorite.id.clone();
    let name = favorite.name();
    let kcal = format!("{} {}", format::kcal(favorite.total().kcal), s().kcal);
    let label = format!("{name}, {kcal}");
    // Pressable and holdable (buttons take presses only): it sinks a little
    // under the finger.
    let scale = animated_value(1.0);
    view()
        .role(AccessibilityRole::Button)
        .label(SharedString::from(label))
        .on_press_down(move || {
            if !reduce_motion() {
                scale.spring(motion::PRESS_SCALE_CARD, motion::PRESS);
            }
        })
        .on_press_up(move || {
            scale.spring(1.0, motion::PRESS);
        })
        .on_press(move || {
            close();
            log(&id);
        })
        .on_long_press(move || {
            haptic(Haptic::Impact(HapticImpact::Medium));
            actions(held.clone(), close);
        })
        .bind_scale(&scale)
        .w(px(TILE))
        .gap(px(8.0))
        .child(photo(favorite.photo.clone()))
        .child(
            view()
                .px(px(2.0))
                .gap(px(1.0))
                .child(
                    text(name)
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(color::INK)
                        .number_of_lines(1),
                )
                .child(
                    text(kcal)
                        .typo(Type::Caption)
                        .tabular_nums()
                        .text_color(color::MUTED),
                ),
        )
}

fn photo(name: Option<String>) -> impl IntoElement {
    let name = stored(name);
    let uri = move || name.with(|n| n.as_deref().and_then(photos::uri));
    view()
        .w(px(TILE))
        .h(px(PHOTO))
        .rounded(px(radius::WELL))
        .overflow_hidden()
        .bg(color::SURFACE_2)
        .items_center()
        .justify_center()
        .child(
            when(
                move || uri().is_some(),
                move || {
                    image(move || uri().unwrap_or_default())
                        .object_fit(ResizeMode::Cover)
                        .w(px(TILE))
                        .h(px(PHOTO))
                        .accessibility_elements_hidden(true)
                },
            )
            .otherwise(|| icon(Icon::Utensils, 28.0, color::FAINT)),
        )
}

/// Logs the favorite `id` today, with Undo.
fn log(id: &str) {
    let Some(meal) = favorites::log(id, clock::today()) else {
        return;
    };
    haptic(Haptic::Notification(HapticNotification::Success));
    let name = favorites::get(id)
        .map(|favorite| favorite.name())
        .unwrap_or_default();
    let logged = meal.id.clone();
    nav::select(nav::Tab::Today);
    show_toast(
        s().logged(&name),
        Some((
            s().undo.into(),
            Rc::new(move || {
                meals::remove(&logged);
            }),
        )),
    );
}

/// Holding a tile: adjust before logging, or remove it (with Undo).
fn actions(id: String, close: impl Fn() + Copy + 'static) {
    let Some(favorite) = favorites::get(&id) else {
        return;
    };
    let answer = alert_dialog()
        .title(favorite.name())
        .action("adjust", s().adjust_then_log)
        .destructive("remove", s().remove_favorite)
        .cancel("cancel", s().cancel)
        .action_sheet()
        .show();
    spawn(async move {
        let Ok(answer) = answer.await else {
            return;
        };
        match answer.action.as_deref() {
            Some("adjust") => {
                close();
                nav::push(Route::FromFavorite {
                    day: clock::today(),
                    id: id.clone(),
                });
            }
            Some("remove") => {
                let Some(removed) = favorites::remove(&id) else {
                    return;
                };
                // The toast and its Undo show under the sheet otherwise.
                close();
                show_toast(
                    s().favorite_removed,
                    Some((
                        s().undo.into(),
                        Rc::new(move || favorites::restore(removed.clone())),
                    )),
                );
            }
            _ => {}
        }
    });
}
