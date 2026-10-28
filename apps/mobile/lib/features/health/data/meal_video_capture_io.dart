import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/meal_photo.dart';
import 'meal_video_frames.dart';

Future<List<MealPhoto>?> captureMealVideo({
  required bool camera,
  required int limit,
}) async {
  final file = await ImagePicker().pickVideo(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxDuration: const Duration(seconds: 8),
  );
  if (file == null) return null;
  try {
    if (await file.length() > MealVideoFrameExtractor.maxSourceBytes) {
      throw const MealVideoException('video_size');
    }
    final frames = await const MealVideoFrameExtractor().extract(file.path);
    return await compute(selectMealVideoFrameRequest, (
      frames: frames,
      limit: limit,
    ));
  } finally {
    // Delete only the picker copy inside the app's temporary directory.
    // Never remove an original library file or persist the raw video.
    try {
      final temp = await getTemporaryDirectory();
      if (p.isWithin(p.canonicalize(temp.path), p.canonicalize(file.path))) {
        await File(file.path).delete();
      }
    } on Object {
      // OS-managed temporary cleanup remains available after a failed delete.
    }
  }
}
