import '../domain/meal_photo.dart';

Future<List<MealPhoto>?> captureMealVideo({
  required bool camera,
  required int limit,
}) => throw UnsupportedError('Meal video capture is native-only');
