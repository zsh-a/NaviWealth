import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../domain/meal_photo.dart';
import 'meal_photo_capture.dart';

class MealVideoException implements Exception {
  const MealVideoException(this.code);
  final String code;
}

class MealVideoFrame {
  const MealVideoFrame({required this.bytes, required this.timestampMs});
  final Uint8List bytes;
  final int timestampMs;
}

/// Native codecs read a local file on a worker queue. No video/audio is sent
/// to the model; only the reviewed, normalized still frames cross that seam.
class MealVideoFrameExtractor {
  const MealVideoFrameExtractor();
  static const channel = MethodChannel('com.naviwealth/video_frames');
  static const maxSourceBytes = 50 * 1024 * 1024;

  Future<List<MealVideoFrame>> extract(String path) async {
    try {
      final response = await channel.invokeMapMethod<String, Object?>(
        'extract',
        {'path': path},
      );
      final duration = response?['duration_ms'];
      final frames = response?['frames'];
      if (duration is! int ||
          duration <= 0 ||
          duration > MealPhoto.maxVideoDurationMs ||
          frames is! List<Object?> ||
          frames.isEmpty ||
          frames.length > 8) {
        throw const MealVideoException('unreadable');
      }
      return frames
          .map((raw) {
            if (raw is! Map<Object?, Object?> ||
                raw['bytes'] is! Uint8List ||
                raw['time_ms'] is! int) {
              throw const MealVideoException('unreadable');
            }
            final bytes = raw['bytes'] as Uint8List;
            final time = raw['time_ms'] as int;
            if (bytes.isEmpty ||
                bytes.length > MealPhoto.maxBytes ||
                time < 0 ||
                time > duration) {
              throw const MealVideoException('unreadable');
            }
            return MealVideoFrame(bytes: bytes, timestampMs: time);
          })
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw MealVideoException(error.code);
    }
  }
}

class _ScoredFrame {
  _ScoredFrame(this.frame, this.pixels, this.sharpness);
  final MealVideoFrame frame;
  final List<double> pixels;
  final double sharpness;
}

/// Samples across time, prefers sharp frames in each interval, then removes
/// near-duplicates. Visual difference is a heuristic, not a depth measurement.
List<MealPhoto> selectMealVideoFrames(List<MealVideoFrame> frames, int limit) {
  if (limit < 1 || limit > MealPhoto.maxCount || frames.length > 8) {
    throw const MealVideoException('unreadable');
  }
  final scored = <_ScoredFrame>[];
  for (final frame in frames) {
    final decoded = img.decodeImage(frame.bytes);
    if (decoded == null || decoded.width * decoded.height > 40 * 1000 * 1000) {
      continue;
    }
    final thumb = img.copyResize(decoded, width: 32, height: 32);
    final pixels = <double>[
      for (final pixel in thumb)
        0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b,
    ];
    var sum = 0.0, squares = 0.0;
    for (var y = 1; y < 31; y++) {
      for (var x = 1; x < 31; x++) {
        final i = y * 32 + x;
        final laplacian =
            pixels[i - 1] +
            pixels[i + 1] +
            pixels[i - 32] +
            pixels[i + 32] -
            4 * pixels[i];
        sum += laplacian;
        squares += laplacian * laplacian;
      }
    }
    final variance = squares / 900 - (sum / 900) * (sum / 900);
    if (variance > 1) scored.add(_ScoredFrame(frame, pixels, variance));
  }
  scored.sort((a, b) => a.frame.timestampMs.compareTo(b.frame.timestampMs));
  if (scored.isEmpty) throw const MealVideoException('unreadable');
  final selected = <_ScoredFrame>[];
  final bins = math.min(limit, scored.length);
  for (var bin = 0; bin < bins; bin++) {
    final candidates = scored.sublist(
      bin * scored.length ~/ bins,
      (bin + 1) * scored.length ~/ bins,
    )..sort((a, b) => b.sharpness.compareTo(a.sharpness));
    for (final candidate in candidates) {
      final duplicate = selected.any((prior) {
        var difference = 0.0;
        for (var i = 0; i < candidate.pixels.length; i++) {
          difference += (candidate.pixels[i] - prior.pixels[i]).abs();
        }
        return difference / candidate.pixels.length < 6;
      });
      if (!duplicate) {
        selected.add(candidate);
        break;
      }
    }
  }
  selected.sort((a, b) => a.frame.timestampMs.compareTo(b.frame.timestampMs));
  return [
    for (final frame in selected)
      MealPhoto(
        bytes: normalizeMealPhoto(frame.frame.bytes),
        timestampMs: frame.frame.timestampMs,
        role: MealPhotoRole.overview,
      ),
  ];
}

List<MealPhoto> selectMealVideoFrameRequest(
  ({List<MealVideoFrame> frames, int limit}) request,
) => selectMealVideoFrames(request.frames, request.limit);
