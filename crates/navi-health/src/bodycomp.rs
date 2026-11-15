//! Body composition estimated from one scale measurement. The scale sends
//! only weight and impedance; everything here is computed locally with
//! published BIA formulas (Segal, Deurenberg), never received as official
//! fields. Pure math: no I/O, no storage, no clock.

use serde::{Deserialize, Serialize};

/// Sex as the estimation formulas and the user profile need it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Sex {
    Male,
    Female,
}

/// The lowest and highest impedance accepted from a measurement, in ohms.
/// Readings outside this band are treated as absent, as the reference
/// implementation filters its raw ADC conversions.
pub const MIN_RESISTANCE_OHM: f64 = 100.0;
pub const MAX_RESISTANCE_OHM: f64 = 1500.0;

/// The body-fat share the formulas may claim, in percent, by sex.
const MIN_BODY_FAT_PERCENT: (f64, f64) = (3.0, 8.0); // (male, female)
const MAX_BODY_FAT_PERCENT: f64 = 60.0;

/// The fat-free share any formula result is clamped to, of body weight.
const MIN_FAT_FREE_SHARE: f64 = 0.35;
const MAX_FAT_FREE_SHARE: f64 = 0.97;

/// Bone share assumed by the muscle-rate derivation, in percent.
const BONE_PERCENT: (f64, f64) = (4.5, 4.0); // (male, female)

/// The three kept composition shares, in percent, with their provenance.
/// Estimates are stored as one JSON body per day (see the host's
/// `body_metrics` table), never mixed into the weight value itself.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BodyMetrics {
    pub body_fat_percent: f64,
    pub muscle_percent: f64,
    pub water_percent: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resistance_ohm: Option<f64>,
    /// The formula that produced the fat estimate, e.g. `segal_3a_male_lt20`.
    pub model: String,
}

impl BodyMetrics {
    /// Whether every share is finite and inside its accepted band.
    pub fn valid(&self) -> bool {
        let (low, _) = MIN_BODY_FAT_PERCENT;
        self.body_fat_percent.is_finite()
            && (low..=MAX_BODY_FAT_PERCENT).contains(&self.body_fat_percent)
            && (20.0..=95.0).contains(&self.muscle_percent)
            && (25.0..=80.0).contains(&self.water_percent)
            && self.resistance_ohm.is_none_or(|r| {
                r.is_finite() && (MIN_RESISTANCE_OHM..=MAX_RESISTANCE_OHM).contains(&r)
            })
            && !self.model.is_empty()
    }
}

/// Body mass index, rounded to two decimals; display-only, never stored.
/// Height is in centimetres and must be a plausible adult profile value.
pub fn bmi(weight_kg: f64, height_cm: u16) -> Option<f64> {
    if !weight_kg.is_finite() || weight_kg <= 0.0 || !(80..=230).contains(&height_cm) {
        return None;
    }
    let height_m = f64::from(height_cm) / 100.0;
    Some((weight_kg / (height_m * height_m) * 100.0).round() / 100.0)
}

/// Estimates the composition of one measurement. `resistance_ohm` outside
/// the accepted band counts as absent and falls back to the BMI-based
/// formula. Returns `None` unless weight and height are usable.
pub fn estimate(
    weight_kg: f64,
    height_cm: f64,
    age_years: u16,
    sex: Sex,
    resistance_ohm: Option<f64>,
) -> Option<BodyMetrics> {
    if !weight_kg.is_finite() || weight_kg <= 0.0 || !height_cm.is_finite() || height_cm <= 0.0 {
        return None;
    }
    let resistance = resistance_ohm
        .filter(|r| r.is_finite() && (MIN_RESISTANCE_OHM..=MAX_RESISTANCE_OHM).contains(r));
    let (body_fat, model) = match resistance {
        Some(resistance) => {
            let (fat_free, model) =
                segal_fat_free_mass(weight_kg, height_cm, age_years, sex, resistance);
            let fat_free = fat_free.clamp(
                weight_kg * MIN_FAT_FREE_SHARE,
                weight_kg * MAX_FAT_FREE_SHARE,
            );
            (100.0 * (weight_kg - fat_free) / weight_kg, model)
        }
        None => {
            let bmi_value = weight_kg / (height_cm / 100.0).powi(2);
            let male_bonus = f64::from(sex == Sex::Male);
            (
                1.20 * bmi_value + 0.23 * f64::from(age_years) - 10.8 * male_bonus - 5.4,
                "deurenberg_bmi_fallback".to_owned(),
            )
        }
    };
    let low = match sex {
        Sex::Male => MIN_BODY_FAT_PERCENT.0,
        Sex::Female => MIN_BODY_FAT_PERCENT.1,
    };
    let body_fat = rounded_1(body_fat.clamp(low, MAX_BODY_FAT_PERCENT));
    let lean = 100.0 - body_fat;
    let bone = match sex {
        Sex::Male => BONE_PERCENT.0,
        Sex::Female => BONE_PERCENT.1,
    };
    let metrics = BodyMetrics {
        body_fat_percent: body_fat,
        muscle_percent: rounded_1((lean - bone).clamp(20.0, 95.0)),
        water_percent: rounded_1((lean * 0.70).clamp(25.0, 80.0)),
        resistance_ohm: resistance.map(rounded_2),
        model,
    };
    metrics.valid().then_some(metrics)
}

/// The Segal equations: fat-free mass from impedance, chosen by sex and by
/// whether the first pass already implies a high fat share.
fn segal_fat_free_mass(
    weight_kg: f64,
    height_cm: f64,
    age_years: u16,
    sex: Sex,
    resistance_ohm: f64,
) -> (f64, String) {
    let height_sq = height_cm * height_cm;
    let age = f64::from(age_years);
    match sex {
        Sex::Male => {
            let ffm = 9.33285 + 0.000_663_60 * height_sq - 0.021_17 * resistance_ohm
                + 0.628_54 * weight_kg
                - 0.123_80 * age;
            if 100.0 * (weight_kg - ffm) / weight_kg < 20.0 {
                return (ffm, "segal_3a_male_lt20".to_owned());
            }
            (
                14.52435 + 0.000_885_80 * height_sq - 0.029_99 * resistance_ohm
                    + 0.426_88 * weight_kg
                    - 0.070_02 * age,
                "segal_3b_male_ge20".to_owned(),
            )
        }
        Sex::Female => {
            let ffm = 10.43485 + 0.000_646_02 * height_sq - 0.013_97 * resistance_ohm
                + 0.420_87 * weight_kg;
            if 100.0 * (weight_kg - ffm) / weight_kg < 30.0 {
                return (ffm, "segal_3c_female_lt30".to_owned());
            }
            (
                9.37938 + 0.000_911_86 * height_sq - 0.014_66 * resistance_ohm
                    + 0.299_90 * weight_kg
                    - 0.070_12 * age,
                "segal_3d_female_ge30".to_owned(),
            )
        }
    }
}

/// Shares are kept and shown to one decimal.
fn rounded_1(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

/// Impedance is kept to two decimals, as the reference implementation logs it.
fn rounded_2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segal_male_low_fat_matches_the_reference_reading() {
        // README example of the reference tool: male, 23, 170 cm, 506 ohm.
        let metrics = estimate(58.0, 170.0, 23, Sex::Male, Some(506.0)).unwrap();
        assert_eq!(metrics.body_fat_percent, 11.4);
        assert_eq!(metrics.muscle_percent, 84.1);
        assert_eq!(metrics.water_percent, 62.0);
        assert_eq!(metrics.resistance_ohm, Some(506.0));
        assert_eq!(metrics.model, "segal_3a_male_lt20");
        assert!(metrics.valid());
    }

    #[test]
    fn segal_switches_equation_when_the_first_pass_is_fatter() {
        let metrics = estimate(90.0, 170.0, 40, Sex::Male, Some(450.0)).unwrap();
        assert_eq!(metrics.body_fat_percent, 30.8);
        assert_eq!(metrics.model, "segal_3b_male_ge20");
    }

    #[test]
    fn segal_female_uses_her_own_equations_and_bone_share() {
        let metrics = estimate(55.0, 165.0, 25, Sex::Female, Some(480.0)).unwrap();
        assert_eq!(metrics.body_fat_percent, 19.2);
        assert_eq!(metrics.muscle_percent, 76.8);
        assert_eq!(metrics.water_percent, 56.6);
        assert_eq!(metrics.model, "segal_3c_female_lt30");
    }

    #[test]
    fn without_impedance_the_estimate_falls_back_to_bmi() {
        let metrics = estimate(80.0, 175.0, 30, Sex::Male, None).unwrap();
        assert_eq!(metrics.body_fat_percent, 22.0);
        assert_eq!(metrics.muscle_percent, 73.5);
        assert_eq!(metrics.water_percent, 54.6);
        assert_eq!(metrics.resistance_ohm, None);
        assert_eq!(metrics.model, "deurenberg_bmi_fallback");
    }

    #[test]
    fn impedance_outside_the_band_counts_as_absent() {
        let fallback = estimate(80.0, 175.0, 30, Sex::Male, Some(50.0)).unwrap();
        assert_eq!(fallback.model, "deurenberg_bmi_fallback");
        let high = estimate(80.0, 175.0, 30, Sex::Male, Some(2000.0)).unwrap();
        assert_eq!(high.model, "deurenberg_bmi_fallback");
    }

    #[test]
    fn implausible_formula_results_are_clamped_into_the_human_band() {
        // A minimal 100-ohm reading implies almost no fat; the fat-free
        // clamp and the male floor hold the estimate at 3.0 percent.
        let metrics = estimate(50.0, 170.0, 23, Sex::Male, Some(100.0)).unwrap();
        assert_eq!(metrics.body_fat_percent, 3.0);
        assert_eq!(metrics.model, "segal_3a_male_lt20");
    }

    #[test]
    fn unusable_measurements_have_no_estimate() {
        assert!(estimate(0.0, 170.0, 23, Sex::Male, Some(506.0)).is_none());
        assert!(estimate(f64::NAN, 170.0, 23, Sex::Male, Some(506.0)).is_none());
        assert!(estimate(58.0, 0.0, 23, Sex::Male, Some(506.0)).is_none());
    }

    #[test]
    fn bmi_rounds_to_two_decimals_and_needs_a_plausible_height() {
        assert_eq!(bmi(80.0, 175), Some(26.12));
        assert_eq!(bmi(58.0, 170), Some(20.07));
        assert_eq!(bmi(80.0, 0), None);
        assert_eq!(bmi(80.0, 300), None);
        assert_eq!(bmi(0.0, 175), None);
    }

    #[test]
    fn metrics_outside_the_human_band_are_refused() {
        let metrics = estimate(58.0, 170.0, 23, Sex::Male, Some(506.0)).unwrap();
        assert!(metrics.valid());
        let mut fat = metrics.clone();
        fat.body_fat_percent = 70.0;
        assert!(!fat.valid());
        let mut water = metrics.clone();
        water.water_percent = 10.0;
        assert!(!water.valid());
        let mut model = metrics.clone();
        model.model = String::new();
        assert!(!model.valid());
    }

    #[test]
    fn metrics_survive_a_json_round_trip() {
        let metrics = estimate(58.0, 170.0, 23, Sex::Male, Some(506.0)).unwrap();
        let json = serde_json::to_string(&metrics).unwrap();
        assert_eq!(serde_json::from_str::<BodyMetrics>(&json).unwrap(), metrics);
        assert!(json.contains("body_fat_percent"));
        assert!(json.contains("resistance_ohm"));
        let without = BodyMetrics {
            resistance_ohm: None,
            ..metrics.clone()
        };
        let json = serde_json::to_string(&without).unwrap();
        assert_eq!(serde_json::from_str::<BodyMetrics>(&json).unwrap(), without);
    }
}
