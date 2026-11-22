//! Exclusive choices with a native sliding underline.

use std::rc::Rc;

use nsh_base::{tab, tabs};
use nsh_core::{Haptic, prelude::*};

use super::{
    Typo,
    theme::{Type, color, size},
};

/// One choice: its value and its label (read in a binding).
pub struct Segment<T> {
    pub value: T,
    pub label: Rc<dyn Fn() -> SharedString>,
}

impl<T> Segment<T> {
    pub fn new(value: T, label: impl Fn() -> SharedString + 'static) -> Self {
        Self {
            value,
            label: Rc::new(label),
        }
    }
}

/// The control over `segments`; `selected` reads the current value (the
/// caller owns it) and `select` asks for another.
pub fn segmented<T: Copy + PartialEq + 'static>(
    segments: Vec<Segment<T>>,
    selected: impl Fn() -> T + Copy + 'static,
    select: impl Fn(T) + Copy + 'static,
) -> impl IntoElement {
    // Margins resolve against the whole row. Inset by one third of a tab
    // on either side so the mark scales from a header switch to a full row.
    let inset = relative(1.0 / (3.0 * segments.len().max(1) as f32));
    tabs()
        .flex_row()
        .indicator_style(move |s| {
            s.bottom(px(5.0))
                .h(px(2.0))
                .mx(inset)
                .rounded_full()
                .bg(color::ACCENT)
        })
        .children(segments.into_iter().map(move |segment| {
            let value = segment.value;
            let label = segment.label;
            let is_selected = move || selected() == value;
            tab()
                .selected(is_selected)
                .on_press(move |_: &()| {
                    if selected() != value {
                        haptic(Haptic::Selection);
                        select(value);
                    }
                })
                .flex_1()
                .min_w(px(0.0))
                .min_h(px(size::TOUCH))
                .py(px(9.0))
                .items_center()
                .justify_center()
                .rounded_full()
                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                .child(
                    text(move || label())
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .number_of_lines(2)
                        .text_center()
                        .text_color(move || {
                            if is_selected() {
                                color::ACCENT_INK
                            } else {
                                color::MUTED
                            }
                        }),
                )
        }))
}
