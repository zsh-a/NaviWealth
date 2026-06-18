// Integration test (real Drift): an options trade journal entry mirrors
// premium cash into the forward ledger, and that cash flows into dashboard
// net worth through the existing cash-asset read model.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/options_income/data/providers.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/trade_journal_entry.dart';

import 'support/integration_env.dart';

void main() {
  group('Integration: options journal moves net worth (real Drift)', () {
    test('cash-secured put premium increases dashboard assets', () async {
      final env = await IntegrationEnv.create();

      final accountRepo = await env.container.read(
        accountRepositoryProvider.future,
      );
      final broker = await accountRepo.create(
        type: AccountCategory.broker,
        name: 'Broker',
        currency: 'CNY',
      );
      final cash = await accountRepo.create(
        type: AccountCategory.cash,
        name: 'Options Cash',
        currency: 'CNY',
      );

      final journalRepo = await env.container.read(
        tradeJournalRepositoryProvider.future,
      );
      final ledger = await env.container.read(
        optionsJournalLedgerServiceProvider.future,
      );
      final entry = await journalRepo.create(
        strategy: OptionsStrategyKind.cashSecuredPut,
        symbol: 'AAPL',
        optionSymbol: 'AAPL260619P00190000',
        openedAt: DateTime.utc(2026, 6, 18),
        entryCredit: Decimal.parse('125'),
        currency: 'CNY',
        status: TradeJournalStatus.open,
        brokerageAccountId: broker.id,
        cashAccountId: cash.id,
        underlyingMarket: 'us_stock',
        strikePrice: Decimal.parse('190'),
        contractSize: 100,
      );
      await ledger.mirror(entry);

      env.keepAlive(manualAssetsStreamProvider);
      env.keepAlive(dashboardPriceRowsProvider);
      env.keepAlive(dashboardSnapshotProvider);

      final snapshot = await env.container.read(
        dashboardSnapshotProvider.future,
      );
      expect(snapshot.totalAssets.amount, Decimal.parse('125'));
      expect(snapshot.netWorth.amount, Decimal.parse('125'));
    }, tags: 'integration');

    test('assigned put creates the underlying holding posting', () async {
      final env = await IntegrationEnv.create();

      final accountRepo = await env.container.read(
        accountRepositoryProvider.future,
      );
      final broker = await accountRepo.create(
        type: AccountCategory.broker,
        name: 'Broker',
        currency: 'CNY',
      );
      final cash = await accountRepo.create(
        type: AccountCategory.cash,
        name: 'Options Cash',
        currency: 'CNY',
      );

      final journalRepo = await env.container.read(
        tradeJournalRepositoryProvider.future,
      );
      final ledger = await env.container.read(
        optionsJournalLedgerServiceProvider.future,
      );
      final entry = await journalRepo.create(
        strategy: OptionsStrategyKind.cashSecuredPut,
        symbol: 'AAPL',
        optionSymbol: 'AAPL260619P00190000',
        openedAt: DateTime.utc(2026, 6, 18),
        entryCredit: Decimal.parse('125'),
        currency: 'CNY',
        status: TradeJournalStatus.assigned,
        brokerageAccountId: broker.id,
        cashAccountId: cash.id,
        underlyingMarket: 'us_stock',
        strikePrice: Decimal.parse('190'),
        contractSize: 100,
      );
      await ledger.mirror(entry);

      final rows = await env.db
          .customSelect(
            "SELECT units FROM postings WHERE unit = 'us_stock:AAPL' "
            'AND deleted_at IS NULL',
          )
          .get();
      expect(rows.map((r) => r.read<String>('units')), contains('100'));
    }, tags: 'integration');
  });
}
