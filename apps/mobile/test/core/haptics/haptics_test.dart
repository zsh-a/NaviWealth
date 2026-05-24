import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/haptics/haptics.dart';

/// Captures every `HapticFeedback.*` channel invocation so we can assert
/// the right intent fires for each `Haptics.*` helper.
class _HapticsRecorder {
  final List<String> calls = [];

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            // Argument is the haptic type string ("HapticFeedbackType.lightImpact"
            // etc.) or null for the default rumble.
            calls.add((call.arguments as String?) ?? 'default');
          }
          return null;
        });
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

void main() {
  late _HapticsRecorder recorder;
  final originalPlatform = debugDefaultTargetPlatformOverride;

  setUp(() {
    Haptics.disabled = false;
    recorder = _HapticsRecorder()..install();
  });

  tearDown(() {
    recorder.dispose();
    debugDefaultTargetPlatformOverride = originalPlatform;
    Haptics.disabled = false;
  });

  group('Haptics on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('primaryPress fires lightImpact', () {
      Haptics.primaryPress();
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });

    test('selection fires selectionClick', () {
      Haptics.selection();
      expect(recorder.calls, ['HapticFeedbackType.selectionClick']);
    });

    test('destructive fires mediumImpact', () {
      Haptics.destructive();
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('success fires lightImpact', () {
      Haptics.success();
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });

    test('error fires heavyImpact', () {
      Haptics.error();
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });
  });

  group('Haptics on desktop', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test('all helpers are no-op on macOS', () {
      Haptics.primaryPress();
      Haptics.selection();
      Haptics.destructive();
      Haptics.success();
      Haptics.error();
      expect(recorder.calls, isEmpty);
    });
  });

  group('Haptics test seam', () {
    test('disabled flag silences all helpers even on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Haptics.disabled = true;
      Haptics.primaryPress();
      Haptics.selection();
      Haptics.destructive();
      expect(recorder.calls, isEmpty);
    });
  });

  group('wrapPrimary', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('returns null for null input', () {
      expect(Haptics.wrapPrimary(null), isNull);
    });

    test('fires primaryPress before invoking inner callback', () {
      var ran = false;
      final wrapped = Haptics.wrapPrimary(() => ran = true);
      expect(wrapped, isNotNull);
      wrapped!();
      expect(ran, isTrue);
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });
  });
}
