//! Buttons: one press feedback, one focus ring and one disabled look for
//! every action in the app.
//!
//! ```ignore
//! Btn::primary().size(Size::Large).icon(Icon::Photo).label(|| "Log a meal".into()).on_press(pick)
//! ```

use std::rc::Rc;

use nsh_base::{ButtonElement, button};
use nsh_core::{Haptic, HapticImpact, prelude::*};

use super::{
    Typo,
    feedback::spinner,
    icons::{Icon, icon},
    theme::{Type, color, motion, radius, size},
};

/// What a button means.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Variant {
    /// The one commitment of a decision area (Save, Send, Log).
    #[default]
    Primary,
    /// A clear but quieter action, in the accent's wash.
    Tonal,
    /// An ordinary action on a framed surface.
    Secondary,
    /// A low-emphasis inline or toolbar action.
    Ghost,
    /// A destructive action.
    Danger,
}

impl Variant {
    fn fill(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ACCENT_FILL,
            Variant::Tonal => color::ACCENT_SOFT,
            Variant::Secondary => color::SURFACE,
            Variant::Ghost => AdaptiveColor::TRANSPARENT,
            Variant::Danger => color::DANGER_SOFT,
        }
    }

    fn hover_fill(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ACCENT_FILL.map(|c| c.darken(0.06)),
            Variant::Tonal => color::ACCENT_SOFT.map(|c| c.darken(0.03)),
            Variant::Secondary => color::SUNKEN,
            Variant::Ghost => color::ACCENT_SOFT,
            Variant::Danger => color::DANGER_SOFT.map(|c| c.darken(0.03)),
        }
    }

    fn pressed_fill(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ACCENT_FILL.map(|c| c.darken(0.12)),
            Variant::Tonal => color::ACCENT_SOFT.map(|c| c.darken(0.07)),
            Variant::Secondary => color::LINE,
            Variant::Ghost => color::ACCENT_SOFT.map(|c| c.darken(0.05)),
            Variant::Danger => color::DANGER_SOFT.map(|c| c.darken(0.07)),
        }
    }

    fn ink(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ON_ACCENT,
            Variant::Tonal | Variant::Ghost => color::ACCENT,
            Variant::Secondary => color::INK,
            Variant::Danger => color::DANGER,
        }
    }
}

/// How big a button is: height, padding, text and icon together.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Size {
    /// Inside rows and cards (the touch target stays 44 pt).
    Small,
    /// Ordinary actions.
    #[default]
    Medium,
    /// A screen's main action.
    Large,
}

impl Size {
    fn height(self) -> f32 {
        match self {
            Size::Small => size::SMALL,
            Size::Medium => size::MEDIUM,
            Size::Large => size::LARGE,
        }
    }

    fn padding(self) -> f32 {
        match self {
            Size::Small => 14.0,
            Size::Medium => 18.0,
            Size::Large => 24.0,
        }
    }

    fn icon(self) -> f32 {
        match self {
            Size::Small => 18.0,
            Size::Medium => 20.0,
            Size::Large => 22.0,
        }
    }

    fn radius(self) -> f32 {
        match self {
            Size::Small => radius::SMALL,
            Size::Medium => radius::CONTROL,
            Size::Large => radius::CONTROL + 2.0,
        }
    }

    fn type_(self) -> Type {
        match self {
            Size::Small => Type::Subhead,
            Size::Medium | Size::Large => Type::Headline,
        }
    }
}

type Text = Rc<dyn Fn() -> SharedString>;
type Flag = Rc<dyn Fn() -> bool>;

/// A button being configured; [`Btn::on_press`] makes it.
pub struct Btn {
    variant: Variant,
    size: Size,
    capsule: bool,
    icon: Option<Icon>,
    label: Option<Text>,
    busy: Option<Flag>,
    disabled: Option<Flag>,
}

impl Btn {
    /// A button of `variant`, medium-sized, with no content yet.
    pub fn new(variant: Variant) -> Self {
        Self {
            variant,
            size: Size::Medium,
            capsule: false,
            icon: None,
            label: None,
            busy: None,
            disabled: None,
        }
    }

    pub fn primary() -> Self {
        Self::new(Variant::Primary)
    }

    pub fn tonal() -> Self {
        Self::new(Variant::Tonal)
    }

    pub fn secondary() -> Self {
        Self::new(Variant::Secondary)
    }

    pub fn ghost() -> Self {
        Self::new(Variant::Ghost)
    }

    pub fn size(mut self, size: Size) -> Self {
        self.size = size;
        self
    }

    /// Fully rounded ends: the floating main action only.
    pub fn capsule(mut self) -> Self {
        self.capsule = true;
        self
    }

    pub fn icon(mut self, icon: Icon) -> Self {
        self.icon = Some(icon);
        self
    }

    /// Its label, read in a binding (follows the language).
    pub fn label(mut self, label: impl Fn() -> SharedString + 'static) -> Self {
        self.label = Some(Rc::new(label));
        self
    }

    /// Working: a spinner instead of the icon, no presses, same size.
    pub fn busy(mut self, busy: impl Fn() -> bool + 'static) -> Self {
        self.busy = Some(Rc::new(busy));
        self
    }

    pub fn disabled(mut self, disabled: impl Fn() -> bool + 'static) -> Self {
        self.disabled = Some(Rc::new(disabled));
        self
    }

    /// The button, calling `press` when pressed.
    pub fn on_press(self, press: impl Fn() + 'static) -> ButtonElement {
        let Btn {
            variant,
            size,
            capsule,
            icon: glyph,
            label,
            busy,
            disabled,
        } = self;
        let scale = animated_value(1.0);
        let is_busy = {
            let busy = busy.clone();
            move || busy.as_ref().is_some_and(|busy| busy())
        };
        let inactive = {
            let is_busy = is_busy.clone();
            move || is_busy() || disabled.as_ref().is_some_and(|disabled| disabled())
        };
        let ink = variant.ink();
        let mut element = button()
            .disabled(inactive)
            .on_press_down(move || {
                if !reduce_motion() {
                    scale.spring(motion::PRESS_SCALE, motion::PRESS);
                }
            })
            .on_press_up(move || {
                scale.spring(1.0, motion::PRESS);
            })
            .on_press(move || {
                if variant == Variant::Primary {
                    haptic(Haptic::Impact(HapticImpact::Light));
                }
                press();
            })
            .bind_scale(&scale)
            .flex_row()
            .items_center()
            .justify_center()
            .gap(px(if size == Size::Small { 6.0 } else { 8.0 }))
            .min_h(px(size.height()))
            .px(px(size.padding()))
            .bg(variant.fill())
            .transition_colors()
            .duration(motion::INSTANT)
            .hover(move |s| s.bg(variant.hover_fill()))
            .active(move |s| s.bg(variant.pressed_fill()))
            .focus_visible(|s| {
                s.outline(px(2.0))
                    .outline_color(color::ACCENT)
                    .outline_offset(px(2.0))
            })
            .disabled_style(|s| s.opacity(0.42));
        element = if capsule {
            element.rounded_full()
        } else {
            element.rounded(px(size.radius()))
        };
        if variant == Variant::Secondary {
            element = element.border_1().border_color(color::LINE);
        }
        if size == Size::Small {
            let slop = (size::TOUCH - size.height()) / 2.0;
            element = element.hit_slop(EdgeInsets::all(px(slop)));
        }
        let icon_size = size.icon();
        let leading = glyph.map(move |glyph| {
            let is_busy = is_busy.clone();
            when(
                move || !is_busy(),
                move || icon(glyph, icon_size, ink).into_element(),
            )
            .otherwise(move || spinner(icon_size, ink).into_element())
        });
        let busy_without_icon = glyph.is_none().then(|| {
            when(
                move || busy.as_ref().is_some_and(|busy| busy()),
                move || spinner(icon_size, ink),
            )
        });
        element
            .child(leading)
            .child(busy_without_icon)
            .child(label.map(move |label| {
                text(move || label())
                    .typo(size.type_())
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(ink)
                    .number_of_lines(1)
            }))
    }
}

/// An icon-only button: a square of the touch size, named for screen
/// readers.
pub struct IconBtn {
    icon: Icon,
    variant: Variant,
    label: Text,
    size: f32,
}

impl IconBtn {
    /// A quiet (ghost) button showing `icon`, named `label`.
    pub fn new(icon: Icon, label: impl Fn() -> SharedString + 'static) -> Self {
        Self {
            icon,
            variant: Variant::Ghost,
            label: Rc::new(label),
            size: size::TOUCH,
        }
    }

    pub fn variant(mut self, variant: Variant) -> Self {
        self.variant = variant;
        self
    }

    /// Its side, at least the touch size.
    pub fn side(mut self, side: f32) -> Self {
        self.size = side.max(size::TOUCH);
        self
    }

    pub fn on_press(self, press: impl Fn() + 'static) -> ButtonElement {
        let IconBtn {
            icon: glyph,
            variant,
            label,
            size: side,
        } = self;
        let scale = animated_value(1.0);
        let tint = match variant {
            Variant::Ghost => color::INK,
            other => other.ink(),
        };
        let rest = match variant {
            Variant::Ghost => AdaptiveColor::TRANSPARENT,
            other => other.fill(),
        };
        let element = button()
            .accessibility_label(move || Some(label()))
            .on_press_down(move || {
                if !reduce_motion() {
                    scale.spring(motion::PRESS_SCALE_ICON, motion::PRESS);
                }
            })
            .on_press_up(move || {
                scale.spring(1.0, motion::PRESS);
            })
            .on_press(press)
            .bind_scale(&scale)
            .size(px(side))
            .items_center()
            .justify_center()
            .rounded_full()
            .bg(rest)
            .transition_colors()
            .duration(motion::INSTANT)
            .hover(|s| s.bg(color::SUNKEN))
            .active(|s| s.bg(color::LINE))
            .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
            .disabled_style(|s| s.opacity(0.42))
            .child(icon(glyph, 22.0, tint));
        if variant == Variant::Secondary {
            element.border_1().border_color(color::LINE)
        } else {
            element
        }
    }
}

/// A compact choice or shortcut (a portion size): neutral at rest, the
/// accent's wash while `selected` reads true.
pub fn chip(
    label: impl Fn() -> SharedString + 'static,
    selected: impl Fn() -> bool + Copy + 'static,
    press: impl Fn() + 'static,
) -> ButtonElement {
    button()
        .selected(selected)
        .on_press(press)
        .min_w(px(48.0))
        .min_h(px(size::SMALL))
        .px_3()
        .items_center()
        .justify_center()
        .rounded(px(radius::SMALL))
        .bg(color::SUNKEN)
        .hit_slop(EdgeInsets::all(px(4.0)))
        .transition_colors()
        .duration(motion::INSTANT)
        .hover(|s| s.bg(color::LINE))
        .active(|s| s.bg(color::LINE_STRONG))
        .selected_style(|s| s.bg(color::ACCENT_SOFT))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
        .child(
            text(label)
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .tabular_nums()
                .text_color(move || {
                    if selected() {
                        color::ACCENT
                    } else {
                        color::BODY
                    }
                }),
        )
}
