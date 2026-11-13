import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/health_meal.dart';
import '../domain/meal_photo.dart';

class MealRecognitionDraft {
  const MealRecognitionDraft({
    required this.foods,
    required this.model,
    required this.promptVersion,
    this.title,
  });
  final List<MealFood> foods;
  final String model;
  final String promptVersion;
  final String? title;
}

abstract interface class MealRecognitionClient {
  /// Captured with the client/profile, so consent cannot silently target a
  /// different provider after a settings change while the dialog is open.
  String get providerLabel;
  Future<MealRecognitionDraft> recognize({
    required List<MealPhoto> photos,
    required String languageCode,
    required bool allowUpload,
    String context = '',
  });
}

/// App composition supplies an FRB-backed client. No Dart HTTP or relay fallback.
final mealRecognitionClientProvider = Provider<MealRecognitionClient?>(
  (ref) => null,
);

/// Adapts the validated shared-core DTO into the Host's editable meal model.
/// Provider response decoding, catalog resolution and recognition validation
/// are owned by health-core; model text never reaches this adapter.
MealRecognitionDraft mealRecognitionDraftFromCore(
  Map<String, Object?> response,
) {
  final foods = response['foods'];
  final model = response['model'];
  final promptVersion = response['prompt_version'];
  final title = response['title'];
  if (foods is! List<Object?> ||
      foods.isEmpty ||
      foods.length > 30 ||
      model is! String ||
      model.isEmpty ||
      model.length > 200 ||
      promptVersion is! String ||
      promptVersion.isEmpty ||
      promptVersion.length > 200 ||
      (title != null && title is! String)) {
    throw const FormatException('Invalid shared meal recognition result');
  }
  return MealRecognitionDraft(
    foods: List.unmodifiable(
      foods.map((food) {
        if (food is! Map<String, Object?>) {
          throw const FormatException('Invalid shared meal food');
        }
        return MealFood.fromJson(food);
      }),
    ),
    model: model,
    promptVersion: promptVersion,
    title: title as String?,
  );
}
