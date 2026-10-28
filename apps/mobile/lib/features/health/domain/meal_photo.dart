import 'dart:typed_data';

enum MealPhotoRole { overview, side, detail, label, afterMeal }

extension MealPhotoRoleWire on MealPhotoRole {
  String get wire => this == MealPhotoRole.afterMeal ? 'after_meal' : name;

  static MealPhotoRole parse(String value) => MealPhotoRole.values.firstWhere(
    (role) => role.wire == value,
    orElse: () => MealPhotoRole.overview,
  );
}

/// A device-local view of one meal. Video frames use the same image contract.
class MealPhoto {
  MealPhoto({
    required Uint8List bytes,
    this.id,
    this.role = MealPhotoRole.overview,
    this.timestampMs,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  static const maxCount = 4;
  static const maxBytes = 2 * 1024 * 1024;
  static const maxVideoDurationMs = 10000;
  final String? id;
  final Uint8List bytes;
  final MealPhotoRole role;
  final int? timestampMs;

  bool get isMealView =>
      role != MealPhotoRole.afterMeal && role != MealPhotoRole.label;
  bool get isValid =>
      bytes.isNotEmpty &&
      bytes.length <= maxBytes &&
      (id == null || (id!.isNotEmpty && id!.length <= 128)) &&
      (timestampMs == null ||
          (timestampMs! >= 0 && timestampMs! <= maxVideoDurationMs));

  MealPhoto withRole(MealPhotoRole role) =>
      MealPhoto(id: id, bytes: bytes, role: role, timestampMs: timestampMs);
}
