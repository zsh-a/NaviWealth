//! The app's styled layer over `nsh_base`: features build only from these
//! components and the layout primitives, never restyling a control
//! themselves. A look a feature needs becomes a variant here first.

pub mod button;
pub mod feedback;
pub mod field;
pub mod icons;
pub mod ring;
pub mod segmented;
pub mod sheet;
pub mod surface;
pub mod theme;
pub mod toast;
pub mod toggle;

use nsh_core::{LineHeight, prelude::*};

pub use button::{Btn, IconBtn, Size, Variant};
pub use icons::{Icon, icon};
pub use theme::{Type, color, motion, radius, space};

/// Text roles on any styled element ([`Type`]).
pub trait Typo: Styled + Sized {
    /// Sets the size, line height and weight of `role`.
    fn typo(self, role: Type) -> Self {
        let (size, line, weight) = role.metrics();
        let styled = self
            .text_size(px(size))
            .line_height(LineHeight::Points(px(line)))
            .font_weight(FontWeight(weight));
        match role {
            Type::Display | Type::LargeTitle => styled.letter_spacing(px(-0.6)),
            _ => styled,
        }
    }
}

impl<T: Styled + Sized> Typo for T {}
