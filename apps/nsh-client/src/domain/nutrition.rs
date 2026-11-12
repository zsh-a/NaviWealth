//! Nutrients, foods and the arithmetic the app owns: amounts are always
//! `grams × per-100 g / 100`, computed here and never taken from a model.

use std::ops::{Add, AddAssign};

use serde::{Deserialize, Serialize};

/// The most edible weight one food may have, in grams.
pub const MAX_GRAMS: f64 = 5000.0;
/// The most energy 100 g of anything holds (pure fat is about 900 kcal).
pub const MAX_KCAL_PER_100G: f64 = 900.0;
/// The most grams of one macronutrient 100 g may hold.
pub const MAX_MACRO_PER_100G: f64 = 100.0;
/// Rounding slack for protein + carbs + fat per 100 g.
pub const MAX_MACRO_SUM_PER_100G: f64 = 105.0;
/// The longest food name kept, in characters.
pub const MAX_NAME_CHARS: usize = 80;
/// The most foods one meal holds.
pub const MAX_FOODS_PER_MEAL: usize = 30;

/// Atwater factors: kcal per gram of protein, carbohydrate and fat.
pub const KCAL_PER_G_PROTEIN: f64 = 4.0;
pub const KCAL_PER_G_CARBS: f64 = 4.0;
pub const KCAL_PER_G_FAT: f64 = 9.0;

/// Energy in kcal and macronutrients in grams: per 100 g of a food, or an
/// amount actually eaten.
#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct Nutrients {
    pub kcal: f64,
    pub protein: f64,
    pub carbs: f64,
    pub fat: f64,
}

impl Nutrients {
    /// Nothing.
    pub const ZERO: Nutrients = Nutrients {
        kcal: 0.0,
        protein: 0.0,
        carbs: 0.0,
        fat: 0.0,
    };

    /// A value of these four numbers.
    pub const fn new(kcal: f64, protein: f64, carbs: f64, fat: f64) -> Self {
        Self {
            kcal,
            protein,
            carbs,
            fat,
        }
    }

    /// Every number multiplied by `factor`.
    pub fn scaled(self, factor: f64) -> Self {
        Self {
            kcal: self.kcal * factor,
            protein: self.protein * factor,
            carbs: self.carbs * factor,
            fat: self.fat * factor,
        }
    }

    /// What `grams` of a food with these per-100 g values hold.
    pub fn for_grams(self, grams: f64) -> Self {
        self.scaled(grams / 100.0)
    }

    /// The energy the macronutrients account for (Atwater factors).
    pub fn macro_kcal(self) -> f64 {
        self.protein * KCAL_PER_G_PROTEIN
            + self.carbs * KCAL_PER_G_CARBS
            + self.fat * KCAL_PER_G_FAT
    }

    /// Whether these are plausible per-100 g values: finite, not negative,
    /// within physical limits.
    pub fn is_valid_per_100g(self) -> bool {
        let macros = [self.protein, self.carbs, self.fat];
        self.kcal.is_finite()
            && (0.0..=MAX_KCAL_PER_100G).contains(&self.kcal)
            && macros
                .iter()
                .all(|g| g.is_finite() && (0.0..=MAX_MACRO_PER_100G).contains(g))
            && macros.iter().sum::<f64>() <= MAX_MACRO_SUM_PER_100G
    }

    /// How the energy divides between the macronutrients, in kcal that sum
    /// to [`Self::kcal`] (what the ring draws). Energy the macronutrients do
    /// not explain (alcohol, fibre, rounding) is `other`; when they explain
    /// more than the total, their shares shrink to fit it.
    pub fn energy_split(self) -> EnergySplit {
        let total = self.kcal.max(0.0);
        let parts = [
            self.protein.max(0.0) * KCAL_PER_G_PROTEIN,
            self.carbs.max(0.0) * KCAL_PER_G_CARBS,
            self.fat.max(0.0) * KCAL_PER_G_FAT,
        ];
        let explained: f64 = parts.iter().sum();
        if total <= 0.0 {
            return EnergySplit::default();
        }
        let (scale, other) = if explained > total {
            (total / explained, 0.0)
        } else {
            (1.0, total - explained)
        };
        EnergySplit {
            protein: parts[0] * scale,
            carbs: parts[1] * scale,
            fat: parts[2] * scale,
            other,
        }
    }
}

impl Add for Nutrients {
    type Output = Nutrients;

    fn add(self, other: Nutrients) -> Nutrients {
        Nutrients {
            kcal: self.kcal + other.kcal,
            protein: self.protein + other.protein,
            carbs: self.carbs + other.carbs,
            fat: self.fat + other.fat,
        }
    }
}

impl AddAssign for Nutrients {
    fn add_assign(&mut self, other: Nutrients) {
        *self = *self + other;
    }
}

impl std::iter::Sum for Nutrients {
    fn sum<I: Iterator<Item = Nutrients>>(iter: I) -> Nutrients {
        iter.fold(Nutrients::ZERO, Add::add)
    }
}

/// Energy by macronutrient, in kcal ([`Nutrients::energy_split`]).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct EnergySplit {
    pub protein: f64,
    pub carbs: f64,
    pub fat: f64,
    pub other: f64,
}

impl EnergySplit {
    /// The whole.
    pub fn total(self) -> f64 {
        self.protein + self.carbs + self.fat + self.other
    }

    /// Each part's share of the whole, from 0 to 1 (all 0 for nothing).
    pub fn shares(self) -> [f64; 4] {
        let total = self.total();
        if total <= 0.0 {
            return [0.0; 4];
        }
        [
            self.protein / total,
            self.carbs / total,
            self.fat / total,
            self.other / total,
        ]
    }
}

/// Where a food's per-100 g values came from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FoodSource {
    /// A USDA FoodData Central record of the bundled catalog.
    Catalog { fdc_id: String },
    /// A vision model's estimate.
    Estimate,
    /// Entered or corrected by the user.
    Manual,
}

/// How sure the model said it was of a portion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Confidence {
    High,
    Medium,
    Low,
}

impl Confidence {
    /// From the model's word for it; anything else is no answer.
    pub fn parse(word: &str) -> Option<Self> {
        match word.trim().to_ascii_lowercase().as_str() {
            "high" => Some(Self::High),
            "medium" => Some(Self::Medium),
            "low" => Some(Self::Low),
            _ => None,
        }
    }
}

/// One food of a meal: what it is, how much was eaten, and its nutrients
/// per 100 g as prepared.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Food {
    /// Identity within the app (list keys, edits); not shown.
    pub id: u64,
    pub name: String,
    /// Edible weight eaten, on the same cooked/raw basis as `per_100g`.
    pub grams: f64,
    pub per_100g: Nutrients,
    pub source: FoodSource,
    /// The model's confidence in the portion, until the user edits it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub confidence: Option<Confidence>,
    /// The weight first estimated, the reference of the portion shortcuts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub estimated_grams: Option<f64>,
}

/// Why a food cannot be saved.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FoodError {
    /// No name.
    NameMissing,
    /// The weight is not a number in (0, [`MAX_GRAMS`]].
    Grams,
    /// The per-100 g values are not plausible.
    Nutrients,
}

impl Food {
    /// What was eaten: `grams × per_100g / 100`.
    pub fn amount(&self) -> Nutrients {
        self.per_100g.for_grams(self.grams)
    }

    /// Whether it can be saved, and the first reason it cannot.
    pub fn validate(&self) -> Result<(), FoodError> {
        if self.name.trim().is_empty() {
            return Err(FoodError::NameMissing);
        }
        if !valid_grams(self.grams) {
            return Err(FoodError::Grams);
        }
        if !self.per_100g.is_valid_per_100g() {
            return Err(FoodError::Nutrients);
        }
        Ok(())
    }

    /// Whether the model doubted this portion and the user has not looked.
    pub fn needs_check(&self) -> bool {
        self.confidence == Some(Confidence::Low)
    }
}

/// Whether `grams` is a weight a food may have.
pub fn valid_grams(grams: f64) -> bool {
    grams.is_finite() && grams > 0.0 && grams <= MAX_GRAMS
}

/// `name` trimmed and cut to [`MAX_NAME_CHARS`] characters.
pub fn clean_name(name: &str) -> String {
    name.trim().chars().take(MAX_NAME_CHARS).collect()
}

/// The sum of what `foods` hold.
pub fn total<'a>(foods: impl IntoIterator<Item = &'a Food>) -> Nutrients {
    foods.into_iter().map(Food::amount).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn food(grams: f64, per_100g: Nutrients) -> Food {
        Food {
            id: 1,
            name: "Rice".into(),
            grams,
            per_100g,
            source: FoodSource::Manual,
            confidence: None,
            estimated_grams: None,
        }
    }

    #[test]
    fn amounts_scale_per_100_grams() {
        let rice = food(250.0, Nutrients::new(130.0, 2.69, 28.17, 0.28));
        let eaten = rice.amount();
        assert!((eaten.kcal - 325.0).abs() < 1e-9);
        assert!((eaten.protein - 6.725).abs() < 1e-9);
        assert!((eaten.carbs - 70.425).abs() < 1e-9);
        assert!((eaten.fat - 0.7).abs() < 1e-9);
    }

    #[test]
    fn totals_sum_every_food() {
        let foods = [
            food(100.0, Nutrients::new(100.0, 10.0, 10.0, 1.0)),
            food(50.0, Nutrients::new(200.0, 0.0, 40.0, 4.0)),
        ];
        assert_eq!(total(&foods), Nutrients::new(200.0, 10.0, 30.0, 3.0));
        assert_eq!(total(&[]), Nutrients::ZERO);
    }

    #[test]
    fn per_100g_limits() {
        assert!(Nutrients::new(884.0, 0.0, 0.0, 100.0).is_valid_per_100g());
        assert!(!Nutrients::new(901.0, 0.0, 0.0, 100.0).is_valid_per_100g());
        assert!(!Nutrients::new(100.0, -1.0, 0.0, 0.0).is_valid_per_100g());
        assert!(!Nutrients::new(100.0, 60.0, 50.0, 0.0).is_valid_per_100g());
        assert!(!Nutrients::new(f64::NAN, 0.0, 0.0, 0.0).is_valid_per_100g());
    }

    #[test]
    fn validation_names_the_first_problem() {
        let ok = food(120.0, Nutrients::new(52.0, 0.26, 13.81, 0.17));
        assert_eq!(ok.validate(), Ok(()));
        let mut unnamed = ok.clone();
        unnamed.name = "  ".into();
        assert_eq!(unnamed.validate(), Err(FoodError::NameMissing));
        assert_eq!(food(0.0, ok.per_100g).validate(), Err(FoodError::Grams));
        assert_eq!(food(5001.0, ok.per_100g).validate(), Err(FoodError::Grams));
        let wrong = food(10.0, Nutrients::new(2000.0, 0.0, 0.0, 0.0));
        assert_eq!(wrong.validate(), Err(FoodError::Nutrients));
    }

    #[test]
    fn energy_split_explains_the_total() {
        // 20 g protein (80) + 50 g carbs (200) + 10 g fat (90) = 370 of 400.
        let split = Nutrients::new(400.0, 20.0, 50.0, 10.0).energy_split();
        assert_eq!(split.protein, 80.0);
        assert_eq!(split.carbs, 200.0);
        assert_eq!(split.fat, 90.0);
        assert_eq!(split.other, 30.0);
        assert!((split.total() - 400.0).abs() < 1e-9);
        let shares = split.shares();
        assert!((shares.iter().sum::<f64>() - 1.0).abs() < 1e-9);
    }

    #[test]
    fn energy_split_shrinks_macros_past_the_total() {
        // Macros explain 740 kcal, the label says 370: halve each share.
        let split = Nutrients::new(370.0, 40.0, 100.0, 20.0).energy_split();
        assert_eq!(split.other, 0.0);
        assert!((split.total() - 370.0).abs() < 1e-9);
        assert!((split.protein - 80.0).abs() < 1e-9);
        assert_eq!(Nutrients::ZERO.energy_split().shares(), [0.0; 4]);
    }

    #[test]
    fn names_are_trimmed_and_bounded() {
        assert_eq!(clean_name("  牛肉面 "), "牛肉面");
        let long = "很".repeat(200);
        assert_eq!(clean_name(&long).chars().count(), MAX_NAME_CHARS);
    }

    #[test]
    fn confidence_words() {
        assert_eq!(Confidence::parse(" LOW "), Some(Confidence::Low));
        assert_eq!(Confidence::parse("sure"), None);
    }
}
