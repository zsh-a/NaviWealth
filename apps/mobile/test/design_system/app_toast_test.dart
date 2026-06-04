import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => AppMessenger.init(child: child!),
    home: FTheme(data: FThemes.slate.light.desktop, child: child),
  );
}

void main() {
  setUp(() => Haptics.disabled = true);
  tearDown(() => Haptics.disabled = false);

  testWidgets('app toast renders semantic kinds and action', (tester) async {
    var actionPressed = false;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () {
              for (final kind in ToastKind.values) {
                AppMessenger.show(
                  context,
                  kind,
                  'toast-${kind.name}',
                  actionLabel: kind == ToastKind.info ? 'Undo' : null,
                  onAction: kind == ToastKind.info
                      ? () => actionPressed = true
                      : null,
                );
              }
            },
            child: const Text('Show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    for (final kind in ToastKind.values) {
      expect(find.text('toast-${kind.name}'), findsOneWidget);
    }

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(actionPressed, isTrue);

    await tester.pump(const Duration(seconds: 3));
  });
}
