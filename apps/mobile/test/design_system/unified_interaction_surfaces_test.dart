import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/ui/execution_sheet_footer.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  for (final width in [320.0, 400.0, 600.0]) {
    testWidgets('execution and shared form footers agree at $width dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              SizedBox(
                width: width,
                child: AppSheetFooter(
                  submitLabel: 'Save shared',
                  cancelLabel: 'Cancel shared',
                  onSubmit: () {},
                  onCancel: () {},
                ),
              ),
              SizedBox(
                width: width,
                child: ExecutionSheetFooter(
                  submitLabel: 'Save execution',
                  cancelLabel: 'Cancel execution',
                  onSubmit: () {},
                  onCancel: () {},
                ),
              ),
            ],
          ),
        ),
      );
      final sharedDelta =
          tester.getCenter(find.text('Save shared')) -
          tester.getCenter(find.text('Cancel shared'));
      final executionDelta =
          tester.getCenter(find.text('Save execution')) -
          tester.getCenter(find.text('Cancel execution'));
      expect(executionDelta.dy, closeTo(sharedDelta.dy, 0.1));
      expect(executionDelta.dx, closeTo(sharedDelta.dx, 0.1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('error state owns one clear primary retry action', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        AppEmptyState.error(
          title: 'Could not load',
          retryLabel: 'Retry',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.byType(AppActionButton), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(retried, isTrue);
  });

  testWidgets('grouped actions share one surface and quiet divider', (
    tester,
  ) async {
    var selected = '';
    await tester.pumpWidget(
      _wrap(
        Center(
          child: SizedBox(
            width: 360,
            child: AppGroupedActionList(
              actions: [
                AppGroupedAction(
                  icon: FLucideIcons.wallet,
                  title: 'Wallet',
                  subtitle: 'Cash account',
                  onPress: () => selected = 'wallet',
                ),
                AppGroupedAction(
                  icon: FLucideIcons.landmark,
                  title: 'Bank',
                  subtitle: 'Deposit account',
                  onPress: () => selected = 'bank',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppGroupedSurface), findsOneWidget);
    expect(find.byType(AppGroupedDivider), findsOneWidget);
    expect(find.byType(SoftCard), findsNothing);
    await tester.tap(find.text('Bank'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(selected, 'bank');
  });
}
