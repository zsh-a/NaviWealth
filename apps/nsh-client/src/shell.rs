//! The app shell: Today at the bottom of the navigation stack and the
//! pages the routes open over it. No page logic here.

use nsh_base::nav_stack;
use nsh_core::prelude::*;

use crate::{
    nav::{self, Route},
    pages::{
        edit_meal_page, new_meal_page, repeat_meal_page, settings_page, today_page,
        week_review_page,
    },
};

pub fn shell() -> impl IntoElement {
    nav_stack()
        .flex_1()
        .child(today_page().key("today"))
        .child(each(
            nav::open,
            |route: &Route| route.key(),
            |route, depth| {
                let page = match route.get_untracked() {
                    Route::NewMeal { day, capture } => new_meal_page(day, capture),
                    Route::EditMeal(id) => edit_meal_page(&id),
                    Route::RepeatMeal { day, from } => repeat_meal_page(day, &from),
                    Route::Settings => settings_page(),
                    Route::WeekReview => week_review_page(),
                };
                // Back on iOS and Android is the system's: it pops the page
                // natively, and the routes follow.
                page.on_dismiss(move || nav::truncate(depth.get_untracked()))
            },
        ))
}
