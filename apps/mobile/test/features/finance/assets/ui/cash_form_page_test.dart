import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/cash_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _Harness {
  _Harness({required this.db, required this.repository});

  final AppDatabase db;
  final ManualAssetRepository repository;

  static _Harness create() {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    final priceRepository = PriceRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    return _Harness(
      db: db,
      repository: ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        priceRepo: priceRepository,
      ),
    );
  }

  Future<void> dispose() => db.close();
}

Account _bankAccount() => Account(
  id: 'bank-1',
  type: AccountCategory.bank,
  name: 'Everyday bank',
  currency: 'CNY',
  category: AccountSide.asset,
  sync: SyncMeta(
    ownerUserId: 'user-test',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'device-test',
    hlc: Hlc.zero('device-test'),
  ),
);

Future<Widget> _wrap({
  required Future<ManualAssetRepository> repositoryFuture,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      manualAssetRepositoryProvider.overrideWith((_) => repositoryFuture),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value(<Account>[_bankAccount()]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: const CashFormPage(),
      ),
    ),
  );
}

void _expectSubmitWiring(WidgetTester tester, {required bool enabled}) {
  final body = tester.widget<AppFormScaffoldBody>(
    find.byType(AppFormScaffoldBody),
  );
  final button = tester.widget<FButton>(
    find.descendant(
      of: find.byType(AppFormActionBar),
      matching: find.byType(FButton),
    ),
  );
  if (enabled) {
    expect(body.onSubmit, isNotNull);
    expect(button.onPress, isNotNull);
  } else {
    expect(body.onSubmit, isNull);
    expect(button.onPress, isNull);
  }
}

void main() {
  late _Harness harness;

  setUp(() {
    harness = _Harness.create();
  });

  tearDown(() => harness.dispose());

  testWidgets('cash fields stay locked while duplicate lookup is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = Completer<ManualAssetRepository>();
    addTearDown(() {
      if (!repository.isCompleted) repository.complete(harness.repository);
    });

    await tester.pumpWidget(await _wrap(repositoryFuture: repository.future));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Checking this account for an existing cash balance…'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('cash-balance-field')), findsNothing);
    expect(find.byKey(const Key('cash-nickname-field')), findsNothing);
    _expectSubmitWiring(tester, enabled: false);

    repository.complete(harness.repository);
    await tester.pumpAndSettle();

    expect(
      find.text('Checking this account for an existing cash balance…'),
      findsNothing,
    );
    expect(find.byKey(const Key('cash-balance-field')), findsOneWidget);
    expect(find.byKey(const Key('cash-nickname-field')), findsOneWidget);
    _expectSubmitWiring(tester, enabled: true);
  });

  testWidgets('duplicate lookup failure restores the editable form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = Completer<ManualAssetRepository>();

    await tester.pumpWidget(await _wrap(repositoryFuture: repository.future));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('cash-balance-field')), findsNothing);

    repository.completeError(StateError('repository unavailable'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cash-balance-field')), findsOneWidget);
    expect(find.byKey(const Key('cash-nickname-field')), findsOneWidget);
    expect(find.textContaining('Failed to load:'), findsOneWidget);
    _expectSubmitWiring(tester, enabled: true);
    await tester.pump(const Duration(seconds: 7));
  });
}
