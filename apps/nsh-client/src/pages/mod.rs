//! The home (three tabs), the pages pushed over it, and the parts they
//! share.

mod capture;
mod drafts;
pub(crate) mod home;
mod parts;
mod records;
mod records_jump;
mod review;
mod review_calendar;
mod review_charts;
pub(crate) mod rows;
mod settings;
mod settings_backup;
mod settings_garmin;
mod settings_model;
mod today;
mod week_review;

pub use home::home_page;
pub use review::{
    edit_meal_page, failure_copy as review_failure_copy, new_meal_page, pending_meal_page,
};
pub use settings::settings_page;
pub use settings_model::model_page;

mod review_note;
