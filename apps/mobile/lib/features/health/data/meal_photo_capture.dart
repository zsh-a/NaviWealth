import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../domain/meal_photo.dart';
import 'health_meal_repository.dart';
import 'meal_video_capture_stub.dart'
    if (dart.library.io) 'meal_video_capture_io.dart';

class MealPhotoCapture {
  const MealPhotoCapture();

  bool get supportsVideo =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<List<Uint8List>> pickMany({required int limit}) async {
    if (limit < 1 || limit > MealPhoto.maxCount) {
      throw ArgumentError.value(limit);
    }
    if (limit == 1) {
      final photo = await pick(camera: false);
      return photo == null ? [] : [photo];
    }
    if (kIsWeb) throw UnsupportedError('Health meal capture is native-only');
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      limit: limit,
    );
    if (files.length > limit) {
      throw const FormatException('Too many meal views');
    }
    final photos = <Uint8List>[];
    for (final file in files) {
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('Meal photo exceeds capture limit');
      }
      photos.add(await compute(normalizeMealPhoto, await file.readAsBytes()));
    }
    return photos;
  }

  Future<List<MealPhoto>?> pickVideo({
    required bool camera,
    required int limit,
  }) {
    if (!supportsVideo) throw UnsupportedError('Meal video is unavailable');
    return captureMealVideo(camera: camera, limit: limit);
  }

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
