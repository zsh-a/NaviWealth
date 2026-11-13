//! One module per page of the stack, and the parts they share.

mod parts;
mod review;
mod settings;
mod today;

pub use review::{
    edit_meal_page, failure_copy as review_failure_copy, new_meal_page, repeat_meal_page,
};
pub use settings::settings_page;
pub use today::today_page;
