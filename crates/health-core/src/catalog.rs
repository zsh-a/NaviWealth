//! A small offline reference of foods whose nutrients are measured, not
//! estimated: public-domain (CC0) USDA FoodData Central SR Legacy records,
//! verifiable at `https://fdc.nal.usda.gov/food-details/{id}/nutrients`.
//! The preparation (cooked, raw) is part of each record's identity. When a
//! model names one of these ids, the app uses these values, never the
//! model's.

use super::nutrition::Nutrients;

/// One reference food.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CatalogFood {
    /// FoodData Central id.
    pub id: &'static str,
    pub name_en: &'static str,
    pub name_zh: &'static str,
    pub per_100g: Nutrients,
}

/// The bundled records.
pub const CATALOG: &[CatalogFood] = &[
    food(
        "168878",
        "White rice, cooked",
        "白米饭（熟）",
        130.0,
        2.69,
        28.17,
        0.28,
    ),
    food(
        "171287",
        "Whole egg, raw",
        "全鸡蛋（生，可食部分）",
        143.0,
        12.56,
        0.72,
        9.51,
    ),
    food(
        "171477",
        "Chicken breast, roasted",
        "鸡胸肉（烤熟、去皮）",
        165.0,
        31.02,
        0.0,
        3.57,
    ),
    food("171413", "Olive oil", "橄榄油", 884.0, 0.0, 0.0, 100.0),
    food(
        "172475",
        "Firm tofu, raw, calcium-set",
        "硬豆腐（生、硫酸钙凝固）",
        144.0,
        17.27,
        2.78,
        8.72,
    ),
    food(
        "171688",
        "Apple, raw, with skin",
        "苹果（生、带皮）",
        52.0,
        0.26,
        13.81,
        0.17,
    ),
    food(
        "173944",
        "Banana, raw",
        "香蕉（生、去皮）",
        89.0,
        1.09,
        22.84,
        0.33,
    ),
    food(
        "171265",
        "Whole milk, 3.25% fat",
        "全脂牛奶（脂肪 3.25%）",
        61.0,
        3.15,
        4.8,
        3.25,
    ),
    food(
        "169967",
        "Broccoli, boiled, drained",
        "西兰花（水煮、沥干）",
        35.0,
        2.38,
        7.18,
        0.41,
    ),
    food(
        "170379",
        "Broccoli, raw",
        "西兰花（生）",
        34.0,
        2.82,
        6.64,
        0.37,
    ),
    food(
        "170393",
        "Carrot, raw",
        "胡萝卜（生）",
        41.0,
        0.93,
        9.58,
        0.24,
    ),
    food(
        "169124",
        "Pineapple, raw",
        "菠萝（生、可食部分）",
        50.0,
        0.54,
        13.12,
        0.12,
    ),
];

#[allow(clippy::too_many_arguments)]
const fn food(
    id: &'static str,
    name_en: &'static str,
    name_zh: &'static str,
    kcal: f64,
    protein: f64,
    carbs: f64,
    fat: f64,
) -> CatalogFood {
    CatalogFood {
        id,
        name_en,
        name_zh,
        per_100g: Nutrients::new(kcal, protein, carbs, fat),
    }
}

/// The record with FoodData Central id `id`.
pub fn by_id(id: &str) -> Option<&'static CatalogFood> {
    CATALOG.iter().find(|food| food.id == id.trim())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_record_is_plausible_and_unique() {
        for (index, food) in CATALOG.iter().enumerate() {
            assert!(food.per_100g.is_valid_per_100g(), "{}", food.id);
            assert!(CATALOG[index + 1..].iter().all(|other| other.id != food.id));
        }
    }

    #[test]
    fn looks_up_by_id() {
        assert_eq!(
            by_id(" 168878 ").map(|f| f.name_en),
            Some("White rice, cooked")
        );
        assert!(by_id("000").is_none());
    }
}
