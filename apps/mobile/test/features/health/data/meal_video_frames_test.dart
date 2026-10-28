import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naviwealth/features/health/data/meal_video_frames.dart';
import 'package:naviwealth/features/health/domain/meal_photo.dart';

Uint8List _picture({int shift = 0, bool flat = false}) {
  final image = img.Image(width: 96, height: 96);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final value = flat ? 128 : (((x + shift) ~/ 12 + y ~/ 12) % 2) * 255;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(
      MealVideoFrameExtractor.channel,
      null,
    ),
  );

  test(
    'video selection removes blank and duplicate views and retains timestamps',
    () {
      final frames = [
        MealVideoFrame(bytes: _picture(flat: true), timestampMs: 100),
        MealVideoFrame(bytes: _picture(), timestampMs: 300),
        MealVideoFrame(bytes: _picture(), timestampMs: 500),
        MealVideoFrame(bytes: _picture(shift: 12), timestampMs: 700),
      ];
      final selected = selectMealVideoFrames(frames, 4);
      expect(selected, hasLength(2));
      expect(selected.map((frame) => frame.timestampMs), [300, 700]);
      expect(
        selected.every((frame) => frame.isValid && frame.isMealView),
        isTrue,
      );
      expect(selectMealVideoFrames(frames, 1), hasLength(1));
      expect(
        () => selectMealVideoFrames([
          MealVideoFrame(bytes: _picture(flat: true), timestampMs: 100),
        ], 4),
        throwsA(isA<MealVideoException>()),
      );
    },
  );

  test(
    'native extraction validates bounds and preserves safe error codes',
    () async {
      messenger.setMockMethodCallHandler(MealVideoFrameExtractor.channel, (
        call,
      ) async {
        expect(call.method, 'extract');
        expect(call.arguments, {'path': '/tmp/meal.mp4'});
        return {
          'duration_ms': 2000,
          'frames': [
            {'bytes': _picture(), 'time_ms': 300},
          ],
        };
      });
      final frames = await const MealVideoFrameExtractor().extract(
        '/tmp/meal.mp4',
      );
      expect(frames.single.timestampMs, 300);
      for (final response in [
        {
          'duration_ms': 2000,
          'frames': [
            {'bytes': _picture(), 'time_ms': 3000},
          ],
        },
        {'duration_ms': 2000, 'frames': <Object?>[]},
        {
          'duration_ms': MealPhoto.maxVideoDurationMs + 1,
          'frames': <Object?>[],
        },
      ]) {
        messenger.setMockMethodCallHandler(
          MealVideoFrameExtractor.channel,
          (_) async => response,
        );
        await expectLater(
          const MealVideoFrameExtractor().extract('/tmp/meal.mp4'),
          throwsA(isA<MealVideoException>()),
        );
      }
      messenger.setMockMethodCallHandler(MealVideoFrameExtractor.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'video_duration',
          message: 'private file path',
        );
      });
      await expectLater(
        const MealVideoFrameExtractor().extract('/tmp/meal.mp4'),
        throwsA(
          isA<MealVideoException>().having(
            (e) => e.code,
            'code',
            'video_duration',
          ),
        ),
      );
    },
  );
}
