//! Compatibility exports for the shared health domain.
pub use navi_health::review::*;

/// One personal review entry per local day, kept as a single line.
pub const MAX_NOTE_CHARS: usize = 280;
pub fn valid_note(text: &str) -> bool {
    !text.trim().is_empty()
        && text.chars().count() <= MAX_NOTE_CHARS
        && !text.contains(['\n', '\r'])
}
