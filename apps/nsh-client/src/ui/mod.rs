//! The app's styled layer over `nsh_base`: features build only from these
//! components and the layout primitives, never restyling a control
//! themselves. A look a feature needs becomes a variant here first.

pub mod button;
pub mod feedback;
pub mod field;
pub mod figures;
pub mod icons;
pub mod ring;
pub mod segmented;
pub mod sheet;
pub mod surface;
pub mod theme;
pub mod toast;
pub mod toggle;

use nsh_core::{LineHeight, element::BoxShadow, prelude::*};

pub use button::{Btn, IconBtn, Size, Variant};
pub use icons::{Icon, icon};
pub use theme::{Type, color, motion, radius, space};

/// Text roles on any styled element ([`Type`]).
pub trait Typo: Styled + Sized {
    /// Sets the size, line height, weight and tracking of `role`.
    fn typo(self, role: Type) -> Self {
        let (size, line, weight, tracking) = role.metrics();
        let styled = self
            .text_size(px(size))
            .line_height(LineHeight::Points(px(line)))
            .font_weight(FontWeight(weight));
        if tracking != 0.0 {
            styled.letter_spacing(px(tracking))
        } else {
            styled
        }
    }
}

impl<T: Styled + Sized> Typo for T {}

/// Soft light under floating surfaces.
pub trait Lift: Styled + Sized {
    /// Casts `layers` in light appearance; dark surfaces float by tone.
    fn lift(self, layers: &'static [BoxShadow]) -> Self {
        self.shadow(layers.iter().copied())
            .dark(|s| s.shadow(theme::shadow::NONE))
    }
}

impl<T: Styled + Sized> Lift for T {}
