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

  testWidgets('confirm dialog wraps content instead of filling viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () {
              showConfirmDialog(
                context: context,
                title: const Text('Delete item?'),
                body: const Text('This cannot be undone.'),
                cancelLabel: 'Cancel',
                confirmLabel: 'Delete',
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

    final dialogSize = tester.getSize(
      find.byKey(const ValueKey<String>('app-dialog-surface')),
    );
    expect(dialogSize.height, lessThan(320));
    expect(dialogSize.height, greaterThan(120));
    expect(dialogSize.width, lessThanOrEqualTo(460));
    final cancelCenter = tester.getCenter(find.text('Cancel'));
    final deleteCenter = tester.getCenter(find.text('Delete'));
    expect((cancelCenter.dy - deleteCenter.dy).abs(), lessThan(4));
  });

  testWidgets('progress dialog can be dismissed by returned callback', (
    tester,
  ) async {
    late Future<Future<void> Function()> dismissFuture;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () {
              dismissFuture = showProgressDialog(
                context: context,
                message: 'Exporting backup',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Exporting backup'), findsOneWidget);
    final dismiss = await dismissFuture;
    await dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Exporting backup'), findsNothing);
  });

  testWidgets('text prompt keeps validation inline and returns trimmed input', (
    tester,
  ) async {
    late Future<String?> result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () {
              result = showAppTextPromptSheet(
                context: context,
                title: 'Add note',
                fieldLabel: 'Note',
                submitLabel: 'Save',
                cancelLabel: 'Cancel',
                validator: (value) =>
                    value.trim().isEmpty ? 'A note is required' : null,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A note is required'), findsOneWidget);

    await tester.enterText(find.byType(FTextField), '  Reviewed  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await result, 'Reviewed');
    expect(find.text('Add note'), findsNothing);
  });
}
