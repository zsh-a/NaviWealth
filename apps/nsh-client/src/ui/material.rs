//! Floating materials share one tint, light direction and opaque fallback.
//! Blur is confined to navigation; task sheets stay on matte surfaces.

use nsh_core::{platform::Os, prelude::*};

use super::{
    Lift,
    theme::{color, material, shadow},
};

#[derive(Clone, Copy)]
pub enum Glass {
    Dock,
    Sheet,
}

/// Android reports its API level; backdrop rendering starts at API 31.
/// The GTK preview uses a solid dock, as do older Android versions.
fn backdrop_available() -> bool {
    match os() {
        Os::Android => os_version().0 >= 31,
        Os::Linux => false,
        _ => true,
    }
}

pub fn glass<E: Styled>(element: E, kind: Glass) -> E {
    if matches!(kind, Glass::Sheet) {
        // No shadow: the opaque surface over the scrim separates it, and a
        // large blurred shadow is costly to redraw while the sheet moves
        // with the keyboard.
        return element.bg(color::SURFACE).backdrop_filter_none();
    }
    let element = if backdrop_available() {
        element
            .bg(color::GLASS.opacity(material::DOCK_OPACITY))
            .backdrop_blur(px(material::DOCK_BLUR))
    } else {
        element.bg(color::GLASS).backdrop_filter_none()
    };
    element
        .border(px(material::EDGE))
        .border_color(color::GLASS_EDGE)
        .lift(&shadow::FLOAT)
}
