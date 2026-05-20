import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/rebalance/domain/allocation_schemes.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/rebalance/ui/rebalance_page.dart';
import 'package:naviwealth/features/rebalance/ui/target_allocation_editor_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves a valid custom target and selects the custom preset', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);

    await _pumpWithContainer(
      tester,
      container,
      SingleChildScrollView(child: TargetAllocationEditorSheet(dirty: dirty)),
    );

    await _enterAllocation(tester, AssetCategory.stock, '34');
    await _enterAllocation(tester, AssetCategory.etf, '16');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      container.read(selectedSchemeProvider),
      AllocationSchemePreset.custom,
    );
    final saved = container.read(targetAllocationProvider);
    expect(saved[AssetCategory.stock], closeTo(0.34, 0.001));
    expect(saved[AssetCategory.etf], closeTo(0.16, 0.001));
    expect(saved.isValid, isTrue);
  });

  testWidgets('keeps invalid totals from saving and shows the total hint', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);

    await _pumpWithContainer(
      tester,
      container,
      SingleChildScrollView(child: TargetAllocationEditorSheet(dirty: dirty)),
    );

    await _enterAllocation(tester, AssetCategory.stock, '50');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Total must be 100%. Current total: 115.0%.'),
      findsOneWidget,
    );
    expect(
      container.read(selectedSchemeProvider),
      AllocationSchemePreset.balanced,
    );
  });

  testWidgets('opens from Rebalance and guards dirty dismissals', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rebalancePlanProvider.overrideWithValue(_plan),
      ],
    );
    addTearDown(container.dispose);

    await _pumpWithContainer(tester, container, const RebalancePage());

    await tester.tap(find.text('Custom target'));
    await tester.pumpAndSettle();
    expect(find.text('Custom target'), findsWidgets);

    await _enterAllocation(tester, AssetCategory.stock, '34');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });
}

Future<void> _pumpWithContainer(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterAllocation(
  WidgetTester tester,
  AssetCategory category,
  String value,
) async {
  final fieldHost = find.byKey(
    ValueKey('target-allocation-field-${category.name}'),
  );
  await tester.ensureVisible(fieldHost);
  await tester.pumpAndSettle();
  final field = find.descendant(
    of: fieldHost,
    matching: find.byType(EditableText),
  );
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Save');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
}

final _plan = RebalancePlan(
  target: allocationScheme(AllocationSchemePreset.balanced),
  actualWeights: const {
    AssetCategory.stock: 0.50,
    AssetCategory.etf: 0.10,
    AssetCategory.bondsAndFunds: 0.10,
    AssetCategory.cash: 0.15,
    AssetCategory.crypto: 0.05,
    AssetCategory.realEstate: 0.05,
    AssetCategory.vehicle: 0.05,
  },
  drifts: const [
    Drift(
      category: AssetCategory.stock,
      actualWeight: 0.50,
      targetWeight: 0.35,
      severity: DriftSeverity.critical,
    ),
    Drift(
      category: AssetCategory.bondsAndFunds,
      actualWeight: 0.10,
      targetWeight: 0.20,
      severity: DriftSeverity.critical,
    ),
  ],
  trades: [
    SuggestedTrade(
      category: AssetCategory.stock,
      direction: TradeDirection.sell,
      amount: Money(Decimal.parse('1500'), 'USD'),
    ),
  ],
  estimatedFees: Money(Decimal.parse('1.5'), 'USD'),
  estimatedTaxes: Money(Decimal.parse('1.5'), 'USD'),
  driftBeforePct: 0.25,
  driftAfterPct: 0.01,
  totalAssets: Money(Decimal.parse('10000'), 'USD'),
);
