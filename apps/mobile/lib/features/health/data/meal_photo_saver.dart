import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

enum MealPhotoSaveFailure { permissionDenied, insufficientSpace, failed }

class MealPhotoSaveException implements Exception {
  const MealPhotoSaveException(this.failure);

  final MealPhotoSaveFailure failure;
}

/// Exports only the selected, normalized image after an explicit user action.
/// No album is specified so iOS needs add-only photo access, not library reads.
class MealPhotoSaver {
  const MealPhotoSaver();

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> save(Uint8List bytes) async {
    if (!supported) throw UnsupportedError('Meal photo saving is mobile-only');
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const MealPhotoSaveException(
          MealPhotoSaveFailure.permissionDenied,
        );
      }
      await Gal.putImageBytes(
        bytes,
        name: 'NaviWealth_meal_${DateTime.now().microsecondsSinceEpoch}',
      );
    } on GalException catch (error) {
      throw MealPhotoSaveException(switch (error.type) {
        GalExceptionType.accessDenied => MealPhotoSaveFailure.permissionDenied,
        GalExceptionType.notEnoughSpace =>
          MealPhotoSaveFailure.insufficientSpace,
        _ => MealPhotoSaveFailure.failed,
      });
    }
  }
}

final mealPhotoSaverProvider = Provider<MealPhotoSaver>(
  (ref) => const MealPhotoSaver(),
);
