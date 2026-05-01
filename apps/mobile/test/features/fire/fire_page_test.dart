import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/fire/data/fire_goal_preferences.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/fire/presentation/fire_page.dart';
import 'package:naviwealth/features/fire/presentation/fire_progress_gauge.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

Asset _cash(String id, String price) => Asset(
      id: id,
      type: AssetType.cash,
      symbol: id,
      currency: 'CNY',
      lastPrice: Decimal.parse(price),
      sync: _meta(),
    );

Future<Widget> _wrap({
  required SharedPreferences prefs,
  List<Asset> manualAssets = const [],
}) async {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      manualAssetsStreamProvider.overrideWith(
        (ref) => Stream.value(manualAssets),
      ),
      physicalAssetsListProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
      liabilitiesStreamProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
      fxRatesStreamProvider.overrideWith(
        (ref) => Stream<List<FxRate>>.value(const []),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FirePage(),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders empty state with set-goal CTA when no goal configured',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(await _wrap(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Set your FIRE goal'), findsOneWidget);
    expect(find.text('Set goal'), findsOneWidget);
    expect(find.byType(FireProgressGauge), findsNothing);
  });

  testWidgets('renders the gauge and scenario table once a goal is saved',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.fire.target_amount': '1000000',
      'naviwealth.fire.monthly_expenses': '4000',
      'naviwealth.fire.monthly_surplus': '5000',
      'naviwealth.fire.inflation_rate': 0.03,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(await _wrap(
      prefs: prefs,
      manualAssets: [_cash('cash-1', '200000')],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FireProgressGauge), findsOneWidget);
    // Scenario tier labels appear in the chart legend ("Conservative (3.0%)")
    // and again as standalone labels in the scenarios table further down
    // the list. textContaining matches both forms regardless of which one
    // is currently mounted in the viewport.
    expect(find.textContaining('Conservative'), findsWidgets);
    expect(find.textContaining('Neutral'), findsWidgets);
    expect(find.textContaining('Aggressive'), findsWidgets);

    // Scroll the page until the Edit goal CTA at the bottom of the list
    // appears — under the 800×600 test viewport it sits below the fold.
    final editGoal = find.text('Edit goal');
    await tester.scrollUntilVisible(
      editGoal,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(editGoal, findsOneWidget);
  });

  testWidgets('progress reads back as 100% when net worth meets target',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.fire.target_amount': '100000',
      'naviwealth.fire.monthly_expenses': '0',
      'naviwealth.fire.monthly_surplus': '0',
      'naviwealth.fire.inflation_rate': 0.03,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(await _wrap(
      prefs: prefs,
      manualAssets: [_cash('cash-1', '200000')],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached FIRE"), findsOneWidget);
  });

  testWidgets('saves a goal entered in the goal sheet', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          manualAssetsStreamProvider.overrideWith(
            (ref) => Stream.value(const <Asset>[]),
          ),
          physicalAssetsListProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          liabilitiesStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          fxRatesStreamProvider.overrideWith(
            (ref) => Stream<List<FxRate>>.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return const FirePage();
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set goal'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Target net worth'),
      '500000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = container.read(fireGoalProvider);
    expect(saved.isConfigured, isTrue);
    expect(saved.targetAmount, Decimal.parse('500000'));
    expect(saved, isNot(equals(FireGoal.unset())));
  });
}
