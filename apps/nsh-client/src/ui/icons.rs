//! The app's one icon family: 24 × 24 line glyphs, 1.8 pt round strokes in
//! the element's text color (`currentColor`), so tokens tint them.

use nsh_core::{element::ImageSrc, prelude::*};

/// A glyph.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Icon {
    Photo,
    Pencil,
    Sliders,
    ChevronLeft,
    ChevronRight,
    Plus,
    Minus,
    Trash,
    Check,
    Sparkle,
    Alert,
    Server,
    Chip,
    Eye,
    EyeOff,
    Lock,
    Refresh,
    Utensils,
    Chart,
}

impl Icon {
    fn body(self) -> &'static str {
        match self {
            Icon::Photo => {
                r#"<rect x="3" y="4.5" width="18" height="15" rx="3.5"/><circle cx="9" cy="10" r="1.6"/><path d="M3.6 17.2l4.9-4.4 3.6 3.1 2.9-2.4 5.4 4.4"/>"#
            }
            Icon::Pencil => {
                r#"<path d="M4.5 19.5h3.8L18.6 9.2a2.1 2.1 0 0 0 0-3L17.8 5.4a2.1 2.1 0 0 0-3 0L4.5 15.7z"/><path d="M13.5 6.7l3.8 3.8"/>"#
            }
            Icon::Sliders => {
                r#"<path d="M4 7.5h9M17.5 7.5H20M4 16.5h3M11.5 16.5H20"/><circle cx="15.2" cy="7.5" r="2.2"/><circle cx="9.2" cy="16.5" r="2.2"/>"#
            }
            Icon::ChevronLeft => r#"<path d="M14.5 5.5L8 12l6.5 6.5"/>"#,
            Icon::ChevronRight => r#"<path d="M9.5 5.5L16 12l-6.5 6.5"/>"#,
            Icon::Plus => r#"<path d="M12 5v14M5 12h14"/>"#,
            Icon::Minus => r#"<path d="M5 12h14"/>"#,
            Icon::Trash => {
                r#"<path d="M4.5 7h15M10 11v6M14 11v6M6.5 7l.8 11.6A2 2 0 0 0 9.3 20.5h5.4a2 2 0 0 0 2-1.9L17.5 7M9.2 7V5a1.5 1.5 0 0 1 1.5-1.5h2.6A1.5 1.5 0 0 1 14.8 5v2"/>"#
            }
            Icon::Check => r#"<path d="M5 12.5l4.4 4.4L19 7.4"/>"#,
            Icon::Sparkle => {
                r#"<path d="M11 3.5c.5 3.9 2.6 6 6.5 6.5-3.9.5-6 2.6-6.5 6.5-.5-3.9-2.6-6-6.5-6.5 3.9-.5 6-2.6 6.5-6.5z"/><path d="M18.5 15.5c.2 1.4.9 2.1 2.3 2.3-1.4.2-2.1.9-2.3 2.3-.2-1.4-.9-2.1-2.3-2.3 1.4-.2 2.1-.9 2.3-2.3z"/>"#
            }
            Icon::Alert => {
                r#"<circle cx="12" cy="12" r="8.8"/><path d="M12 7.6v5.2"/><path d="M12 16.4h.01"/>"#
            }
            Icon::Server => {
                r#"<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>"#
            }
            Icon::Chip => {
                r#"<rect x="6" y="6" width="12" height="12" rx="2.6"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/>"#
            }
            Icon::Eye => {
                r#"<path d="M2.8 12s3.4-6.3 9.2-6.3 9.2 6.3 9.2 6.3-3.4 6.3-9.2 6.3S2.8 12 2.8 12z"/><circle cx="12" cy="12" r="2.8"/>"#
            }
            Icon::EyeOff => {
                r#"<path d="M9.9 5.9A9 9 0 0 1 12 5.7c5.8 0 9.2 6.3 9.2 6.3a16.6 16.6 0 0 1-2.4 3.2M6.6 7.3A16 16 0 0 0 2.8 12s3.4 6.3 9.2 6.3a8.9 8.9 0 0 0 4.3-1.1"/><path d="M10 10a2.8 2.8 0 0 0 4 4"/><path d="M4 4l16 16"/>"#
            }
            Icon::Lock => {
                r#"<rect x="5" y="10.5" width="14" height="10" rx="2.6"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.6 0v2.5"/>"#
            }
            Icon::Refresh => {
                r#"<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.8 4.5v4.3h-4.3"/>"#
            }
            Icon::Utensils => {
                r#"<path d="M7 3.5v17M4.4 3.5v4.8a2.6 2.6 0 0 0 5.2 0V3.5"/><path d="M17.2 20.5V3.5c-2.3 1.3-3.7 3.9-3.7 7.1V14h3.7"/>"#
            }
            Icon::Chart => r#"<path d="M4 20h16"/><path d="M7 16.5v-5M12 16.5V7M17 16.5v-3.5"/>"#,
        }
    }

    /// The glyph as an SVG document.
    pub fn markup(self) -> String {
        format!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{}</svg>"#,
            self.body()
        )
    }
}

/// `icon` at `size` points, tinted by `tint` (a token, or a closure picking
/// one). Hidden from screen readers: the control it sits in is named.
pub fn icon(icon: Icon, size: f32, tint: impl IntoReactive<AdaptiveColor>) -> impl IntoElement {
    svg(ImageSrc::svg_markup(&icon.markup()))
        .size(px(size))
        .flex_shrink_0()
        .text_color(tint)
        .accessibility_elements_hidden(true)
}
