import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/features/health/data/meal_video_frames.dart';

import 'support/meal_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native video codecs extract bounded, usable meal frames', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('meal-video-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/synthetic.mp4');
    await file.writeAsBytes(base64Decode(mealVideoFixtureBase64));
    final frames = await const MealVideoFrameExtractor().extract(file.path);
    expect(frames, hasLength(8));
    expect(frames.every((frame) => img.decodeJpg(frame.bytes) != null), isTrue);
    expect(
      frames.every(
        (frame) => frame.timestampMs >= 0 && frame.timestampMs <= 2000,
      ),
      isTrue,
    );
    final selected = await compute(selectMealVideoFrameRequest, (
      frames: frames,
      limit: 4,
    ));
    expect(selected.length, inInclusiveRange(2, 4));
    expect(selected.every((photo) => photo.isValid), isTrue);
    debugPrint('meal-video: native frames verified');
  }, skip: !Platform.isAndroid && !Platform.isIOS);
}
