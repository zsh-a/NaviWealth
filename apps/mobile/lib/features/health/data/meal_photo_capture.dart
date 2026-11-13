import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/meal_photo.dart';
import 'meal_video_capture_stub.dart'
    if (dart.library.io) 'meal_video_capture_io.dart';

typedef MealPhotoNormalizer = Future<Uint8List> Function(Uint8List bytes);

/// App composition supplies the same native normalizer used by recognition.
final mealPhotoNormalizerProvider = Provider<MealPhotoNormalizer>((ref) {
  return (_) => throw UnsupportedError('Meal normalization is native-only');
});

class MealPhotoCapture {
  const MealPhotoCapture({MealPhotoNormalizer? normalize})
    : _normalize = normalize;

  final MealPhotoNormalizer? _normalize;

  Future<Uint8List> _normalizePhoto(Uint8List bytes) {
    final normalize = _normalize;
    if (normalize == null) {
      throw UnsupportedError('Meal normalization is unavailable');
    }
    return normalize(bytes);
  }

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
      photos.add(await _normalizePhoto(await file.readAsBytes()));
    }
    return photos;
  }

  Future<List<MealPhoto>?> pickVideo({
    required bool camera,
    required int limit,
  }) async {
    if (!supportsVideo) throw UnsupportedError('Meal video is unavailable');
    final frames = await captureMealVideo(camera: camera, limit: limit);
    if (frames == null) return null;
    return [
      for (final frame in frames)
        MealPhoto(
          bytes: await _normalizePhoto(frame.bytes),
          role: frame.role,
          timestampMs: frame.timestampMs,
        ),
    ];
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
    return _normalizePhoto(await file.readAsBytes());
  }
}

final mealPhotoCaptureProvider = Provider<MealPhotoCapture>(
  (ref) => MealPhotoCapture(normalize: ref.watch(mealPhotoNormalizerProvider)),
);
