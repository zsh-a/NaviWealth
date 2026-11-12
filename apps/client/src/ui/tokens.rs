//! Runtime dimensions authored in theme.json; values include safe defaults.
use super::*;
pub fn number_font() -> String {
    theme()
        .font("font-number")
        .map(|s| s.to_string())
        .unwrap_or_else(|| "Manrope ExtraLight, sans-serif".into())
}
pub fn token(name: &str) -> f32 {
    theme().number(name).unwrap_or(match name {
        "type-page" => 25.0,
        "space-page" => 28.0,
        "type-section" => 16.0,
        "type-body" => 14.0,
        "type-balance" => 24.0,
        "type-record" => 34.0,
        "type-caption" | "space-control" => 12.0,
        "type-action" => 13.0,
        "type-expense" => 39.0,
        "type-income" => 20.0,
        "type-net-worth" => 43.0,
        "type-surplus" => 49.0,
        "type-mini" => 23.0,
        "type-amount-input" => 51.0,
        "space-page-narrow" => 24.0,
        "space-row" => 12.0,
        "space-group" => 28.0,
        "space-section" => 28.0,
        "control-height" => 48.0,
        "row-height" => 64.0,
        "header-height" => 76.0,
        "tab-height" => 60.0,
        "icon-size" => 20.0,
        "icon-stroke" => 1.5,
        "space-icon" => 12.0,
        "bar-height" => 4.0,
        "bar-allocation-height" => 14.0,
        "type-allocation" => 17.0,
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
        "spring-damping" => 34.0,
        "spring-mass" => 0.6,
        "category-height" => 56.0,
        "category-icon-size" => 16.0,
        _ => 0.0,
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn authored_type_dimensions_reach_runtime_as_numbers() {
        const MANROPE: nsh_core::element::FontAsset =
            nsh_core::prelude::asset!("fonts/manrope-latin-variable.woff2");
        assert_eq!(MANROPE.family, "Manrope ExtraLight");
        // nsh reserves `font-*` for family names. Dimension roles must not
        // silently disappear and fall back to Rust defaults after a theme edit.
        let theme = nsh_base::Theme::from_json(include_str!("../../theme.json")).unwrap();
        assert_eq!(theme.number("type-net-worth"), Some(43.0));
        assert_eq!(theme.number("type-body"), Some(14.0));
        assert_eq!(theme.number("space-row"), Some(12.0));
        assert_eq!(theme.number("opacity-pressed"), Some(0.82));
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
                ("data-investment", "secondary"),
                ("destructive", "card"),
                ("up", "card"),
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
