//! The app's design tokens, the only place raw colors and sizes live.
//!
//! "墨与日光 · Ink & Daylight": a warm daylight canvas, white surfaces lifted
//! by soft light, and ink for everything that acts: buttons, selection,
//! focus. The interface itself is monochrome so that the food (its photos
//! and its nutrition colors) carries the color. An iris-to-sky light marks
//! the moments the AI works. Every color is an `AdaptiveColor`, so light and
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
    pub const CANVAS: AdaptiveColor = c(0xF5F4F1, 0x0A0A0B);
    /// Cards, sheets, rows.
    pub const SURFACE: AdaptiveColor = c(0xFFFFFF, 0x161618);
    /// A well inside a surface: macro tiles, detail rows, chips.
    pub const SURFACE_2: AdaptiveColor = c(0xF4F3F0, 0x1F1F22);
    /// Fields and tracks.
    pub const SUNKEN: AdaptiveColor = c(0xEFEEEA, 0x1C1C1F);
    /// What sits raised on a track: the selected segment.
    pub const RAISED: AdaptiveColor = c(0xFFFFFF, 0x2C2C30);
    /// Hairlines.
    pub const LINE: AdaptiveColor = c(0xEAE9E5, 0x26262A);
    /// Stronger edges: unchecked boxes, the grabber.
    pub const LINE_STRONG: AdaptiveColor = c(0xD4D3CE, 0x3C3C41);

    /// Titles and figures.
    pub const INK: AdaptiveColor = c(0x0E0E10, 0xF6F6F7);
    /// Copy.
    pub const BODY: AdaptiveColor = c(0x2C2C30, 0xE2E2E6);
    /// Secondary text.
    pub const MUTED: AdaptiveColor = c(0x76767C, 0x9C9CA4);
    /// Tertiary marks: chevrons, placeholders.
    pub const FAINT: AdaptiveColor = c(0xABABB0, 0x606066);

    /// The primary action's fill: ink.
    pub const ACTION: AdaptiveColor = c(0x111113, 0xF6F6F7);
    /// Its pressed fill.
    pub const ACTION_PRESSED: AdaptiveColor = c(0x33333A, 0xD6D6DA);
    /// The top of its sheen.
    pub const ACTION_SHEEN: AdaptiveColor = c(0x2E2E33, 0xFFFFFF);
    /// Text and icons on the action fill.
    pub const ON_ACTION: AdaptiveColor = c(0xFFFFFF, 0x0B0B0C);

    /// The AI's light, from iris to sky: analysis, estimates.
    pub const AI_FROM: AdaptiveColor = c(0x7B61FF, 0x9B87FF);
    pub const AI_TO: AdaptiveColor = c(0x22B8F0, 0x48C9F5);

    /// Destructive actions and errors.
    pub const DANGER: AdaptiveColor = c(0xE5484D, 0xFF6369);
    pub const DANGER_SOFT: AdaptiveColor = c(0xFDECEC, 0x3A1618);
    /// Estimates to check.
    pub const CAUTION: AdaptiveColor = c(0xB86E00, 0xFFC046);
    pub const CAUTION_SOFT: AdaptiveColor = c(0xFFF3DA, 0x372809);
    /// Done, connected.
    pub const POSITIVE: AdaptiveColor = c(0x1E9A55, 0x4CC38A);

    /// Energy from protein.
    pub const PROTEIN: AdaptiveColor = c(0xFF5A5F, 0xFF6E72);
    /// Energy from carbohydrates.
    pub const CARBS: AdaptiveColor = c(0xFFAA1C, 0xFFBF45);
    /// Energy from fat.
    pub const FAT: AdaptiveColor = c(0x3D8BFF, 0x5C9DFF);
    /// Energy the macronutrients do not explain.
    pub const OTHER: AdaptiveColor = c(0xCCCAC4, 0x4A4A50);
    /// The ring's empty track.
    pub const TRACK: AdaptiveColor = c(0xEFEEEA, 0x1E1E22);

    /// The dim behind sheets.
    pub const SCRIM: AdaptiveColor = c(0x0A0A0B, 0x000000);
    /// Behind photos while they load.
    pub const PHOTO_WELL: AdaptiveColor = c(0xE7E6E2, 0x1C1C1F);
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

/// Control heights (touch: at least 44 pt).
pub mod size {
    /// A screen's main action.
    pub const LARGE: f32 = 56.0;
    /// Ordinary buttons and fields.
    pub const MEDIUM: f32 = 50.0;
    /// Compact buttons inside rows and cards (44 pt hit area kept).
    pub const SMALL: f32 = 38.0;
    /// The touch target every pressable keeps.
    pub const TOUCH: f32 = 44.0;
}

/// Text roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    /// A meal's total.
    Display,
    /// A page's title.
    LargeTitle,
    /// Section and sheet titles.
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
            Type::Title => (22.0, 28.0, 700, -0.4),
            Type::Figure => (20.0, 24.0, 700, -0.4),
            Type::Headline => (17.0, 22.0, 600, -0.2),
            Type::Body => (16.0, 23.0, 400, 0.0),
            Type::Callout => (15.0, 21.0, 400, 0.0),
            Type::Subhead => (14.0, 19.0, 500, 0.0),
            Type::Caption => (12.5, 16.0, 600, 0.0),
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
        layer(10.0, 30.0, -6.0, 0x1A14081A),
    ];
    /// A floating control: the main action, raised round buttons.
    pub const FLOAT: [BoxShadow; 2] = [
        layer(2.0, 6.0, 0.0, 0x0A0A0B1F),
        layer(14.0, 32.0, -8.0, 0x0A0A0B40),
    ];
    /// The selected segment on its track.
    pub const SEGMENT: [BoxShadow; 1] = [layer(2.0, 6.0, 0.0, 0x1A140814)];
    /// Dark appearance: depth comes from the surfaces' tone, not shadows.
    pub const NONE: [BoxShadow; 0] = [];
}

/// Motion: durations in ms, curves and springs. Reduced motion turns every
/// one of them off.
pub mod motion {
    use super::{Easing, Spring, Timing};

    /// A hover wash, a color change.
    pub const INSTANT: f32 = 120.0;
    /// A press, a control's state.
    pub const FAST: f32 = 180.0;
    /// Moving into place: a selection sliding, a glyph swapping.
    pub const BASE: f32 = 240.0;
    /// Reveals: a result arriving.
    pub const SLOW: f32 = 380.0;
    /// Unhurried entrances: the ring filling, figures counting.
    pub const SLOWER: f32 = 640.0;

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
    pub const PRESS_SCALE: f32 = 0.96;
    /// How far a pressed card shrinks.
    pub const PRESS_SCALE_CARD: f32 = 0.98;
    /// How far a pressed icon button shrinks.
    pub const PRESS_SCALE_ICON: f32 = 0.9;
}
