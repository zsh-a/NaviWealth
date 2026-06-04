import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(data: FThemes.slate.light.desktop, child: child),
  );
}

void main() {
  testWidgets('confirm dialog ignores barrier taps', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () {
              showConfirmDialog(
                context: context,
                title: const Text('Discard changes?'),
                body: const Text('This cannot be undone.'),
                cancelLabel: 'Keep editing',
                confirmLabel: 'Discard',
                destructive: true,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
  });
}
