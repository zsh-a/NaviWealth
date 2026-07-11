import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
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
