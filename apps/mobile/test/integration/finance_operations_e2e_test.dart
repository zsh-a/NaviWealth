// End-to-end finance operations over the real provider graph and a real
// in-memory Drift database. This covers the accounting spine shared by
// account management, manual cash management, transfers, expenses, trades,
// journal/activity reads, balances, and holdings.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/services/price_resolver.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/domain/values/price_confidence.dart';
import 'package:naviwealth/domain/values/resolved_price.dart';
import 'package:naviwealth/features/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

import 'support/integration_env.dart';

class _FixedPriceResolver implements PriceResolver {
  const _FixedPriceResolver({
    required this.price,
    required this.currency,
    required this.asOf,
  });

  final Decimal price;
  final String currency;
  final DateTime asOf;

  ResolvedPrice _resolved() => ResolvedPrice(
    value: price,
    currency: currency,
    confidence: PriceConfidence.realTime,
    source: 'integration-test',
    asOf: asOf,
    fetchedAt: asOf,
  );

  @override
  Future<ResolvedPrice?> resolve(Asset asset, {DateTime? asOf}) async {
    return _resolved();
  }

  @override
  Future<Map<String, ResolvedPrice?>> resolveMany(
    Iterable<Asset> assets, {
    DateTime? asOf,
  }) async {
    return {for (final asset in assets) asset.id: _resolved()};
  }
}

void main() {
  group('Integration: finance operations end to end', () {
    test('accounts, cash funding, expense, transfer, trade, balances and '
        'holdings stay coherent', () async {
      final env = await IntegrationEnv.create(
        extraOverrides: [
          priceResolverProvider.overrideWith(
            (_) async => _FixedPriceResolver(
              price: Decimal.fromInt(250),
              currency: 'CNY',
              asOf: DateTime.utc(2026, 1, 15),
            ),
          ),
        ],
      );

      final accountRepo = await env.container.read(
        accountRepositoryProvider.future,
      );
      await accountRepo.seedSystemAccounts();
      final checking = await accountRepo.create(
        type: AccountCategory.bank,
        name: 'E2E Checking',
        currency: 'CNY',
      );
      final savings = await accountRepo.create(
        type: AccountCategory.bank,
        name: 'E2E Savings',
        currency: 'CNY',
      );
      final broker = await accountRepo.create(
        type: AccountCategory.broker,
        name: 'E2E Broker',
        currency: 'CNY',
      );

      final securitiesRepo = await env.container.read(
        securitiesAssetRepositoryProvider.future,
      );
      final aapl = await securitiesRepo.upsertSecurity(
        symbol: 'AAPL',
        market: AssetMarket.usStock,
        type: AssetType.stock,
        currency: 'CNY',
        name: 'Apple Inc.',
      );

      final manualRepo = await env.container.read(
        manualAssetRepositoryProvider.future,
      );
      final cashAsset = await manualRepo.createCash(
        accountId: checking.id,
        currency: 'CNY',
        balance: Decimal.fromInt(10000),
        nickname: 'Operating cash',
      );

      final journalRepo = await env.container.read(
        journalEntryRepositoryProvider.future,
      );
      final diningAccountId = AccountRepository.systemAccountIdForPath(
        'expense:dining',
        ownerUserId: 'u-test',
      );
      final expenseBuild = JournalEntryBuilders.expense(
        date: DateTime.utc(2026, 1, 11),
        expenseAccountId: diningAccountId,
        fromAccountId: checking.id,
        amount: Decimal.parse('125.50'),
        currency: 'CNY',
        narration: 'E2E team lunch',
      );
      await journalRepo.create(
        entry: expenseBuild.entry,
        postings: expenseBuild.postings,
      );

      final transferBuild = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 1, 12),
        fromAccountId: checking.id,
        toAccountId: savings.id,
        amount: Decimal.fromInt(1500),
        currency: 'CNY',
        narration: 'E2E reserve transfer',
      );
      await journalRepo.create(
        entry: transferBuild.entry,
        postings: transferBuild.postings,
      );

      final buyBuild = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 1, 13),
        accountId: broker.id,
        cashAccountId: checking.id,
        assetUnit: aapl.id,
        qty: Decimal.fromInt(10),
        price: Decimal.fromInt(200),
        quoteCurrency: 'CNY',
        narration: 'E2E buy AAPL',
      );
      await journalRepo.create(
        entry: buyBuild.entry,
        postings: buyBuild.postings,
      );

      env.keepAlive(accountsStreamProvider);
      env.keepAlive(manualAssetsStreamProvider);
      env.keepAlive(allAssetsStreamProvider);
      env.keepAlive(journalEntriesWithPostingsStreamProvider);
      env.keepAlive(journalExpensesStreamProvider);
      env.keepAlive(accountBalancesByIdProvider);
      env.keepAlive(holdingsSnapshotProvider);

      final accounts = await env.container.read(accountsStreamProvider.future);
      expect(
        accounts.map((account) => account.name),
        containsAll(['E2E Checking', 'E2E Savings', 'E2E Broker']),
      );

      final manualAssets = await env.container.read(
        manualAssetsStreamProvider.future,
      );
      expect(manualAssets.map((asset) => asset.id), contains(cashAsset.id));

      final balances = await env.container.read(
        accountBalancesByIdProvider.future,
      );
      expect(
        balances[checking.id]!.legFor('CNY')!.units,
        Decimal.parse('6374.50'),
      );
      expect(balances[savings.id]!.legFor('CNY')!.units, Decimal.fromInt(1500));
      expect(balances[broker.id]!.legFor(aapl.id)!.units, Decimal.fromInt(10));

      final expenses = await env.container.read(
        journalExpensesStreamProvider.future,
      );
      expect(expenses, hasLength(1));
      expect(expenses.single.note, 'E2E team lunch');
      expect(expenses.single.fromAccountId, checking.id);
      expect(expenses.single.amount, Decimal.parse('125.50'));

      final feed = await journalRepo.queryActivityFeed(
        kinds: {EntryKind.expense},
        accountCategories: {
          checking.id: AccountSide.asset,
          savings.id: AccountSide.asset,
          broker.id: AccountSide.asset,
          diningAccountId: AccountSide.expense,
        },
        pageSize: 10,
      );
      expect(feed.entries.map((entry) => entry.entry.narration), [
        'E2E team lunch',
      ]);

      final holdings = await env.container.read(
        holdingsSnapshotProvider.future,
      );
      final holding = holdings[aapl.id];
      expect(holding, isNotNull);
      expect(holding!.quantity, Decimal.fromInt(10));
      expect(holding.marketValueInBase, Decimal.fromInt(2500));

      final journals = await env.container.read(
        journalEntriesWithPostingsStreamProvider.future,
      );
      expect(journals, hasLength(4));
      expect(
        journals.every((journal) => journal.postings.length >= 2),
        isTrue,
        reason: 'every finance operation must be backed by balanced postings',
      );
    }, tags: 'integration');
  });
}
