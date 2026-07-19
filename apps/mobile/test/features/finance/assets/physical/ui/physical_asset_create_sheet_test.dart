import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset_repository.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/assets/physical/ui/physical_asset_create_sheet.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap({
  required AssetType type,
  required FormDirtyController dirty,
  Future<PhysicalAssetRepository>? repository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      if (repository != null)
        physicalAssetRepositoryProvider.overrideWith((_) => repository),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: PhysicalAssetCreateSheet(type: type, dirty: dirty),
      ),
    ),
  );
}

void main() {
  testWidgets('vehicle setup is concise and stacks purchase fields on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    await tester.pumpWidget(await _wrap(type: AssetType.vehicle, dirty: dirty));
    await tester.pumpAndSettle();

    final toggle = tester.widget<Semantics>(
      find.byKey(const Key('physical-asset-details-toggle-label')),
    );
    final fields = tester.widget<Offstage>(
      find.byKey(const Key('physical-asset-details-fields')),
    );
    expect(toggle.properties.expanded, isFalse);
    expect(fields.offstage, isTrue);
    expect(find.text('Valuation & depreciation'), findsOneWidget);
    expect(find.text('Name *', findRichText: true), findsOneWidget);
    expect(find.text('Currency *', findRichText: true), findsOneWidget);
    expect(find.text('Purchase price *', findRichText: true), findsOneWidget);
    expect(
      find.text(
        'Annual residual rate *',
        findRichText: true,
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    final currencyTop = tester.getTopLeft(
      find.byKey(const Key('physical-asset-currency-field')),
    );
    final dateTop = tester.getTopLeft(
      find.byKey(const Key('physical-asset-purchase-date-field')),
    );
    expect(dateTop.dy, greaterThan(currencyTop.dy));
  });

  testWidgets('hidden depreciation errors reveal vehicle details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    await tester.pumpWidget(await _wrap(type: AssetType.vehicle, dirty: dirty));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('physical-asset-name-field')),
      'Family car',
    );
    await tester.enterText(
      find.byKey(const Key('physical-asset-purchase-price-field')),
      '180000',
    );
    final residualInput = find.descendant(
      of: find.byKey(
        const Key('physical-asset-residual-rate-field'),
        skipOffstage: false,
      ),
      matching: find.byType(EditableText, skipOffstage: false),
    );
    tester.widget<EditableText>(residualInput).controller.text = '1.2';
    await tester.pump();

    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pump();

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('physical-asset-details-toggle-label')),
          )
          .properties
          .expanded,
      isTrue,
    );
    expect(
      tester
          .widget<Offstage>(
            find.byKey(const Key('physical-asset-details-fields')),
          )
          .offstage,
      isFalse,
    );
    expect(find.text('Must be between 0 and 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('real-estate details use a purpose-specific summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    await tester.pumpWidget(
      await _wrap(type: AssetType.realEstate, dirty: dirty),
    );
    await tester.pumpAndSettle();

    expect(find.text('Address, valuation & linked loan'), findsOneWidget);
    expect(
      find.byKey(
        const Key('physical-asset-address-field'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed create stays editable and re-enables submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dirty = FormDirtyController();
    addTearDown(dirty.dispose);
    final repository = Completer<PhysicalAssetRepository>();
    addTearDown(() {
      if (!repository.isCompleted) {
        repository.completeError(StateError('test ended'));
      }
    });
    await tester.pumpWidget(
      await _wrap(
        type: AssetType.vehicle,
        dirty: dirty,
        repository: repository.future,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('physical-asset-name-field')),
      'Family car',
    );
    await tester.enterText(
      find.byKey(const Key('physical-asset-purchase-price-field')),
      '180000',
    );
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pump();
    repository.completeError(StateError('write failed'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PhysicalAssetCreateSheet), findsOneWidget);
    expect(find.text('Family car'), findsOneWidget);
    expect(find.text("Couldn't save your changes. Try again."), findsOneWidget);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNotNull,
    );
    await tester.pump(const Duration(seconds: 7));
  });
}
