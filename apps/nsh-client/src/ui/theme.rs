//! The app's design tokens, the only place raw colors and sizes live.
//!
//! "澄白 · Porcelain": a cool porcelain canvas, white grouped surfaces and
//! graphite text keep figures readable; iris marks what can be pressed and
//! what is selected. Food data has its own colors (protein rose, carbs
//! amber, fat teal) that never stand in for actions or status. Every color
//! is an `AdaptiveColor`, so light and dark switch natively.

use nsh_core::element::{AdaptiveColor, Easing, Spring, Timing};

/// Color roles.
pub mod color {
    use super::AdaptiveColor;

    const fn c(light: u32, dark: u32) -> AdaptiveColor {
        AdaptiveColor::rgb(light, dark)
    }

    /// The page.
    pub const CANVAS: AdaptiveColor = c(0xF5F6F9, 0x0E1015);
    /// Grouped content: cards, lists, sheets.
    pub const SURFACE: AdaptiveColor = c(0xFFFFFF, 0x181B22);
    /// A control or well on a surface: fields, tracks, steppers.
    pub const SUNKEN: AdaptiveColor = c(0xEEF0F4, 0x242833);
    /// What sits raised on a sunken track: the selected segment.
    pub const RAISED: AdaptiveColor = c(0xFFFFFF, 0x363C4C);
    /// A switch's knob.
    pub const KNOB: AdaptiveColor = c(0xFFFFFF, 0xF3F4F8);
    /// Hairlines between rows and around fields.
    pub const LINE: AdaptiveColor = c(0xE4E7EE, 0x2C313D);
    /// A field's edge when it has focus.
    pub const LINE_STRONG: AdaptiveColor = c(0xC9CEDA, 0x434A5A);

    /// Titles and figures.
    pub const INK: AdaptiveColor = c(0x161922, 0xF3F4F8);
    /// Readable copy.
    pub const BODY: AdaptiveColor = c(0x2A2F3B, 0xD9DDE6);
    /// Secondary text: units, metadata.
    pub const MUTED: AdaptiveColor = c(0x646B7A, 0xA2A9B9);
    /// Tertiary marks: chevrons, placeholders.
    pub const FAINT: AdaptiveColor = c(0x9097A5, 0x6E7586);

    /// What can be pressed, and what is selected.
    pub const ACCENT: AdaptiveColor = c(0x4F5BD5, 0x9AA4F7);
    /// The primary button's fill.
    pub const ACCENT_FILL: AdaptiveColor = c(0x4F5BD5, 0x8F9AF2);
    /// Text and icons on the accent fill.
    pub const ON_ACCENT: AdaptiveColor = c(0xFFFFFF, 0x0F1230);
    /// A quiet accent wash: tonal buttons, the selected segment.
    pub const ACCENT_SOFT: AdaptiveColor = c(0xECEEFD, 0x262B4F);

    /// Destructive actions and errors.
    pub const DANGER: AdaptiveColor = c(0xC9364A, 0xFF7A86);
    pub const DANGER_SOFT: AdaptiveColor = c(0xFCEBED, 0x3A1F25);
    /// Estimates to check.
    pub const CAUTION: AdaptiveColor = c(0xA1620A, 0xF2B45A);
    pub const CAUTION_SOFT: AdaptiveColor = c(0xFDF2E1, 0x372B16);
    /// Done, connected.
    pub const POSITIVE: AdaptiveColor = c(0x1C7F55, 0x5DD39E);

    /// Energy from protein.
    pub const PROTEIN: AdaptiveColor = c(0xDE5479, 0xF27C9B);
    /// Energy from carbohydrates.
    pub const CARBS: AdaptiveColor = c(0xE29A2E, 0xF3BD5E);
    /// Energy from fat.
    pub const FAT: AdaptiveColor = c(0x2E9C92, 0x58C6BB);
    /// Energy the macronutrients do not explain.
    pub const OTHER: AdaptiveColor = c(0xB7BDCA, 0x4D5465);
    /// The ring's empty track.
    pub const TRACK: AdaptiveColor = c(0xEDEFF4, 0x232733);

    /// The dim behind sheets.
    pub const SCRIM: AdaptiveColor = c(0x0B0D14, 0x000000);
    /// Behind photos while they load.
    pub const PHOTO_WELL: AdaptiveColor = c(0xE6E8EE, 0x1F232C);
    /// Text and marks over a photo, on [`MEDIA_SCRIM`].
    pub const ON_MEDIA: AdaptiveColor = c(0xFFFFFF, 0xFFFFFF);
    /// The shade that keeps text over a photo readable.
    pub const MEDIA_SCRIM: AdaptiveColor = c(0x0A0C12, 0x05060A);
}

/// Corner radii, from the largest surfaces down.
pub mod radius {
    /// Sheets' top corners.
    pub const SHEET: f32 = 28.0;
    /// Cards and grouped lists.
    pub const CARD: f32 = 22.0;
    /// The meal photo.
    pub const PHOTO: f32 = 18.0;
    /// Buttons and fields.
    pub const CONTROL: f32 = 14.0;
    /// Small controls: chips, steppers, thumbnails.
    pub const SMALL: f32 = 10.0;
    /// Badges.
    pub const BADGE: f32 = 6.0;
}

/// Spacing that is not on the 4 pt scale's methods: the page's gutter.
pub mod space {
    /// The page's leading and trailing inset on phones.
    pub const GUTTER: f32 = 20.0;
    /// A card's inset.
    pub const CARD: f32 = 18.0;
}

/// Control heights (touch: at least 44 pt).
pub mod size {
    /// The main actions of a screen.
    pub const LARGE: f32 = 56.0;
    /// Ordinary buttons and fields.
    pub const MEDIUM: f32 = 48.0;
    /// Compact buttons inside rows and cards (44 pt hit area).
    pub const SMALL: f32 = 36.0;
    /// The touch target every pressable keeps.
    pub const TOUCH: f32 = 44.0;
}

/// Text roles: size (pt), line height (pt) and weight.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    /// The day's energy figure.
    Display,
    /// A page's title.
    LargeTitle,
    /// A sheet's or card's title.
    Title,
    /// Row titles and emphasized values.
    Headline,
    /// Copy.
    Body,
    /// Secondary copy.
    Callout,
    /// Metadata.
    Subhead,
    /// Units, badges, captions.
    Caption,
}

impl Type {
    /// Size, line height and weight (100–900).
    pub const fn metrics(self) -> (f32, f32, u16) {
        match self {
            Type::Display => (34.0, 38.0, 650),
            Type::LargeTitle => (30.0, 36.0, 700),
            Type::Title => (20.0, 26.0, 650),
            Type::Headline => (16.0, 22.0, 600),
            Type::Body => (16.0, 23.0, 400),
            Type::Callout => (15.0, 21.0, 400),
            Type::Subhead => (14.0, 19.0, 450),
            Type::Caption => (12.5, 16.0, 550),
        }
    }
}

/// Motion: durations in ms, curves and springs. Reduced motion turns
/// every one of them off ([`super::motion::reduced`]).
pub mod motion {
    use super::{Easing, Spring, Timing};

    /// A hover wash, a color change.
    pub const INSTANT: f32 = 120.0;
    /// A press, a control's state.
    pub const FAST: f32 = 180.0;
    /// Moving into place: a selection sliding, a glyph swapping.
    pub const BASE: f32 = 240.0;
    /// Reveals: a sheet's content, a result arriving.
    pub const SLOW: f32 = 360.0;
    /// Unhurried entrances: a list's wave, the ring filling.
    pub const SLOWER: f32 = 520.0;

    /// Rows arriving one after another, this far apart (capped at 8).
    pub const STAGGER: f32 = 45.0;
    /// How far arriving content rises, in points.
    pub const RISE: f32 = 10.0;

    /// Content arriving.
    pub const ENTER: Timing = Timing::new(SLOW, Easing::EaseOut);
    /// Sinking under the finger and back: quick, critically damped.
    pub const PRESS: Spring = Spring {
        stiffness: 520.0,
        damping: 36.0,
        mass: 1.0,
        velocity: None,
        frame_rate: None,
    };
    /// How far a pressed button shrinks.
    pub const PRESS_SCALE: f32 = 0.97;
    /// How far a pressed icon button shrinks.
    pub const PRESS_SCALE_ICON: f32 = 0.92;
}
