import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _harness({
  required FormDirtyController dirty,
  required Future<bool> Function(BuildContext context) confirmDismiss,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FButton(
              onPress: () => showAppSheet<void>(
                context: context,
                title: 'Edit allocation',
                dirtyGuard: dirty,
                confirmDismiss: () => confirmDismiss(context),
                builder: (_) => const SizedBox(
                  height: 160,
                  child: Center(child: Text('Allocation form')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pristine guarded sheet closes from a barrier tap', (
    tester,
  ) async {
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    var confirmations = 0;

    await tester.pumpWidget(
      _harness(
        dirty: dirty,
        confirmDismiss: (_) async {
          confirmations++;
          return false;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Edit allocation'), findsNothing);
    expect(confirmations, 0);
  });

  testWidgets('dirty barrier dismissal confirms before closing', (
    tester,
  ) async {
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    var confirmations = 0;
    var approve = false;

    await tester.pumpWidget(
      _harness(
        dirty: dirty,
        confirmDismiss: (_) async {
          confirmations++;
          return approve;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    dirty.markDirty();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(confirmations, 1);
    expect(find.text('Edit allocation'), findsOneWidget);

    approve = true;
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(confirmations, 2);
    expect(find.text('Edit allocation'), findsNothing);
  });

  testWidgets('dirty sheet drag springs back and confirms', (tester) async {
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    var confirmations = 0;
    var approve = false;

    await tester.pumpWidget(
      _harness(
        dirty: dirty,
        confirmDismiss: (_) async {
          confirmations++;
          return approve;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    dirty.markDirty();

    await tester.fling(
      find.byType(AppSheetDragHandle),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(confirmations, 1);
    expect(find.text('Edit allocation'), findsOneWidget);

    approve = true;
    await tester.fling(
      find.byType(AppSheetDragHandle),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(confirmations, 2);
    expect(find.text('Edit allocation'), findsNothing);
  });

  testWidgets('busy sheet rejects dismissal without prompting', (tester) async {
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    var confirmations = 0;

    await tester.pumpWidget(
      _harness(
        dirty: dirty,
        confirmDismiss: (_) async {
          confirmations++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    dirty
      ..markDirty()
      ..busy = true;

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(confirmations, 0);
    expect(find.text('Edit allocation'), findsOneWidget);

    dirty
      ..busy = false
      ..markPristine();
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Edit allocation'), findsNothing);
  });

  testWidgets('dirty dismissal can present the shared discard dialog', (
    tester,
  ) async {
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);

    await tester.pumpWidget(
      _harness(
        dirty: dirty,
        confirmDismiss: (context) async {
          final discard = await showConfirmDialog(
            context: context,
            title: const Text('Discard changes?'),
            body: const Text('Your edits have not been saved.'),
            cancelLabel: 'Keep editing',
            confirmLabel: 'Discard',
            destructive: true,
          );
          return discard == true;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    dirty.markDirty();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Edit allocation'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit allocation'), findsNothing);
  });
}
