//! The app's design tokens, the only place raw colors and sizes live.
//!
//! "精密仪表 · Instrument": one plane, one accent, numbers first. A quiet
//! near-white (or near-black) canvas, content grouped by space and hairlines
//! rather than lifted cards, and a single cobalt accent reserved for the one
//! action of a screen and for "now" (the chosen tab, today, the latest
//! point). Money stays in neutral ink, gains and losses included. Every
//! color is an `AdaptiveColor`, so light and dark switch natively.

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

    /// The page: a quiet near-white / near-black.
    pub const CANVAS: AdaptiveColor = c(0xFAFAF8, 0x0B0B0C);
    /// Objects on the page: sheets, the rows of a group, a pending draft.
    pub const SURFACE: AdaptiveColor = c(0xFFFFFF, 0x151517);
    /// A well inside a surface: detail rows, chips, quiet buttons.
    pub const SURFACE_2: AdaptiveColor = c(0xF3F3F0, 0x1C1C1F);
    /// Fields and tracks.
    pub const SUNKEN: AdaptiveColor = c(0xEDEDEA, 0x19191C);
    /// Hairlines.
    pub const LINE: AdaptiveColor = c(0xE6E6E2, 0x26262A);
    /// Stronger edges: unchecked boxes, the grabber.
    pub const LINE_STRONG: AdaptiveColor = c(0xD1D1CC, 0x3C3C41);

    /// Titles and figures.
    pub const INK: AdaptiveColor = c(0x111113, 0xF2F2F0);
    /// Copy.
    pub const BODY: AdaptiveColor = c(0x2B2B2F, 0xD8D8D5);
    /// Secondary text.
    pub const MUTED: AdaptiveColor = c(0x6B6B70, 0x96969B);
    /// Tertiary marks and inactive controls; readable secondary text uses MUTED.
    pub const FAINT: AdaptiveColor = c(0xA1A1A6, 0x5A5A5F);

    /// The accent: cobalt, for the one action of a screen and for "now".
    pub const ACCENT: AdaptiveColor = c(0x2F5BEA, 0x7C9BFF);
    /// The accent as text or a glyph on light fills (the soft platter
    /// included), a step deeper so small labels keep their contrast.
    pub const ACCENT_INK: AdaptiveColor = c(0x2448C8, 0x9FB5FF);
    /// A soft accent fill: the chosen tab's platter, an accent chip.
    pub const ACCENT_SOFT: AdaptiveColor = c(0xE1E6FB, 0x1B2140);

    /// The primary action's fill: the accent.
    pub const ACTION: AdaptiveColor = ACCENT;
    /// Its pressed fill.
    pub const ACTION_PRESSED: AdaptiveColor = c(0x2449C9, 0x6A88F0);
    /// The top of its sheen.
    pub const ACTION_SHEEN: AdaptiveColor = c(0x4A73F5, 0x93AEFF);
    /// Text and icons on the action fill.
    pub const ON_ACTION: AdaptiveColor = c(0xFFFFFF, 0x0B0B0C);

    /// The tint of floating glass (the dock and its capture button).
    pub const GLASS: AdaptiveColor = c(0xF6F6F4, 0x222226);
    /// Secondary navigation text over translucent material (not ordinary surfaces).
    pub const ON_GLASS_MUTED: AdaptiveColor = c(0x45454A, 0xB8B8BD);
    /// Reflected light on the edge of a floating material.
    pub const GLASS_EDGE: AdaptiveColor = AdaptiveColor {
        light: super::rgba(0xFFFFFFC8).to_hsla(),
        dark: super::rgba(0xFFFFFF1F).to_hsla(),
    };

    /// Destructive actions and errors.
    pub const DANGER: AdaptiveColor = c(0xB0262F, 0xFF6369);
    pub const DANGER_SOFT: AdaptiveColor = c(0xFCEBEB, 0x3A1618);
    /// Estimates to check.
    pub const CAUTION: AdaptiveColor = c(0x8A5810, 0xFFC046);
    pub const CAUTION_SOFT: AdaptiveColor = c(0xFFF3DA, 0x372809);
    /// Done, connected.
    pub const POSITIVE: AdaptiveColor = c(0x1F7350, 0x4CC38A);

    /// Energy from protein: the full accent. The macronutrients are three
    /// steps of one accent ramp, so the ring reads as one quiet figure.
    pub const PROTEIN: AdaptiveColor = ACCENT;
    /// Energy from carbohydrates: the accent at about 55%.
    pub const CARBS: AdaptiveColor = c(0x8AA3F0, 0x495A92);
    /// Energy from fat: the accent at about 26%.
    pub const FAT: AdaptiveColor = c(0xC5D1F4, 0x2E375A);
    /// A logged day in the month calendar at its fullest, from the same
    /// accent ramp; lighter days fade it toward the surface.
    pub const HEAT: AdaptiveColor = c(0x9FB3F2, 0x3E4E85);
    /// The ring's empty track.
    pub const TRACK: AdaptiveColor = SUNKEN;

    /// Behind modal surfaces. The alpha is part of the material on both hosts.
    pub const SCRIM: AdaptiveColor = AdaptiveColor {
        light: super::rgba(0x0A0A0B4D).to_hsla(),
        dark: super::rgba(0x0000008C).to_hsla(),
    };
    /// Behind photos while they load.
    pub const PHOTO_WELL: AdaptiveColor = c(0xE6E6E2, 0x1C1C1F);
    /// Text and marks over a photo, on [`MEDIA_SCRIM`].
    pub const ON_MEDIA: AdaptiveColor = c(0xFFFFFF, 0xFFFFFF);
    /// The shade that keeps text over a photo readable.
    pub const MEDIA_SCRIM: AdaptiveColor = c(0x050506, 0x050506);
}

/// Corner radii, from the largest surfaces down, concentric where they
/// nest (an inner radius is the outer one less the padding). Controls are
/// pills.
pub mod radius {
    /// Sheets' top corners and the content rising over a photo.
    pub const SHEET: f32 = 28.0;
    /// Cards.
    pub const CARD: f32 = 20.0;
    /// Wells inside cards: tiles, detail groups.
    pub const WELL: f32 = 14.0;
    /// Fields.
    pub const FIELD: f32 = 12.0;
    /// Photo thumbnails.
    pub const THUMB: f32 = 12.0;
    /// Small marks.
    pub const BADGE: f32 = 6.0;
}

/// Spacing that is not on the 4 pt scale's methods.
pub mod space {
    /// The page's leading and trailing inset on phones.
    pub const GUTTER: f32 = 20.0;
    /// A card's inset.
    pub const CARD: f32 = 18.0;
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
    /// text (muted labels and the accent) keeps 4.5:1 over a black or white
    /// backdrop at this opacity.
    pub const DOCK_OPACITY: f32 = 0.84;
    pub const DOCK_BLUR: f32 = 24.0;
    /// Readable even over an entirely white photo, with or without blur.
    pub const MEDIA_OPACITY: f32 = 0.64;
    pub const MEDIA_PRESSED_OPACITY: f32 = 0.74;
    pub const EDGE: f32 = 0.75;
}

/// Text roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    /// The one headline number of a page: large and light.
    Display,
    /// A section's or a record's lead figure: light, a step under Display.
    Lead,
    /// A page's title.
    LargeTitle,
    /// Sheet titles and empty-state headings (sections use Headline).
    Title,
    /// Figures in cards and tiles.
    Figure,
    /// Row titles, buttons, section headers.
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
    /// Size, line height, weight (100–900) and tracking, in points. Large
    /// numbers are light and small labels medium, so the figures lead
    /// without shouting.
    pub const fn metrics(self) -> (f32, f32, u16, f32) {
        match self {
            Type::Display => (52.0, 58.0, 300, -2.0),
            Type::Lead => (34.0, 40.0, 300, -1.2),
            Type::LargeTitle => (30.0, 36.0, 600, -0.7),
            Type::Title => (20.0, 26.0, 600, -0.2),
            Type::Figure => (22.0, 28.0, 400, -0.4),
            Type::Headline => (16.0, 22.0, 600, -0.1),
            Type::Body => (15.5, 22.0, 400, 0.0),
            Type::Callout => (14.5, 20.0, 400, 0.0),
            Type::Subhead => (13.0, 18.0, 500, 0.0),
            Type::Caption => (12.0, 16.0, 500, 0.1),
        }
    }
}

/// Shadows belong only to what floats; everything else separates by tone
/// and hairlines.
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

    /// Just the contact at the foot of a raised control or pending draft.
    pub const CONTACT: [BoxShadow; 1] = [layer(1.0, 2.0, 0.0, 0x1111130A)];
    /// The accent reflecting under a primary action, localized to its base.
    pub const ACTION: [BoxShadow; 2] = [CONTACT[0], layer(5.0, 10.0, -4.0, 0x2F5BEA38)];
    /// A neutral overlay floats in one direction, clear of the reading surface.
    pub const FLOAT: [BoxShadow; 2] = [CONTACT[0], layer(8.0, 18.0, -6.0, 0x1111131A)];
    /// The dock's lifted lens.
    pub const LENS: [BoxShadow; 1] = [layer(6.0, 16.0, -6.0, 0x1111131A)];
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
    /// The dock's lens lifting under the finger and settling back (a
    /// 250 ms critically damped spring).
    pub const LIFT: Spring = Spring {
        stiffness: 631.7,
        damping: 50.3,
        mass: 1.0,
        velocity: None,
        frame_rate: None,
    };
    /// The lens's jelly: underdamped (ζ 0.4), so a stretched lens wobbles
    /// once into shape.
    pub const JELLY: Spring = Spring {
        stiffness: 100.0,
        damping: 8.0,
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
