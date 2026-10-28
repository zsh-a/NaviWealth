import 'dart:convert';

import '../../../core/sync/sync_meta.dart';

enum HealthMealType { breakfast, lunch, dinner, snack }

/// Nutrient values in kcal and grams. The same type represents a per-100g
/// snapshot and the deterministically calculated amount actually consumed.
class MealNutrients {
  const MealNutrients({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  static const zero = MealNutrients(kcal: 0, protein: 0, carbs: 0, fat: 0);
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  MealNutrients scaled(double factor) => MealNutrients(
    kcal: kcal * factor,
    protein: protein * factor,
    carbs: carbs * factor,
    fat: fat * factor,
  );

  MealNutrients operator +(MealNutrients other) => MealNutrients(
    kcal: kcal + other.kcal,
    protein: protein + other.protein,
    carbs: carbs + other.carbs,
    fat: fat + other.fat,
  );

  bool get validPer100g =>
      kcal.isFinite &&
      kcal >= 0 &&
      kcal <= 1000 &&
      [protein, carbs, fat].every((n) => n.isFinite && n >= 0 && n <= 100) &&
      protein + carbs + fat <= 105;

  Map<String, Object?> toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
  };

  factory MealNutrients.fromJson(Map<String, Object?> json) {
    double value(String key) {
      final raw = json[key];
      if (raw is! num || !raw.isFinite) {
        throw FormatException('Invalid meal nutrient: $key');
      }
      return raw.toDouble();
    }

    final nutrients = MealNutrients(
      kcal: value('kcal'),
      protein: value('protein'),
      carbs: value('carbs'),
      fat: value('fat'),
    );
    if (!nutrients.validPer100g) {
      throw const FormatException('Invalid per-100g nutrient values');
    }
    return nutrients;
  }
}

class MealFood {
  const MealFood({
    required this.name,
    required this.grams,
    required this.per100g,
    required this.source,
    this.catalogId,
  });

  final String name;

  /// Edible, actually consumed weight, using the same cooked/raw basis as
  /// [per100g]. No hidden portion multiplier is applied a second time.
  final double grams;
  final MealNutrients per100g;

  /// USDA record reference, `model_estimate`, or `manual`.
  final String source;
  final String? catalogId;

  MealNutrients get nutrients => per100g.scaled(grams / 100);
  bool get isEstimate => source == 'model_estimate';
  bool get isValid =>
      name.trim().isNotEmpty &&
      name.length <= 120 &&
      grams.isFinite &&
      grams > 0 &&
      grams <= 10000 &&
      per100g.validPer100g &&
      source.isNotEmpty &&
      source.length <= 200 &&
      (catalogId == null || catalogId!.length <= 80);

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'grams': grams,
    'per_100g': per100g.toJson(),
    'source': source,
    'catalog_id': ?catalogId,
  };

  factory MealFood.fromJson(Map<String, Object?> json) {
    final nutrients = json['per_100g'];
    final grams = json['grams'];
    if (nutrients is! Map<String, Object?> ||
        grams is! num ||
        json['name'] is! String ||
        json['source'] is! String) {
      throw const FormatException('Invalid meal food');
    }
    final food = MealFood(
      name: json['name']! as String,
      grams: grams.toDouble(),
      per100g: MealNutrients.fromJson(nutrients),
      source: json['source']! as String,
      catalogId: json['catalog_id'] as String?,
    );
    if (!food.isValid) throw const FormatException('Invalid meal food values');
    return food;
  }
}

class HealthMeal {
  HealthMeal({
    required this.id,
    required this.capturedAt,
    required this.day,
    required this.type,
    required List<MealFood> foods,
    required this.sync,
    this.note,
    this.recognitionModel,
  }) : foods = List.unmodifiable(foods);

  final String id;
  final DateTime capturedAt;
  final DateTime day;
  final HealthMealType type;
  final List<MealFood> foods;
  final String? note;
  final String? recognitionModel;
  final SyncMeta sync;

  MealNutrients get total =>
      foods.fold(MealNutrients.zero, (sum, food) => sum + food.nutrients);

  static String encodeFoods(List<MealFood> foods) => jsonEncode({
    'version': 1,
    'foods': foods.map((food) => food.toJson()).toList(),
  });

  static List<MealFood> decodeFoods(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['foods'] is! List) {
      throw const FormatException('Unsupported meal food payload');
    }
    final foods = (json['foods'] as List<dynamic>).map((raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid meal food');
      }
      return MealFood.fromJson(raw);
    }).toList();
    if (foods.isEmpty || foods.length > 30) {
      throw const FormatException('Expected 1 to 30 meal foods');
    }
    return List.unmodifiable(foods);
  }
}
