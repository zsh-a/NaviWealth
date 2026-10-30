import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/meal_photo_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  const saver = MealPhotoSaver();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('exports selected bytes with add-only access on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'hasAccess' || 'requestAccess' => true,
          _ => null,
        };
      });

      expect(calls, isEmpty);
      await saver.save(bytes);

      final write = calls.singleWhere((call) => call.method == 'putImageBytes');
      final arguments = write.arguments as Map<Object?, Object?>;
      expect(arguments['bytes'], bytes);
      expect(arguments['album'], isNull);
      expect(arguments['name'], startsWith('NaviWealth_meal_'));
      for (final call in calls.where(
        (call) => call.method != 'putImageBytes',
      )) {
        expect(call.arguments, {'toAlbum': false});
      }
    });
  }

  test('permission rejection never writes an image', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false;
    });

    await expectLater(
      saver.save(Uint8List(3)),
      throwsA(
        isA<MealPhotoSaveException>().having(
          (error) => error.failure,
          'failure',
          MealPhotoSaveFailure.permissionDenied,
        ),
      ),
    );
    expect(calls, ['hasAccess', 'requestAccess']);
  });

  test('newly granted permission allows the write', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'hasAccess' => false,
        'requestAccess' => true,
        _ => null,
      };
    });

    await saver.save(Uint8List(3));
    expect(calls.first, 'hasAccess');
    expect(
      calls.indexOf('requestAccess'),
      lessThan(calls.indexOf('putImageBytes')),
    );
  });

  test('native failures expose safe, actionable reasons', () async {
    for (final (code, failure) in [
      ('ACCESS_DENIED', MealPhotoSaveFailure.permissionDenied),
      ('NOT_ENOUGH_SPACE', MealPhotoSaveFailure.insufficientSpace),
      ('NOT_SUPPORTED_FORMAT', MealPhotoSaveFailure.failed),
      ('UNEXPECTED', MealPhotoSaveFailure.failed),
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'putImageBytes') {
          throw PlatformException(
            code: code,
            message: 'private platform details',
          );
        }
        return true;
      });

      await expectLater(
        saver.save(Uint8List(3)),
        throwsA(
          isA<MealPhotoSaveException>().having(
            (error) => error.failure,
            'failure',
            failure,
          ),
        ),
      );
    }
  });

  test('unsupported platforms do not call the photo library', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('The photo library must not be used');
    });
    expect(saver.supported, isFalse);
    await expectLater(saver.save(Uint8List(3)), throwsUnsupportedError);
  });
}
