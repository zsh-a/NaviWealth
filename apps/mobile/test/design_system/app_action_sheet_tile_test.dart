import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      // Mirrors the AppSheet body (scrollable Column) so we catch any
      // sliver-vs-box layout regression in the grouped list.
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('AppActionSheetList renders flat rows with inset dividers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppActionSheetList(
          children: [
            AppActionSheetTile(
              icon: Icons.account_balance_outlined,
              title: 'New account',
              subtitle: 'Bank, broker or crypto',
              onPress: () {},
            ),
            AppActionSheetTile(
              icon: Icons.savings_outlined,
              title: 'Deposit',
              subtitle: 'Rate, value date, maturity',
              onPress: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byType(FTileGroup), findsNothing);
    expect(find.byType(FTile), findsNothing);
    expect(find.byType(AppGroupedDivider), findsOneWidget);
    expect(find.text('New account'), findsOneWidget);
    expect(find.text('Rate, value date, maturity'), findsOneWidget);
  });

  testWidgets('title-only actions stay compact and omit subtitle layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppActionSheetList(
          children: [
            AppActionSheetTile(
              icon: Icons.search,
              title: 'Search',
              onPress: () {},
            ),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppActionSheetTile)).height, 52);
    expect(find.byType(AppGroupedDivider), findsNothing);
  });

  testWidgets('AppActionSheetTile fires onPress', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        AppActionSheetList(
          children: [
            AppActionSheetTile(
              icon: Icons.payments_outlined,
              title: 'Liability',
              subtitle: 'Mortgage, car loan',
              onPress: () => tapped = true,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Liability'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
