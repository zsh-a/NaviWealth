//! The app's design tokens, the only place raw colors and sizes live.
//!
//! "墨与日光 · Ink & Daylight": a warm daylight canvas, white surfaces lifted
//! by soft light, and ink for everything that acts: buttons, selection,
//! focus. The interface itself is monochrome so that the food (its photos
//! and its nutrition colors) carries the color. Every color is an `AdaptiveColor`, so light and
//! dark (a deep graphite with white ink) switch natively.

use nsh_core::{
    color::rgba,
    element::{AdaptiveColor, BoxShadow, Easing, Spring, Timing},
    geometry::px,
};

/// Color roles.
pub mod color {
    use super::AdaptiveColor;

    const fn c(light: u32, dark: u32) -> AdaptiveColor {
        AdaptiveColor::rgb(light, dark)
    }

    /// The page: warm daylight / deep graphite.
    pub const CANVAS: AdaptiveColor = c(0xF4F3EF, 0x111211);
    /// Cards, sheets, rows.
    pub const SURFACE: AdaptiveColor = c(0xFFFFFF, 0x1B1C1B);
    /// A well inside a surface: macro tiles, detail rows, chips.
    pub const SURFACE_2: AdaptiveColor = c(0xF3F2EE, 0x242522);
    /// Fields and tracks.
    pub const SUNKEN: AdaptiveColor = c(0xECEBE6, 0x20211F);
    /// What sits raised on a track: the selected segment.
    pub const RAISED: AdaptiveColor = c(0xFFFFFF, 0x2D2E2B);
    /// Hairlines.
    pub const LINE: AdaptiveColor = c(0xE7E6E0, 0x30312E);
    /// Stronger edges: unchecked boxes, the grabber.
    pub const LINE_STRONG: AdaptiveColor = c(0xD0CFC8, 0x484944);

    /// Titles and figures.
    pub const INK: AdaptiveColor = c(0x1C1D1A, 0xEAEBE7);
    /// Copy.
    pub const BODY: AdaptiveColor = c(0x32332F, 0xD5D6D0);
    /// Secondary text.
    pub const MUTED: AdaptiveColor = c(0x696A66, 0xA1A29E);
    /// Tertiary marks and inactive controls; readable secondary text uses MUTED.
    pub const FAINT: AdaptiveColor = c(0xA4A59E, 0x686A63);

    /// The primary action's fill: ink.
    pub const ACTION: AdaptiveColor = c(0x1C1D1A, 0xEAEBE7);
    /// Its pressed fill.
    pub const ACTION_PRESSED: AdaptiveColor = c(0x383A34, 0xD0D2CA);
    /// The top of its sheen.
    pub const ACTION_SHEEN: AdaptiveColor = c(0x34362F, 0xF0F1ED);
    /// Text and icons on the action fill.
    pub const ON_ACTION: AdaptiveColor = c(0xFFFFFF, 0x1C1D1A);

    /// Secondary navigation text over translucent material (not ordinary surfaces).
    pub const ON_GLASS_MUTED: AdaptiveColor = c(0x545550, 0xBDBFB7);
    /// Reflected light on the edge of a floating material.
    pub const GLASS_EDGE: AdaptiveColor = AdaptiveColor {
        light: super::rgba(0xFFFFFFB8).to_hsla(),
        dark: super::rgba(0xFFFFFF20).to_hsla(),
    };

    /// Destructive actions and errors.
    pub const DANGER: AdaptiveColor = c(0xAE303B, 0xFF6369);
    pub const DANGER_SOFT: AdaptiveColor = c(0xFDECEC, 0x3A1618);
    /// Estimates to check.
    pub const CAUTION: AdaptiveColor = c(0x8C5A14, 0xFFC046);
    pub const CAUTION_SOFT: AdaptiveColor = c(0xFFF3DA, 0x372809);
    /// Done, connected.
    pub const POSITIVE: AdaptiveColor = c(0x23754F, 0x4CC38A);

    /// Energy from protein: the darkest step of the one warm-stone ramp the
    /// macronutrients share, so the ring reads as one quiet figure.
    pub const PROTEIN: AdaptiveColor = c(0x1F1E1B, 0xF2F1EE);
    /// Energy from carbohydrates: the middle step.
    pub const CARBS: AdaptiveColor = c(0x7A766E, 0xA6A29A);
    /// Energy from fat: the light step.
    pub const FAT: AdaptiveColor = c(0xB5B0A6, 0x6E6A63);
    /// Energy the macronutrients do not explain.
    /// A logged day in the month calendar at its fullest, from the same
    /// stone ramp; lighter days fade it toward the surface.
    pub const HEAT: AdaptiveColor = c(0xC4BFB5, 0x5E5A54);
    /// The ring's empty track.
    pub const TRACK: AdaptiveColor = c(0xECEBE6, 0x20211F);

    /// The dim behind sheets.
    pub const SCRIM: AdaptiveColor = c(0x0A0A0B, 0x000000);
    /// Behind photos while they load.
    pub const PHOTO_WELL: AdaptiveColor = c(0xE7E6E0, 0x20211F);
    /// Text and marks over a photo, on [`MEDIA_SCRIM`].
    pub const ON_MEDIA: AdaptiveColor = c(0xFFFFFF, 0xFFFFFF);
    /// The shade that keeps text over a photo readable.
    pub const MEDIA_SCRIM: AdaptiveColor = c(0x050506, 0x050506);
}

/// Corner radii, from the largest surfaces down. Controls are pills.
pub mod radius {
    /// Sheets' top corners and the content rising over a photo.
    pub const SHEET: f32 = 32.0;
    /// Cards.
    pub const CARD: f32 = 24.0;
    /// Wells inside cards: tiles, detail groups.
    pub const WELL: f32 = 18.0;
    /// Fields.
    pub const FIELD: f32 = 16.0;
    /// Photo thumbnails.
    pub const THUMB: f32 = 16.0;
    /// Small marks.
    pub const BADGE: f32 = 8.0;
}

/// Spacing that is not on the 4 pt scale's methods.
pub mod space {
    /// The page's leading and trailing inset on phones.
    pub const GUTTER: f32 = 20.0;
    /// A card's inset.
    pub const CARD: f32 = 20.0;
}

/// Control heights (touch: at least 48 pt).
pub mod size {
    /// A screen's main action.
    pub const LARGE: f32 = 56.0;
    /// Ordinary buttons and fields.
    pub const MEDIUM: f32 = 50.0;
    /// Compact buttons inside rows and cards (48 pt hit area kept).
    pub const SMALL: f32 = 38.0;
    /// The touch target every pressable keeps.
    pub const TOUCH: f32 = 48.0;
}

/// Translucent layers; content cards and fields remain opaque.
pub mod material {
    /// Light enough that the page keeps moving under the dock; the dock's
    /// own text tints keep their contrast on the mix.
    pub const DOCK_OPACITY: f32 = 0.72;
    pub const DOCK_BLUR: f32 = 24.0;
    /// Readable even over an entirely white photo, with or without blur.
    pub const MEDIA_OPACITY: f32 = 0.64;
    pub const MEDIA_PRESSED_OPACITY: f32 = 0.74;
    pub const EDGE: f32 = 0.75;
}

/// Text roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    /// A meal's total.
    Display,
    /// A page's title.
    LargeTitle,
    /// Sheet titles and empty-state headings (sections use Headline).
    Title,
    /// Figures in cards and tiles.
    Figure,
    /// Row titles, buttons.
    Headline,
    /// Copy.
    Body,
    /// Secondary copy.
    Callout,
    /// Metadata, labels.
    Subhead,
    /// Units, badges.
    Caption,
}

impl Type {
    /// Size, line height, weight (100–900) and tracking, in points.
    pub const fn metrics(self) -> (f32, f32, u16, f32) {
        match self {
            Type::Display => (44.0, 48.0, 700, -1.6),
            Type::LargeTitle => (34.0, 40.0, 700, -1.0),
            Type::Title => (20.0, 26.0, 600, -0.2),
            Type::Figure => (20.0, 24.0, 600, -0.2),
            Type::Headline => (17.0, 25.0, 600, 0.0),
            Type::Body => (16.0, 23.0, 400, 0.0),
            Type::Callout => (15.0, 21.0, 400, 0.0),
            Type::Subhead => (14.0, 21.0, 500, 0.0),
            Type::Caption => (12.5, 18.0, 500, 0.0),
        }
    }
}

/// Soft light: shadows of surfaces that float above the canvas.
pub mod shadow {
    use super::{BoxShadow, px, rgba};

    const fn layer(y: f32, blur: f32, spread: f32, color: u32) -> BoxShadow {
        BoxShadow {
            offset_x: px(0.0),
            offset_y: px(y),
            blur: px(blur),
            spread: px(spread),
            color: rgba(color).to_packed(),
            inset: false,
        }
    }

    /// A card on the daylight canvas: a close contact shadow and a wide,
    /// faint glow under it.
    pub const CARD: [BoxShadow; 2] = [
        layer(1.0, 2.0, 0.0, 0x1A14080A),
        layer(6.0, 20.0, -5.0, 0x1A140814),
    ];
    /// A floating control: the main action, raised round buttons.
    pub const FLOAT: [BoxShadow; 2] = [
        layer(2.0, 6.0, 0.0, 0x0A0A0B1F),
        layer(8.0, 20.0, -6.0, 0x0A0A0B30),
    ];
    /// A narrow floating navigation surface. The spread shadow carries the
    /// "off the page" lift the glass alone cannot say.
    pub const DOCK: [BoxShadow; 2] = [
        layer(2.0, 4.0, 0.0, 0x0A0A0B2E),
        layer(8.0, 28.0, -6.0, 0x0A0A0B45),
    ];
    /// The selected segment on its track.
    pub const SEGMENT: [BoxShadow; 1] = [layer(2.0, 6.0, 0.0, 0x1A140814)];
    /// Dark appearance: depth comes from the surfaces' tone, not shadows.
    pub const NONE: [BoxShadow; 0] = [];
}

/// Typefaces. The engine resolves a family from the app's registered font
/// assets first, then the system. Both roles fall back to the platform sans
/// until the app ships its own faces: put a `.ttf` in the crate's
/// `assets/` directory, list it with `assets!()`, and set these constants
/// to its family name — every text picks the change up through
/// [`Typo`](crate::ui::Typo).
pub mod font {
    /// Body, labels and controls.
    pub const TEXT: &str = "sans-serif";
    /// The figures: Display and Figure sizes. A face with a tabular-minded
    /// numeral set earns its keep here first.
    pub const DISPLAY: &str = "sans-serif";
}

/// Motion: durations in ms, curves and springs. Reduced motion turns every
/// one of them off.
pub mod motion {
    use super::{Easing, Spring, Timing};

    /// A hover wash, a color change.
    pub const INSTANT: f32 = 120.0;
    /// A press, a control's state.
    pub const FAST: f32 = 180.0;
    /// Reveals: a result arriving.
    pub const SLOW: f32 = 380.0;

    /// Rows arriving one after another, this far apart (capped at 8).
    pub const STAGGER: f32 = 50.0;
    /// How far arriving content rises, in points.
    pub const RISE: f32 = 14.0;

    /// A soft settle: fast out, long gentle landing.
    pub const SETTLE: Easing = Easing::Bezier(0.22, 1.0, 0.36, 1.0);
    /// Content arriving.
    pub const ENTER: Timing = Timing::new(SLOW, SETTLE);
    /// Sinking under the finger and back: quick, just short of critical.
    pub const PRESS: Spring = Spring {
        stiffness: 600.0,
        damping: 38.0,
        mass: 1.0,
        velocity: None,
        frame_rate: None,
    };
    /// How far a pressed button shrinks.
    pub const PRESS_SCALE: f32 = 0.98;
    /// How far a pressed card shrinks.
    pub const PRESS_SCALE_CARD: f32 = 0.98;
    /// How far a pressed icon button shrinks.
    pub const PRESS_SCALE_ICON: f32 = 0.96;
}
