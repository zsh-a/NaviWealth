import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'health_meal_repository.dart';

class MealPhotoCapture {
  const MealPhotoCapture();

  Future<Uint8List?> pick({required bool camera}) async {
    if (kIsWeb) throw UnsupportedError('Health meal capture is native-only');
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Meal photo exceeds capture limit');
    }
    return compute(normalizeMealPhoto, await file.readAsBytes());
  }
}

final mealPhotoCaptureProvider = Provider<MealPhotoCapture>(
  (ref) => const MealPhotoCapture(),
);

/// Re-encode with a bounded resolution and no EXIF/GPS or original metadata.
/// Processing runs off the UI isolate; only these bytes may be uploaded/saved.
Uint8List normalizeMealPhoto(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Invalid meal photo size');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 40 * 1000 * 1000) {
    throw const FormatException('Unsupported meal photo');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Unreadable meal photo');
  final upright = img.bakeOrientation(decoded);
  final factor = math.min(1.0, 1280 / math.max(upright.width, upright.height));
  final resized = img.copyResize(
    upright,
    width: math.max(1, (upright.width * factor).round()),
    height: math.max(1, (upright.height * factor).round()),
  );
  final clean = img.Image.fromBytes(
    width: resized.width,
    height: resized.height,
    bytes: resized.getBytes(order: img.ChannelOrder.rgb).buffer,
    numChannels: 3,
  );
  final result = Uint8List.fromList(img.encodeJpg(clean, quality: 82));
  if (result.length > HealthMealRepository.maxPhotoBytes) {
    throw const FormatException('Meal photo exceeds normalized size limit');
  }
  return result;
}
