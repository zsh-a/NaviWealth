//! Health models, deterministic calculations and validated SQLite repositories.
//! Hosts own device transports, UI consent, migration ordering and cross-domain
//! transactions. Recognition calls use a caller-supplied transport; nothing
//! uploads in the background or confirms records without its host.

pub mod bodycomp;
pub mod catalog;
pub mod consent;
pub mod favorite;
pub mod garmin;
pub mod meal;
pub mod nutrition;
pub mod photo;
pub mod profile;
pub mod recognition;
pub mod review;
pub mod scale;
pub mod store;
pub mod weight;

pub use consent::{Consent, ConsentError, UploadTarget};
pub use photo::{MealPhoto, PhotoError, PhotoRole};
pub use recognition::{MealEstimate, PROMPT_VERSION, PreparedMeal, PreparedMealView, prepare_meal};
