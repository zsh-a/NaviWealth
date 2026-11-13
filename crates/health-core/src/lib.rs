//! One meal-recognition contract for native hosts. This crate never stores
//! records, uploads in the background, or owns the user's consent UI.

pub mod catalog;
pub mod consent;
pub mod nutrition;
pub mod photo;
pub mod recognition;

pub use consent::{Consent, ConsentError, UploadTarget};
pub use photo::{MealPhoto, PhotoError, PhotoRole};
pub use recognition::{MealEstimate, PROMPT_VERSION, recognize_meal};
