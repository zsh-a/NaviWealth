//! Health logic shared by native hosts: the meal-recognition contract and
//! the Garmin Personal API requests and parsing. This crate does no I/O,
//! never stores records, uploads in the background, or owns consent UI.

pub mod catalog;
pub mod consent;
pub mod garmin;
pub mod nutrition;
pub mod photo;
pub mod recognition;
pub mod weight;

pub use consent::{Consent, ConsentError, UploadTarget};
pub use photo::{MealPhoto, PhotoError, PhotoRole};
pub use recognition::{MealEstimate, PROMPT_VERSION, recognize_meal};
