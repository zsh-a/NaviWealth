import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/ui/target_allocation_editor_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves a valid target without changing global preferences', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
      ],
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

    final saved = container.read(targetAllocationProvider);
    expect(saved[AssetCategory.stock], closeTo(0.34, 0.001));
    expect(saved[AssetCategory.etf], closeTo(0.16, 0.001));
    expect(saved.isValid, isTrue);
  });

  testWidgets('keeps invalid totals from saving and shows the total hint', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
      ],
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
    expect(container.read(targetAllocationProvider).isValid, isTrue);
  });

  testWidgets('adds and saves a single asset target', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
        dashboardSnapshotProvider.overrideWithValue(
          AsyncValue.data(_snapshotWithQqq()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);

    await _pumpWithContainer(
      tester,
      container,
      SingleChildScrollView(child: TargetAllocationEditorSheet(dirty: dirty)),
    );

    await _enterAllocation(tester, AssetCategory.stock, '0');
    await _enterAllocation(tester, AssetCategory.etf, '0');
    await tester.ensureVisible(find.text('Add asset target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add asset target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QQQ'));
    await tester.pumpAndSettle();
    await _enterAssetAllocation(tester, 'qqq', '50');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final saved = container.read(targetAllocationProvider);
    expect(saved.isValid, isTrue);
    expect(saved[AssetCategory.stock], 0);
    expect(saved[AssetCategory.etf], 0);
    expect(saved.assetTargets['qqq']?.label, 'QQQ');
    expect(saved.assetTargets['qqq']?.weight, 0.5);
  });

  testWidgets('guards dirty dismissals', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
      ],
    );
    addTearDown(container.dispose);

    await _pumpWithContainer(
      tester,
      container,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTargetAllocationEditorSheet(context: context),
          child: const Text('Open editor'),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Custom target'), findsOneWidget);

    await _enterAllocation(tester, AssetCategory.stock, '34');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });
}

Future<void> _enterAssetAllocation(
  WidgetTester tester,
  String assetId,
  String value,
) async {
  final fieldHost = find.byKey(
    ValueKey('target-allocation-field-asset-$assetId'),
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
    ValueKey('target-allocation-field-category-${category.name}'),
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

DashboardSnapshot _snapshotWithQqq() {
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 30),
    baseCurrency: 'USD',
    allocations: [
      CategoryAllocation(
        category: AssetCategory.etf,
        totalInBase: Money(Decimal.parse('1000'), 'USD'),
        items: [
          CategoryItem(
            id: 'qqq',
            name: 'QQQ',
            subtitle: '10 · USD',
            valueInBase: Money(Decimal.parse('1000'), 'USD'),
            nativeAmount: Decimal.parse('1000'),
            nativeCurrency: 'USD',
          ),
        ],
      ),
    ],
    totalAssets: Money(Decimal.parse('1000'), 'USD'),
    totalLiabilities: Money.zero('USD'),
    netWorth: Money(Decimal.parse('1000'), 'USD'),
  );
}
