import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset_repository.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/assets/physical/ui/valuation_update_sheet.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../../core/persistence/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';

class _ControlledOutbox implements OutboxStore {
  Completer<void>? _firstWrite;
  bool _armed = false;
  int calls = 0;

  Completer<void> arm() {
    _armed = true;
    calls = 0;
    return _firstWrite = Completer<void>();
  }

  @override
  Future<int> depth() async => calls;

  @override
  Future<void> enqueue({required String table, required String rowId}) {
    if (!_armed) return Future<void>.value();
    calls += 1;
    return calls == 1 ? _firstWrite!.future : Future<void>.value();
  }
}

Finder _field(String label) {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(FTextFormField),
  );
  return find.descendant(of: field, matching: find.byType(EditableText));
}

void main() {
  testWidgets(
    'failed valuation remains editable and retries after pending write unlocks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = _ControlledOutbox();
      final stamper = makeStubStamper();
      final priceRepo = PriceRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final repo = PhysicalAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        priceRepo: priceRepo,
      );
      final asset = await repo.createVehicle(
        name: 'Car',
        currency: 'CNY',
        purchaseDate: DateTime.utc(2024, 1, 1),
        purchasePrice: Decimal.parse('30000'),
      );
      final firstWrite = outbox.arm();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            physicalAssetRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => AppMessenger.init(
              child: FTheme(data: FThemes.slate.light.desktop, child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    ValuationUpdateSheet.show(context, asset: asset),
                  ),
                  child: const Text('Open valuation'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open valuation'));
      await tester.pumpAndSettle();

      await tester.enterText(_field('New valuation'), '25000');
      await tester.tap(find.widgetWithText(FButton, 'Save valuation'));
      await tester.pump();

      expect(outbox.calls, 1);
      expect(find.byType(ValuationUpdateSheet), findsOneWidget);
      expect(
        tester
            .widget<FButton>(find.widgetWithText(FButton, 'Save valuation'))
            .onPress,
        isNull,
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ValuationUpdateSheet), findsOneWidget);

      firstWrite.completeError(StateError('write failed'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(ValuationUpdateSheet), findsOneWidget);
      expect(find.text('25000'), findsOneWidget);
      expect(
        find.text("Couldn't save your changes. Try again."),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FButton>(find.widgetWithText(FButton, 'Save valuation'))
            .onPress,
        isNotNull,
      );

      // The error toast intentionally owns pointer input while visible.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Save valuation'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(outbox.calls, greaterThan(1));
      expect(find.byType(ValuationUpdateSheet), findsNothing);
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
