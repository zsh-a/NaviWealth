//! Floating materials share one tint, light direction and opaque fallback.
//! Blur is confined to navigation and sheets; content stays on matte surfaces.

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
    let (opacity, blur) = match kind {
        Glass::Dock => (material::DOCK_OPACITY, material::DOCK_BLUR),
        Glass::Sheet => (material::SHEET_OPACITY, material::SHEET_BLUR),
    };
    let element = if backdrop_available() {
        element
            .bg(color::SURFACE.opacity(opacity))
            .backdrop_blur(px(blur))
    } else {
        element.bg(color::SURFACE).backdrop_filter_none()
    };
    match kind {
        Glass::Dock => element
            .border(px(material::EDGE))
            .border_color(color::GLASS_EDGE)
            .lift(&shadow::DOCK),
        Glass::Sheet => element
            .border_t(px(material::EDGE))
            .border_color(color::GLASS_EDGE)
            .bg_linear_to_b()
            .gradient_from(color::GLASS_WASH)
            .gradient_to(AdaptiveColor::TRANSPARENT)
            .lift(&shadow::SHEET),
    }
}
