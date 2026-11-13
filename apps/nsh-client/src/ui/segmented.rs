//! A segmented control: a few exclusive choices in one track, with one
//! selection that slides to the chosen segment (natively, on a spring).

use std::rc::Rc;

use nsh_base::{tab, tabs};
use nsh_core::{Haptic, prelude::*};

use super::{
    Lift, Typo,
    theme::{Type, color, shadow},
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
    tabs()
        .flex_row()
        .p(px(4.0))
        .rounded_full()
        .bg(color::SUNKEN)
        .indicator_style(move |s| {
            s.top(px(4.0))
                .bottom(px(4.0))
                .rounded_full()
                .bg(color::RAISED)
                .lift(&shadow::SEGMENT)
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
                .min_h(px(38.0))
                .items_center()
                .justify_center()
                .rounded_full()
                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                .child(
                    text(move || label())
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .number_of_lines(1)
                        .text_color(move || {
                            if is_selected() {
                                color::INK
                            } else {
                                color::MUTED
                            }
                        }),
                )
        }))
}
