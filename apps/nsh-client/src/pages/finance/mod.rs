//! Confirmed manual ledger entries. Account creation stays in the draft until
//! the whole transaction has passed the domain's validation and is saved.
//!
//! `form` owns the draft and its translation to and from balanced postings,
//! `editor` the sheet, `main_panel` and `panels` its bodies, `delete`
//! deletion with Undo, and `rows` the ledger rows and labels other pages
//! share.

mod delete;
mod editor;
mod form;
mod main_panel;
mod panels;
mod rows;

pub(super) use delete::confirm_delete;
pub use editor::finance_editor;
pub(super) use panels::{date_picker, date_picker_through, purpose_field};
pub use rows::transaction_row;
pub(super) use rows::{
    account_option, account_option_with_purpose, category_label, selected_account_label,
    transaction_title,
};
