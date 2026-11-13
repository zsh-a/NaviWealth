//! Buttons: pills of one press feedback, one focus ring and one disabled
//! look for every action in the app.
//!
//! ```ignore
//! Btn::primary().size(Size::Large).icon(Icon::Photo).label(|| "Log a meal".into()).on_press(pick)
//! ```

use std::rc::Rc;

use nsh_base::{ButtonElement, button};
use nsh_core::{Haptic, HapticImpact, prelude::*};

use super::{
    Lift, Typo,
    feedback::spinner,
    icons::{Icon, icon},
    theme::{Type, color, motion, shadow, size},
};

/// What a button means.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Variant {
    /// The one commitment of a decision area: ink.
    #[default]
    Primary,
    /// A neutral well: secondary actions inside cards.
    Tonal,
    /// A raised surface: an action floating on the canvas.
    Secondary,
    /// No fill: low-emphasis inline actions.
    Ghost,
    /// A destructive action.
    Danger,
    /// Frosted glass over a photo.
    Glass,
}

impl Variant {
    fn fill(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ACTION,
            Variant::Tonal => color::SURFACE_2,
            Variant::Secondary => color::SURFACE,
            Variant::Ghost => AdaptiveColor::TRANSPARENT,
            Variant::Danger => color::DANGER_SOFT,
            Variant::Glass => color::MEDIA_SCRIM.opacity(0.38),
        }
    }

    fn pressed_fill(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ACTION_PRESSED,
            Variant::Tonal | Variant::Ghost => color::SUNKEN,
            Variant::Secondary => color::SURFACE_2,
            Variant::Danger => color::DANGER_SOFT.map(|c| c.darken(0.05)),
            Variant::Glass => color::MEDIA_SCRIM.opacity(0.55),
        }
    }

    fn ink(self) -> AdaptiveColor {
        match self {
            Variant::Primary => color::ON_ACTION,
            Variant::Tonal | Variant::Secondary | Variant::Ghost => color::INK,
            Variant::Danger => color::DANGER,
            Variant::Glass => color::ON_MEDIA,
        }
    }

    /// Fill, sheen, edge and lift: the parts that make the surface.
    fn surface<E: Styled + Sized>(self, element: E) -> E {
        let element = element.bg(self.fill());
        match self {
            Variant::Primary => element
                .bg_linear_to_b()
                .gradient_from(color::ACTION_SHEEN)
                .gradient_to(color::ACTION)
                .lift(&shadow::FLOAT),
            Variant::Secondary => element
                .lift(&shadow::CARD)
                .dark(|s| s.border_1().border_color(color::LINE)),
            Variant::Glass => element.backdrop_blur(px(18.0)),
            _ => element,
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
            Size::Small => 16.0,
            Size::Medium => 22.0,
            Size::Large => 26.0,
        }
    }

    fn icon(self) -> f32 {
        match self {
            Size::Small => 18.0,
            Size::Medium => 20.0,
            Size::Large => 22.0,
        }
    }

    fn type_(self) -> Type {
        match self {
            Size::Small => Type::Subhead,
            Size::Medium | Size::Large => Type::Headline,
        }
    }
}

type Label = Rc<dyn Fn() -> SharedString>;
type Flag = Rc<dyn Fn() -> bool>;

/// A button being configured; [`Btn::on_press`] makes it.
pub struct Btn {
    variant: Variant,
    size: Size,
    icon: Option<Icon>,
    label: Option<Label>,
    busy: Option<Flag>,
    disabled: Option<Flag>,
}

impl Btn {
    /// A button of `variant`, medium-sized, with no content yet.
    pub fn new(variant: Variant) -> Self {
        Self {
            variant,
            size: Size::Medium,
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
        let is_disabled = move || disabled.as_ref().is_some_and(|disabled| disabled());
        let inactive = {
            let (is_busy, is_disabled) = (is_busy.clone(), is_disabled.clone());
            move || is_busy() || is_disabled()
        };
        // Disabled goes flat and quiet; busy keeps its full look (the
        // spinner says it is working).
        let dim = {
            let is_busy = is_busy.clone();
            move || is_disabled() && !is_busy()
        };
        let ink = variant.ink();
        let tint = {
            let dim = dim.clone();
            move || if dim() { color::FAINT } else { ink }
        };
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
            .rounded_full()
            .transition_colors()
            .duration(motion::INSTANT)
            .active(move |s| s.bg(variant.pressed_fill()))
            .hover(move |s| s.bg(variant.pressed_fill()))
            .focus_visible(|s| {
                s.outline(px(2.0))
                    .outline_color(color::INK)
                    .outline_offset(px(2.0))
            });
        element = variant.surface(element);
        if variant == Variant::Primary {
            let quiet = move |dim: bool, on: AdaptiveColor| if dim { color::SUNKEN } else { on };
            let (bg, from, to) = (dim.clone(), dim.clone(), dim.clone());
            element = element
                .bg(move || quiet(bg(), color::ACTION))
                .gradient_from(move || quiet(from(), color::ACTION_SHEEN))
                .gradient_to(move || quiet(to(), color::ACTION))
                .disabled_style(|s| s.shadow_none());
        }
        if size == Size::Small {
            let slop = (size::TOUCH - size.height()) / 2.0;
            element = element.hit_slop(EdgeInsets::all(px(slop)));
        }
        let icon_size = size.icon();
        let leading = glyph.map(|glyph| {
            let is_busy = is_busy.clone();
            let tint = tint.clone();
            when(
                move || !is_busy(),
                move || icon(glyph, icon_size, tint.clone()).into_element(),
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
                    .text_color(tint)
                    .number_of_lines(1)
            }))
    }
}

/// An icon-only button: a circle of the touch size, named for screen
/// readers.
pub struct IconBtn {
    icon: Icon,
    variant: Variant,
    label: Label,
    side: f32,
}

impl IconBtn {
    /// A quiet (ghost) button showing `icon`, named `label`.
    pub fn new(icon: Icon, label: impl Fn() -> SharedString + 'static) -> Self {
        Self {
            icon,
            variant: Variant::Ghost,
            label: Rc::new(label),
            side: size::TOUCH,
        }
    }

    pub fn variant(mut self, variant: Variant) -> Self {
        self.variant = variant;
        self
    }

    /// Its diameter, at least the touch size.
    pub fn side(mut self, side: f32) -> Self {
        self.side = side.max(size::TOUCH);
        self
    }

    pub fn on_press(self, press: impl Fn() + 'static) -> ButtonElement {
        let IconBtn {
            icon: glyph,
            variant,
            label,
            side,
        } = self;
        let scale = animated_value(1.0);
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
            .transition_colors()
            .duration(motion::INSTANT)
            .hover(move |s| s.bg(variant.pressed_fill()))
            .active(move |s| s.bg(variant.pressed_fill()))
            .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
            .disabled_style(|s| s.opacity(0.3))
            .child(icon(
                glyph,
                if side > 48.0 { 24.0 } else { 22.0 },
                variant.ink(),
            ));
        variant.surface(element)
    }
}

/// A compact choice or shortcut (a portion size): a neutral pill at rest,
/// ink while `selected` reads true.
pub fn chip(
    label: impl Fn() -> SharedString + 'static,
    selected: impl Fn() -> bool + Copy + 'static,
    press: impl Fn() + 'static,
) -> ButtonElement {
    let scale = animated_value(1.0);
    button()
        .selected(selected)
        .on_press_down(move || {
            if !reduce_motion() {
                scale.spring(motion::PRESS_SCALE, motion::PRESS);
            }
        })
        .on_press_up(move || {
            scale.spring(1.0, motion::PRESS);
        })
        .on_press(press)
        .bind_scale(&scale)
        .min_w(px(52.0))
        .min_h(px(size::SMALL))
        .px_4()
        .items_center()
        .justify_center()
        .rounded_full()
        .bg(color::SURFACE_2)
        .hit_slop(EdgeInsets::all(px(4.0)))
        .transition_colors()
        .duration(motion::FAST)
        .hover(|s| s.bg(color::SUNKEN))
        .active(|s| s.bg(color::SUNKEN))
        .selected_style(|s| s.bg(color::ACTION))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
        .child(
            text(label)
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .tabular_nums()
                .text_color(move || {
                    if selected() {
                        color::ON_ACTION
                    } else {
                        color::BODY
                    }
                }),
        )
}
