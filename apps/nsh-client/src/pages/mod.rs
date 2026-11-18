//! The home (four tabs), the pages pushed over it, and the parts they
//! share.

pub(crate) mod assets;
mod capture;
mod drafts;
pub(crate) mod finance;
pub(crate) mod finance_review;
pub(crate) mod holdings;
pub(crate) mod home;
mod parts;
mod records;
mod records_jump;
mod review;
mod review_calendar;
mod review_charts;
pub(crate) mod rows;
mod settings;
pub(crate) mod settings_backup;
mod settings_body;
mod settings_garmin;
mod settings_model;
mod settings_updates;
mod today;
mod week_review;

pub use home::home_page;
pub use review::{
    edit_meal_page, failure_copy as review_failure_copy, new_meal_page, pending_meal_page,
};
pub use settings::settings_page;
pub(crate) use settings_body::{body_profile_page, open_body_profile};
pub use settings_model::model_page;

pub(crate) mod exchange_rates;
mod review_note;
pub(crate) mod security_picker;
pub(crate) mod statement_import;

pub mod price_history;
