//! The app shell: the home at the bottom of the navigation stack and the
//! pages the routes open over it. No page logic here.

use nsh_base::nav_stack;
use nsh_core::prelude::*;

use crate::{
    nav::{self, Route},
    pages::{
        edit_meal_page, favorite_meal_page, home_page, new_meal_page, pending_meal_page,
        settings_page,
    },
};

pub fn shell() -> impl IntoElement {
    nav_stack()
        .flex_1()
        .child(home_page().key("home"))
        .child(each(
            nav::open,
            |route: &Route| route.key(),
            |route, depth| {
                let page = match route.get_untracked() {
                    Route::NewMeal { day, capture } => new_meal_page(day, capture),
                    Route::EditMeal(id) => edit_meal_page(&id),
                    Route::Pending(id) => pending_meal_page(&id),
                    Route::FromFavorite { day, id } => favorite_meal_page(day, &id),
                    Route::Settings => settings_page(),
                };
                // Back on iOS and Android is the system's: it pops the page
                // natively, and the routes follow.
                page.on_dismiss(move || nav::truncate(depth.get_untracked()))
            },
        ))
}
