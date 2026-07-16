import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/fire/data/fire_goal_preferences.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_page.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_state_hero_card.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 4, 1),
  updatedByDevice: 't',
  hlc: Hlc.zero('t'),
);

Asset _cash(String id) => Asset(
  id: id,
  type: AssetType.cash,
  symbol: id,
  currency: 'CNY',
  sync: _meta(),
);

FireState _stubFireState(FireGoal goal, {Decimal? currentNetWorth}) {
  final plan = FirePlan.fromGoal(goal, baseCurrency: 'CNY');
  final nw = currentNetWorth ?? Decimal.zero;
  final configured = goal.isConfigured;
  return FireState(
    plan: plan,
    baseCurrency: 'CNY',
    netWorth: Money(nw, 'CNY'),
    investableAssets: Money(nw, 'CNY'),
    liquidAssets: Money(Decimal.parse('36000'), 'CNY'),
    annualSpend: Money((goal.monthlyExpenses * Decimal.fromInt(12)), 'CNY'),
    monthlyExpense: Money(goal.monthlyExpenses, 'CNY'),
    withdrawalRate: configured ? 0.0615 : 0,
    cashBucketMonths: configured ? 9.0 : 0,
    fireEtaMonths: configured ? 84 : null,
    safetyLevel: configured
        ? FireSafetyLevel.cautious
        : FireSafetyLevel.unconfigured,
    suggestedActions: const [],
    stressTests: const [],
    currencyMismatchCount: 0,
    computedAt: DateTime.utc(2026, 5, 6),
  );
}

Future<Widget> _wrap({
  required SharedPreferences prefs,
  List<Asset> manualAssets = const [],
  FireGoal? goal,
  Decimal? currentNetWorth,
  BudgetSignal budgetSignal = BudgetSignal.noData,
}) async {
  final resolvedGoal = goal ?? FireGoal.unset();
  final nw = currentNetWorth ?? Decimal.zero;
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      fireDashboardViewProvider.overrideWith(
        (ref) => AsyncValue.data(_view(resolvedGoal, currentNetWorth: nw)),
      ),
      fireStateProvider.overrideWith(
        (ref) =>
            AsyncValue.data(_stubFireState(resolvedGoal, currentNetWorth: nw)),
      ),
      fireBudgetSignalProvider.overrideWith(
        (ref) => AsyncValue.data(budgetSignal),
      ),
      manualAssetsStreamProvider.overrideWith(
        (ref) => Stream.value(manualAssets),
      ),
      dashboardManualAssetValuationsProvider.overrideWith(
        (ref) => const AsyncValue.data(<ManualAssetValuation>[]),
      ),
      physicalAssetsListProvider.overrideWith((ref) => Stream.value(const [])),
      liabilitiesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      fxRatesStreamProvider.overrideWith(
        (ref) => Stream<List<FxRate>>.value(const []),
      ),
      allAssetsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      allAccountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      journalEntriesWithPostingsStreamProvider.overrideWith(
        (ref) => Stream.value(const <JournalEntryWithPostings>[]),
      ),
      holdingsSnapshotProvider.overrideWith(
        (ref) async => const <String, HoldingSnapshot>{},
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

  testWidgets('renders empty state with set-goal CTA when no goal configured', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(await _wrap(prefs: prefs));
    await _pumpFrames(tester);

    expect(find.text('Set your FIRE goal'), findsOneWidget);
    expect(find.text('Set goal'), findsOneWidget);
    expect(find.byType(FireStateHeroCard), findsNothing);
  });

  testWidgets(
    'renders hero, projection legend, and header edit once configured',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'naviwealth.fire.target_amount': '1000000',
        'naviwealth.fire.monthly_expenses': '4000',
        'naviwealth.fire.monthly_surplus': '5000',
        'naviwealth.fire.inflation_rate': 0.03,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        await _wrap(
          prefs: prefs,
          manualAssets: [_cash('cash-1')],
          goal: FireGoal(
            targetAmount: Decimal.parse('1000000'),
            monthlyExpenses: Decimal.parse('4000'),
            monthlySurplus: Decimal.parse('5000'),
            inflationRate: 0.03,
          ),
          currentNetWorth: Decimal.parse('250000'),
        ),
      );
      await _pumpFrames(tester);

      expect(find.byType(FireStateHeroCard), findsOneWidget);
      // Scenario tier labels appear in the chart legend ("Conservative (3.0%)").
      expect(find.textContaining('Conservative'), findsWidgets);
      expect(find.textContaining('Neutral'), findsWidgets);
      expect(find.textContaining('Aggressive'), findsWidgets);

      // Edit lives in the app-bar as a pencil action (no bottom CTA).
      expect(find.byIcon(FLucideIcons.pencil), findsOneWidget);
    },
  );

  for (final (signal, expectedTitle) in const [
    (BudgetSignal.noData, 'Budget signal not available'),
    (BudgetSignal.comfortable, 'Budget supports the plan'),
    (BudgetSignal.strained, 'Budget pressure is rising'),
    (BudgetSignal.overBudget, 'Monthly budget exceeded'),
  ]) {
    testWidgets('renders ${signal.name} budget posture on configured FIRE', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(
          prefs: prefs,
          goal: FireGoal(
            targetAmount: Decimal.parse('1000000'),
            monthlyExpenses: Decimal.parse('4000'),
            monthlySurplus: Decimal.parse('5000'),
            inflationRate: 0.03,
          ),
          currentNetWorth: Decimal.parse('250000'),
          budgetSignal: signal,
        ),
      );
      await _pumpFrames(tester);

      expect(find.byKey(const ValueKey('fire-budget-posture')), findsOneWidget);
      expect(find.text(expectedTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saves a goal entered in the goal sheet', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fireDashboardViewProvider.overrideWith(
            (ref) => AsyncValue.data(_view(FireGoal.unset())),
          ),
          manualAssetsStreamProvider.overrideWith(
            (ref) => Stream.value(const <Asset>[]),
          ),
          dashboardManualAssetValuationsProvider.overrideWith(
            (ref) => const AsyncValue.data(<ManualAssetValuation>[]),
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
          allAssetsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          allAccountsStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          journalEntriesWithPostingsStreamProvider.overrideWith(
            (ref) => Stream.value(const <JournalEntryWithPostings>[]),
          ),
          holdingsSnapshotProvider.overrideWith(
            (ref) async => const <String, HoldingSnapshot>{},
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context, listen: false);
              return const FirePage();
            },
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('Set goal'));
    await _pumpFrames(tester);

    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Target net worth'),
      '500000',
    );
    await tester.tap(find.text('Save'));
    await _pumpFrames(tester);

    final saved = container.read(fireGoalProvider);
    expect(saved.isConfigured, isTrue);
    expect(saved.targetAmount, Decimal.parse('500000'));
    expect(saved, isNot(equals(FireGoal.unset())));
  });
}

FireDashboardView _view(FireGoal goal, {Decimal? currentNetWorth}) {
  return const FireCalculator().buildView(
    goal: goal,
    currentNetWorth: currentNetWorth ?? Decimal.zero,
    baseCurrency: 'CNY',
    start: DateTime(2026, 5, 6),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}
