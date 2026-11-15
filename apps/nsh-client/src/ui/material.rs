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
/// NSH 0.5's GTK renderer does not draw backdrop filters. These paths keep
/// a solid surface so unsupported blur never exposes sharp text underneath.
fn backdrop_available() -> bool {
    match os() {
        Os::Android => os_version().0 >= 31,
        Os::Linux => false,
        _ => true,
    }
}

pub fn glass<E: Styled>(element: E, kind: Glass) -> E {
    if matches!(kind, Glass::Sheet) {
        return element
            .bg(color::SURFACE)
            .backdrop_filter_none()
            .lift(&shadow::SHEET);
    }
    let element = if backdrop_available() {
        element
            .bg(color::SURFACE.opacity(material::DOCK_OPACITY))
            .backdrop_blur(px(material::DOCK_BLUR))
    } else {
        element.bg(color::SURFACE).backdrop_filter_none()
    };
    element
        .border(px(material::EDGE))
        .border_color(color::GLASS_EDGE)
        .lift(&shadow::DOCK)
}
