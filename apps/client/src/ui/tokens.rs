//! Business type roles mapped to the NSH/Tailwind scale; no custom size theme overrides.
use super::*;
pub fn number_font() -> String {
    theme()
        .font("font-sans")
        .map(|s| s.to_string())
        .unwrap_or_else(|| "Manrope ExtraLight, sans-serif".into())
}
pub fn token(name: &str) -> f32 {
    theme().number(name).unwrap_or(match name {
        "type-page" => 24.0,
        "space-page" => 16.0,
        "type-section" => 16.0,
        "type-body" => 16.0,
        "type-balance" => 24.0,
        "type-record" => 30.0,
        "type-caption" | "space-control" => 12.0,
        "type-action" => 14.0,
        "type-expense" => 36.0,
        "type-income" => 20.0,
        "type-net-worth" => 36.0,
        "type-surplus" => 36.0,
        "type-mini" => 24.0,
        "type-amount-input" => 48.0,
        "space-page-narrow" => 16.0,
        "space-row" => 12.0,
        "space-group" => 24.0,
        "space-section" => 24.0,
        "control-height" => 44.0,
        "row-height" => 56.0,
        "header-height" => 56.0,
        "tab-height" => 56.0,
        "icon-size" => 20.0,
        "icon-stroke" => 1.5,
        "space-icon" => 12.0,
        "bar-height" => 4.0,
        "bar-allocation-height" => 14.0,
        "type-allocation" => 18.0,
        "icon-check-size" => 12.0,
        "radius-sheet" => 22.0,
        "opacity-scrim" => 0.28,
        "tracking-display" => -1.5,
        "focus-width" => 2.0,
        "opacity-pressed" => 0.82,
        "opacity-disabled" => 0.45,
        "motion-layout-ms" => 180.0,
        "motion-press-ms" => 160.0,
        "motion-enter" => 8.0,
        "spring-stiffness" => 420.0,
        "spring-damping" => 30.0,
        "spring-mass" => 0.6,
        "category-height" => 56.0,
        "category-icon-size" => 16.0,
        _ => 0.0,
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn official_theme_defaults_and_branded_font_are_preserved() {
        const MANROPE: nsh_core::element::FontAsset =
            nsh_core::prelude::asset!("fonts/manrope-latin-variable.woff2");
        assert_eq!(MANROPE.family, "Manrope ExtraLight");
        let theme = nsh_base::Theme::from_json(include_str!("../../theme.json")).unwrap();
        assert_eq!(theme.number("type-net-worth"), None);
        assert_eq!(theme.number("space-row"), None);
        assert!(theme.color("chart-1").is_some());
        assert!(theme.color("chart-5").is_some());
    }

    #[test]
    fn enabled_financial_text_meets_contrast_on_its_actual_surfaces() {
        let json: serde_json::Value =
            serde_json::from_str(include_str!("../../theme.json")).unwrap();
        let luminance = |hex: &str| {
            [0.2126, 0.7152, 0.0722]
                .iter()
                .enumerate()
                .map(|(i, weight)| {
                    let n =
                        u8::from_str_radix(&hex[1 + i * 2..3 + i * 2], 16).unwrap() as f64 / 255.0;
                    weight
                        * if n <= 0.04045 {
                            n / 12.92
                        } else {
                            ((n + 0.055) / 1.055).powf(2.4)
                        }
                })
                .sum::<f64>()
        };
        for mode in ["light", "dark"] {
            let colors = &json["cssVars"][mode];
            for (fg, bg) in [
                ("foreground", "background"),
                ("muted-foreground", "background"),
                ("muted-foreground", "card"),
                ("muted-foreground", "secondary"),
                ("chart-1", "secondary"),
                ("destructive", "card"),
                ("primary", "card"),
                ("primary-foreground", "primary"),
            ] {
                let a = luminance(colors[fg].as_str().unwrap());
                let b = luminance(colors[bg].as_str().unwrap());
                assert!(
                    (a.max(b) + 0.05) / (a.min(b) + 0.05) >= 4.5,
                    "{mode}: {fg}/{bg}"
                );
            }
        }
    }
}
