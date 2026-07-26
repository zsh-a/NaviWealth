import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_detail_page.dart';
import 'package:naviwealth/features/finance/assets/ui/manual_asset_detail_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _ControlledValuationRepository extends ManualAssetRepository {
  _ControlledValuationRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
    required super.priceRepo,
    required this.results,
  });

  final List<Future<Decimal?> Function()> results;

  @override
  Future<Decimal?> latestValuation(String assetId, {DateTime? asOf}) {
    return results.removeAt(0)();
  }
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user-test',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'device-test',
  hlc: Hlc.zero('device-test'),
);

Account _account() => Account(
  id: 'bank-1',
  type: AccountCategory.bank,
  name: 'Everyday bank',
  currency: 'CNY',
  category: AccountSide.asset,
  sync: _meta(),
);

Asset _deposit() => Asset(
  id: 'deposit-1',
  type: AssetType.bankDepositTerm,
  symbol: 'deposit-1',
  name: 'One-year deposit',
  currency: 'CNY',
  metadataJson: DepositMetadata(
    accountId: 'bank-1',
    principal: Decimal.parse('10000'),
    interestRate: Decimal.parse('0.025'),
  ).encode(),
  sync: _meta(),
);

Widget _app({
  required SharedPreferences preferences,
  required GoRouter router,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      routerConfig: router,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cash account detail exposes the balance editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = await SharedPreferences.getInstance();
    final account = _account();
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => const AccountDetailPage(
            accountId: 'bank-1',
            cashAssetId: 'cash-1',
          ),
        ),
        GoRoute(
          path: '/wealth/assets/:id/edit',
          builder: (_, state) => Text('edit-${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        preferences: preferences,
        router: router,
        overrides: [
          accountsStreamProvider.overrideWith((_) => Stream.value([account])),
          accountBalancesByIdProvider.overrideWith(
            (_) => Stream.value({
              account.id: AccountBalances(
                accountId: account.id,
                legs: [
                  AccountBalanceLeg(unit: 'CNY', units: Decimal.parse('12500')),
                ],
              ),
            }),
          ),
          journalEntriesWithPostingsStreamProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adjust balance'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('account-adjust-cash-balance')));
    await tester.pumpAndSettle();

    expect(find.text('edit-cash-1'), findsOneWidget);
  });

  testWidgets(
    'manual asset valuation failure retries into an editable detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = InMemoryOutboxStore();
      final stamper = makeStubStamper();
      final repository = _ControlledValuationRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        priceRepo: PriceRepository(db: db, outbox: outbox, stamper: stamper),
        results: [
          () => Future<Decimal?>.error(StateError('valuation unavailable')),
          () => Future<Decimal?>.value(Decimal.parse('12500')),
        ],
      );
      final asset = _deposit();
      final router = GoRouter(
        initialLocation: '/detail',
        routes: [
          GoRoute(
            path: '/detail',
            builder: (_, _) =>
                ManualAssetDetailPage(asset: asset, repository: repository),
          ),
          GoRoute(
            path: '/wealth/assets/:id/edit',
            builder: (_, state) => Text('edit-${state.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(
          preferences: preferences,
          router: router,
          overrides: [
            accountsStreamProvider.overrideWith(
              (_) => Stream.value(<Account>[_account()]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.byKey(const Key('manual-asset-edit-primary')),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('manual-asset-edit-primary')),
        findsOneWidget,
      );
      expect(
        tester.widget<AnimatedMoneyText>(find.byType(AnimatedMoneyText)).amount,
        12500,
      );
      await tester.tap(find.byKey(const Key('manual-asset-edit-primary')));
      await tester.pumpAndSettle();

      expect(find.text('edit-deposit-1'), findsOneWidget);
    },
  );
}
