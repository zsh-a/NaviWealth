//! Body composition estimated from one scale measurement. The scale sends
//! only weight and impedance; everything here is computed locally with
//! published BIA formulas, never received as official
//! fields. Pure math: no I/O, no storage, no clock.

use serde::{Deserialize, Serialize};

/// Versioned estimating families. Experimental choices require usable BIA
/// input and never fall back to another family when outside their range.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Algorithm {
    #[default]
    Segal,
    Wu2015,
    Sun2003,
}

impl Algorithm {
    pub const ALL: [Self; 3] = [Self::Segal, Self::Wu2015, Self::Sun2003];

    pub const fn id(self) -> &'static str {
        match self {
            Self::Segal => "segal",
            Self::Wu2015 => "wu2015",
            Self::Sun2003 => "sun2003",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|algorithm| algorithm.id() == id)
    }

    /// Identifies exact BIA model metadata for grouping historical trends.
    /// The old BMI-only `deurenberg_bmi_fallback` deliberately returns None:
    /// it must not be merged into a resistance-based Segal series.
    pub fn from_model_id(id: &str) -> Option<Self> {
        match id {
            "segal_3a_male_lt20"
            | "segal_3b_male_ge20"
            | "segal_3c_female_lt30"
            | "segal_3d_female_ge30" => Some(Self::Segal),
            "wu2015_foot_to_foot_ffm" => Some(Self::Wu2015),
            "sun2003_table5_male_ffm_tbw" | "sun2003_table5_female_ffm_tbw" => Some(Self::Sun2003),
            _ => None,
        }
    }

    pub const fn experimental(self) -> bool {
        !matches!(self, Self::Segal)
    }
}

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

/// Selects a deterministic model without changing the legacy `estimate` path.
///
/// `resistance_ohm` from the AFU-WL ADC conversion is a **reference resistance
/// proxy**, not calibrated impedance Z or validated wrist-to-ankle resistance R.
/// Both new choices are therefore experimental on this device.
///
/// Wu: Table 3, <https://doi.org/10.1186/s12937-015-0041-0>, standing 50 kHz
/// foot-to-foot Z, healthy Asian subjects aged 16–75. We restrict to adults
/// 18–75, weight 39–125.5 kg and BMI 15.9–43.1 (Results' observed range; the
/// abstract reports 15.8). Sun: final race-combined Table 5, AJCN 77:331–340,
/// <https://doi.org/10.1093/ajcn/77.2.331>, supine 50 kHz wrist-to-ankle R,
/// sample aged 12–94; our adult subset is 18–94. Sun gives no hard weight or
/// height limits, so only the existing profile height band 80–230 cm applies.
/// These guards do not establish calibration or population validity.
///
/// New models reject unusable predictions rather than clamping them. Muscle
/// remains a coarse lean-minus-assumed-bone derivation. Wu water remains 70%
/// of lean share; Sun water uses its independent TBW equation (litres treated
/// as kilograms for the displayed percentage). Neither is a direct measurement.
pub fn estimate_with_algorithm(
    weight_kg: f64,
    height_cm: f64,
    age_years: u16,
    sex: Sex,
    resistance_ohm: Option<f64>,
    algorithm: Algorithm,
) -> Option<BodyMetrics> {
    if algorithm == Algorithm::Segal {
        return estimate(weight_kg, height_cm, age_years, sex, resistance_ohm);
    }
    if !weight_kg.is_finite()
        || weight_kg <= 0.0
        || !height_cm.is_finite()
        || !(80.0..=230.0).contains(&height_cm)
    {
        return None;
    }
    let resistance = resistance_ohm
        .filter(|r| r.is_finite() && (MIN_RESISTANCE_OHM..=MAX_RESISTANCE_OHM).contains(r))?;
    let index = height_cm * height_cm / resistance;
    let (fat_free, water_litres, model) = match algorithm {
        Algorithm::Segal => unreachable!(),
        Algorithm::Wu2015 => {
            let bmi = weight_kg / (height_cm / 100.0).powi(2);
            if !(18..=75).contains(&age_years)
                || !(39.0..=125.5).contains(&weight_kg)
                || !(15.9..=43.1).contains(&bmi)
            {
                return None;
            }
            (
                13.055 + 0.204 * weight_kg + 0.394 * index - 0.136 * f64::from(age_years)
                    + 8.125 * f64::from(sex == Sex::Male),
                None,
                "wu2015_foot_to_foot_ffm",
            )
        }
        Algorithm::Sun2003 => {
            if !(18..=94).contains(&age_years) {
                return None;
            }
            // Exact coefficients printed in the PRIMARY Table 5, p.336.
            // Do not substitute higher precision coefficients from reviews.
            // Original PDF copy (visually verified):
            // https://www.egofit.de/wp-content/uploads/2012/09/Nutrition._2005_Feb_21_2_161-9.pdf
            match sex {
                Sex::Male => (
                    -10.68 + 0.65 * index + 0.26 * weight_kg + 0.02 * resistance,
                    Some(1.20 + 0.45 * index + 0.18 * weight_kg),
                    "sun2003_table5_male_ffm_tbw",
                ),
                Sex::Female => (
                    -9.53 + 0.69 * index + 0.17 * weight_kg + 0.02 * resistance,
                    Some(3.75 + 0.45 * index + 0.11 * weight_kg),
                    "sun2003_table5_female_ffm_tbw",
                ),
            }
        }
    };
    let low = match sex {
        Sex::Male => MIN_BODY_FAT_PERCENT.0,
        Sex::Female => MIN_BODY_FAT_PERCENT.1,
    };
    let body_fat = 100.0 * (weight_kg - fat_free) / weight_kg;
    if !fat_free.is_finite() || !(low..=MAX_BODY_FAT_PERCENT).contains(&body_fat) {
        return None;
    }
    // An independent TBW prediction cannot exceed its FFM prediction.
    if water_litres.is_some_and(|water| !water.is_finite() || water <= 0.0 || water > fat_free) {
        return None;
    }
    let body_fat = rounded_1(body_fat);
    let lean = 100.0 - body_fat;
    let bone = match sex {
        Sex::Male => BONE_PERCENT.0,
        Sex::Female => BONE_PERCENT.1,
    };
    let metrics = BodyMetrics {
        body_fat_percent: body_fat,
        muscle_percent: rounded_1(lean - bone),
        water_percent: rounded_1(
            water_litres.map_or(lean * 0.70, |water| 100.0 * water / weight_kg),
        ),
        resistance_ohm: Some(rounded_2(resistance)),
        model: model.into(),
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
    fn algorithm_ids_are_stable_and_unknown_ids_are_not_defaults() {
        assert_eq!(Algorithm::default(), Algorithm::Segal);
        for algorithm in Algorithm::ALL {
            assert_eq!(Algorithm::from_id(algorithm.id()), Some(algorithm));
            let json = format!("\"{}\"", algorithm.id());
            assert_eq!(serde_json::to_string(&algorithm).unwrap(), json);
            assert_eq!(serde_json::from_str::<Algorithm>(&json).unwrap(), algorithm);
            assert_eq!(algorithm.experimental(), algorithm != Algorithm::Segal);
        }
        for id in ["", "unknown", "Wu2015", " segal", "sun_2003"] {
            assert_eq!(Algorithm::from_id(id), None);
            assert!(serde_json::from_str::<Algorithm>(&format!("\"{id}\"")).is_err());
        }
    }

    #[test]
    fn model_metadata_only_groups_exact_bia_families_and_keeps_bmi_fallback_separate() {
        for model in [
            "segal_3a_male_lt20",
            "segal_3b_male_ge20",
            "segal_3c_female_lt30",
            "segal_3d_female_ge30",
        ] {
            assert_eq!(Algorithm::from_model_id(model), Some(Algorithm::Segal));
        }
        assert_eq!(
            Algorithm::from_model_id("wu2015_foot_to_foot_ffm"),
            Some(Algorithm::Wu2015)
        );
        for model in [
            "sun2003_table5_male_ffm_tbw",
            "sun2003_table5_female_ffm_tbw",
        ] {
            assert_eq!(Algorithm::from_model_id(model), Some(Algorithm::Sun2003));
        }
        for model in [
            "",
            "unknown",
            "deurenberg_bmi_fallback",
            "segal",
            "segal_3e",
            "wu2015",
            "sun2003_table5_male_ffm_tbw_v2",
        ] {
            assert_eq!(Algorithm::from_model_id(model), None);
        }
    }

    #[test]
    fn explicit_segal_preserves_legacy_formulas_rounding_clamps_and_fallback() {
        for sex in [Sex::Male, Sex::Female] {
            for resistance in [None, Some(50.0), Some(506.0), Some(1500.0), Some(f64::NAN)] {
                for weight in [0.0, 58.05, 90.0, 400.0] {
                    assert_eq!(
                        estimate_with_algorithm(
                            weight,
                            170.0,
                            23,
                            sex,
                            resistance,
                            Algorithm::Segal
                        ),
                        estimate(weight, 170.0, 23, sex, resistance)
                    );
                }
            }
        }
    }

    #[test]
    fn wu2015_table3_both_sexes_match_independent_decimal_fixtures() {
        // Hand-evaluated Table 3 inputs (not published participant records):
        // W=80,H=175,Z=500,age=30,M -> FFM=57.5525, BF=28.059375%.
        // W=60,H=165,Z=600,age=40,F -> FFM=37.73275, BF=37.112083...%.
        for (weight, height, age, sex, resistance, fat, muscle, water) in [
            (80.0, 175.0, 30, Sex::Male, 500.0, 28.1, 67.4, 50.3),
            (60.0, 165.0, 40, Sex::Female, 600.0, 37.1, 58.9, 44.0),
        ] {
            let metrics = estimate_with_algorithm(
                weight,
                height,
                age,
                sex,
                Some(resistance),
                Algorithm::Wu2015,
            )
            .unwrap();
            assert_eq!(metrics.body_fat_percent, fat);
            assert_eq!(metrics.muscle_percent, muscle);
            assert_eq!(metrics.water_percent, water);
            assert_eq!(metrics.resistance_ohm, Some(resistance));
            assert_eq!(metrics.model, "wu2015_foot_to_foot_ffm");
        }
    }

    #[test]
    fn sun2003_primary_table5_ffm_and_independent_tbw_match_decimal_fixtures() {
        // Exact printed Table 5, manually evaluated synthetic inputs:
        // M: W=80,H=175,R=500 -> FFM=59.9325 kg, TBW=43.1625 L.
        // F: W=60,H=165,R=550 -> FFM=45.825 kg, TBW=32.625 L.
        // These distinguish Table 5 from preliminary Table 4 and reviews'
        // higher precision variants, notably R's 0.02 vs 0.015 coefficient.
        for (weight, height, sex, resistance, fat, muscle, water, model) in [
            (
                80.0,
                175.0,
                Sex::Male,
                500.0,
                25.1,
                70.4,
                54.0,
                "sun2003_table5_male_ffm_tbw",
            ),
            (
                60.0,
                165.0,
                Sex::Female,
                550.0,
                23.6,
                72.4,
                54.4,
                "sun2003_table5_female_ffm_tbw",
            ),
        ] {
            let metrics = estimate_with_algorithm(
                weight,
                height,
                30,
                sex,
                Some(resistance),
                Algorithm::Sun2003,
            )
            .unwrap();
            assert_eq!(metrics.body_fat_percent, fat);
            assert_eq!(metrics.muscle_percent, muscle);
            assert_eq!(metrics.water_percent, water);
            assert_ne!(metrics.water_percent, rounded_1((100.0 - fat) * 0.70));
            assert_eq!(metrics.model, model);
            // Sun's selected Table 5 equations do not use age as a predictor.
            assert_eq!(
                Some(metrics),
                estimate_with_algorithm(
                    weight,
                    height,
                    70,
                    sex,
                    Some(resistance),
                    Algorithm::Sun2003,
                )
            );
        }
    }

    #[test]
    fn experimental_models_need_adult_inputs_and_usable_resistance_without_fallback() {
        for algorithm in [Algorithm::Wu2015, Algorithm::Sun2003] {
            for resistance in [
                None,
                Some(0.0),
                Some(99.9),
                Some(1500.1),
                Some(f64::INFINITY),
                Some(f64::NAN),
            ] {
                assert!(
                    estimate_with_algorithm(80.0, 175.0, 30, Sex::Male, resistance, algorithm)
                        .is_none()
                );
            }
            for age in [0, 5, 16, 17, 95, 120] {
                assert!(
                    estimate_with_algorithm(80.0, 175.0, age, Sex::Male, Some(500.0), algorithm)
                        .is_none()
                );
            }
            for (weight, height) in [
                (0.0, 175.0),
                (f64::NAN, 175.0),
                (80.0, f64::INFINITY),
                (80.0, 79.9),
                (80.0, 230.1),
            ] {
                assert!(
                    estimate_with_algorithm(weight, height, 30, Sex::Male, Some(500.0), algorithm)
                        .is_none()
                );
            }
            for age in [18, 75] {
                assert!(
                    estimate_with_algorithm(80.0, 175.0, age, Sex::Male, Some(500.0), algorithm)
                        .is_some()
                );
            }
            // Numerically impossible FFM must be refused, never clamped.
            assert!(
                estimate_with_algorithm(80.0, 175.0, 30, Sex::Male, Some(100.0), algorithm)
                    .is_none()
            );
        }
        for age in [76, 94] {
            assert!(
                estimate_with_algorithm(
                    80.0,
                    175.0,
                    age,
                    Sex::Male,
                    Some(500.0),
                    Algorithm::Wu2015
                )
                .is_none()
            );
            assert!(
                estimate_with_algorithm(
                    80.0,
                    175.0,
                    age,
                    Sex::Male,
                    Some(500.0),
                    Algorithm::Sun2003
                )
                .is_some()
            );
        }
        for (weight, height) in [(38.9, 150.0), (125.6, 180.0), (50.0, 190.0), (120.0, 160.0)] {
            assert!(
                estimate_with_algorithm(
                    weight,
                    height,
                    30,
                    Sex::Female,
                    Some(600.0),
                    Algorithm::Wu2015
                )
                .is_none()
            );
        }
        for (weight, height) in [(39.0, 150.0), (125.5, 180.0)] {
            assert!(
                estimate_with_algorithm(
                    weight,
                    height,
                    30,
                    Sex::Female,
                    Some(700.0),
                    Algorithm::Wu2015
                )
                .is_some()
            );
        }
    }

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
