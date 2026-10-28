import '../domain/health_meal.dart';

class MealCatalogFood {
  const MealCatalogFood(this.id, this.enName, this.zhName, this.per100g);
  final String id;
  final String enName;
  final String zhName;
  final MealNutrients per100g;
  String label(String languageCode) => languageCode == 'zh' ? zhName : enName;
  MealFood portion(double grams, {String? name}) => MealFood(
    name: name ?? enName,
    grams: grams,
    per100g: per100g,
    source: 'USDA FDC $id',
    catalogId: id,
  );
}

/// Public-domain (CC0) SR Legacy records retrieved from USDA FoodData Central
/// on 2026-10-28. IDs retain source attribution and permit verification at
/// `https://fdc.nal.usda.gov/food-details/{id}/nutrients`.
/// Cooked/raw preparation is part of the identity, not a loose food synonym.
/// This deliberately small offline catalog makes no claim to cover recipes.
const mealFoodCatalog = <MealCatalogFood>[
  MealCatalogFood(
    '168878',
    'White rice, cooked',
    '白米饭（熟）',
    MealNutrients(kcal: 130, protein: 2.69, carbs: 28.17, fat: 0.28),
  ),
  MealCatalogFood(
    '171287',
    'Whole egg, raw',
    '全鸡蛋（生，可食部分）',
    MealNutrients(kcal: 143, protein: 12.56, carbs: 0.72, fat: 9.51),
  ),
  MealCatalogFood(
    '171477',
    'Chicken breast, roasted',
    '鸡胸肉（烤熟、去皮）',
    MealNutrients(kcal: 165, protein: 31.02, carbs: 0, fat: 3.57),
  ),
  MealCatalogFood(
    '171413',
    'Olive oil',
    '橄榄油',
    MealNutrients(kcal: 884, protein: 0, carbs: 0, fat: 100),
  ),
  MealCatalogFood(
    '172475',
    'Firm tofu, raw, calcium-set',
    '硬豆腐（生、硫酸钙凝固）',
    MealNutrients(kcal: 144, protein: 17.27, carbs: 2.78, fat: 8.72),
  ),
  MealCatalogFood(
    '171688',
    'Apple, raw, with skin',
    '苹果（生、带皮）',
    MealNutrients(kcal: 52, protein: 0.26, carbs: 13.81, fat: 0.17),
  ),
  MealCatalogFood(
    '173944',
    'Banana, raw',
    '香蕉（生、去皮）',
    MealNutrients(kcal: 89, protein: 1.09, carbs: 22.84, fat: 0.33),
  ),
  MealCatalogFood(
    '171265',
    'Whole milk, 3.25% fat',
    '全脂牛奶（脂肪 3.25%）',
    MealNutrients(kcal: 61, protein: 3.15, carbs: 4.8, fat: 3.25),
  ),
  MealCatalogFood(
    '169967',
    'Broccoli, boiled, drained',
    '西兰花（水煮、沥干）',
    MealNutrients(kcal: 35, protein: 2.38, carbs: 7.18, fat: 0.41),
  ),
  MealCatalogFood(
    '170379',
    'Broccoli, raw',
    '西兰花（生）',
    MealNutrients(kcal: 34, protein: 2.82, carbs: 6.64, fat: 0.37),
  ),
  MealCatalogFood(
    '170393',
    'Carrot, raw',
    '胡萝卜（生）',
    MealNutrients(kcal: 41, protein: 0.93, carbs: 9.58, fat: 0.24),
  ),
  MealCatalogFood(
    '169124',
    'Pineapple, raw',
    '菠萝（生、可食部分）',
    MealNutrients(kcal: 50, protein: 0.54, carbs: 13.12, fat: 0.12),
  ),
];

MealCatalogFood? mealCatalogFoodById(String? id) {
  for (final food in mealFoodCatalog) {
    if (food.id == id) return food;
  }
  return null;
}
