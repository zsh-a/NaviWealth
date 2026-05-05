import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';

class _HapticsRecorder {
  final List<String> calls = [];

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add((call.arguments as String?) ?? 'default');
      }
      return null;
    });
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

/// Pin the test to Android so [Haptics] reports `isEnabled: true`. Restored
/// in `finally` because the binding asserts the override is null between
/// tests — `tearDown` runs too late for that invariant check.
Future<void> _onAndroid(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  late _HapticsRecorder recorder;

  setUp(() {
    Haptics.disabled = false;
    recorder = _HapticsRecorder()..install();
  });

  tearDown(() {
    recorder.dispose();
  });

  testWidgets('AppFab fires lightImpact and runs onPressed', (tester) async {
    await _onAndroid(() async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AppFab(
              onPressed: () => pressed++,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppFab));
      expect(pressed, 1);
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });
  });

  testWidgets('AppFab.extended fires lightImpact', (tester) async {
    await _onAndroid(() async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AppFab.extended(
              onPressed: () => pressed++,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppFab));
      expect(pressed, 1);
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });
  });

  testWidgets('AppFab disables haptic when onPressed is null', (tester) async {
    await _onAndroid(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            floatingActionButton: AppFab(
              onPressed: null,
              child: Icon(Icons.add),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppFab));
      expect(recorder.calls, isEmpty);
    });
  });

  testWidgets('AppChoiceChip fires selectionClick on toggle', (tester) async {
    await _onAndroid(() async {
      var selectedNow = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setState) => AppChoiceChip(
                label: const Text('foo'),
                selected: selectedNow,
                onSelected: (v) => setState(() => selectedNow = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppChoiceChip));
      await tester.pump();
      expect(selectedNow, isTrue);
      expect(recorder.calls, ['HapticFeedbackType.selectionClick']);
    });
  });

  testWidgets(
    'AppDismissibleListTile fires mediumImpact on swipe-to-dismiss',
    (tester) async {
      await _onAndroid(() async {
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  AppDismissibleListTile(
                    dismissibleKey: const ValueKey('row-1'),
                    direction: DismissDirection.endToStart,
                    background: Container(color: Colors.red),
                    onDismissed: (_) => dismissed = true,
                    child: const SizedBox(
                      height: 56,
                      child: ListTile(title: Text('Row 1')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.fling(
          find.text('Row 1'),
          const Offset(-500, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(dismissed, isTrue);
        expect(recorder.calls, contains('HapticFeedbackType.mediumImpact'));
      });
    },
  );
}
