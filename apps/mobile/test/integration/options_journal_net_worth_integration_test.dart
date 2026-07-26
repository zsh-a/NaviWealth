// Integration test (real Drift): an options trade journal entry mirrors
// premium cash into the forward ledger, and that cash flows into dashboard
// net worth through the existing cash-asset read model.

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

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

    test(
      'close debit mirrors cash outflow and is removed when reopened',
      () async {
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
        final opened = await journalRepo.create(
          strategy: OptionsStrategyKind.cashSecuredPut,
          symbol: 'AAPL',
          optionSymbol: 'AAPL260619P00190000',
          openedAt: DateTime.utc(2026, 6, 18),
          entryCredit: Decimal.parse('125'),
          currency: 'CNY',
          brokerageAccountId: broker.id,
          cashAccountId: cash.id,
          underlyingMarket: 'us_stock',
          strikePrice: Decimal.parse('190'),
          contractSize: 100,
        );
        final entry = await journalRepo.update(
          opened.copyWith(
            closedAt: DateTime.utc(2026, 6, 19),
            exitDebit: Decimal.parse('40'),
            realizedPnl: Decimal.parse('85'),
            status: TradeJournalStatus.closed,
          ),
        );

        await ledger.mirror(entry);

        final closeDebitId = 'options:${entry.id}:closeDebit';
        final closePostings = await env.db
            .customSelect(
              '''
            SELECT account_id, units, unit
            FROM postings
            WHERE journal_entry_id = ? AND deleted_at IS NULL
            ORDER BY position
            ''',
              variables: [Variable.withString(closeDebitId)],
            )
            .get();
        expect(closePostings, hasLength(2));
        expect(closePostings[0].read<String>('account_id'), contains('income'));
        expect(closePostings[0].read<String>('units'), '40');
        expect(closePostings[0].read<String>('unit'), 'CNY');
        expect(closePostings[1].read<String>('account_id'), cash.id);
        expect(closePostings[1].read<String>('units'), '-40');
        expect(closePostings[1].read<String>('unit'), 'CNY');

        await ledger.mirror(entry.copyWith(status: TradeJournalStatus.open));

        final deletedRows = await env.db
            .customSelect(
              'SELECT deleted_at FROM journal_entries WHERE id = ?',
              variables: [Variable.withString(closeDebitId)],
            )
            .get();
        expect(deletedRows, hasLength(1));
        expect(deletedRows.single.read<DateTime?>('deleted_at'), isNotNull);
        expect(
          await env.db
              .customSelect(
                'SELECT id FROM postings '
                'WHERE journal_entry_id = ? AND deleted_at IS NULL',
                variables: [Variable.withString(closeDebitId)],
              )
              .get(),
          isEmpty,
        );
      },
      tags: 'integration',
    );

    test('missing cash account removes existing ledger mirrors', () async {
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
      final mirrorId = 'options:${entry.id}:premium';
      expect(
        await env.db
            .customSelect(
              'SELECT id FROM journal_entries '
              'WHERE id = ? AND deleted_at IS NULL',
              variables: [Variable.withString(mirrorId)],
            )
            .get(),
        hasLength(1),
      );

      await ledger.mirror(entry.copyWith(cashAccountId: ''));

      final rows = await env.db
          .customSelect(
            'SELECT deleted_at FROM journal_entries WHERE id = ?',
            variables: [Variable.withString(mirrorId)],
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<DateTime?>('deleted_at'), isNotNull);
      expect(
        await env.db
            .customSelect(
              'SELECT id FROM postings '
              'WHERE journal_entry_id = ? AND deleted_at IS NULL',
              variables: [Variable.withString(mirrorId)],
            )
            .get(),
        isEmpty,
      );
    }, tags: 'integration');

    test(
      'LEAPS open and close mirror one option lot and cash legs',
      () async {
        final env = await IntegrationEnv.create();
        final accountRepo = await env.container.read(
          accountRepositoryProvider.future,
        );
        final broker = await accountRepo.create(
          type: AccountCategory.broker,
          name: 'Broker',
          currency: 'USD',
        );
        final cash = await accountRepo.create(
          type: AccountCategory.cash,
          name: 'Options Cash',
          currency: 'USD',
        );
        final repo = await env.container.read(
          leapsCallPositionRepositoryProvider.future,
        );
        final ledger = await env.container.read(
          optionsJournalLedgerServiceProvider.future,
        );
        final opened = await repo.create(
          symbol: 'AAPL',
          optionSymbol: 'AAPL280120C00200000',
          openedAt: DateTime.utc(2026, 7, 1),
          expirationAt: DateTime.utc(2028, 1, 20),
          strikePrice: Decimal.fromInt(200),
          entryDebit: Decimal.fromInt(25),
          fees: Decimal.one,
          contractQuantity: 2,
          brokerageAccountId: broker.id,
          cashAccountId: cash.id,
          underlyingMarket: 'us_stock',
        );
        await ledger.mirrorLeaps(opened);

        final openRows = await env.db
            .customSelect(
              '''
            SELECT units, unit FROM postings
            WHERE journal_entry_id = ? AND deleted_at IS NULL
            ORDER BY position
            ''',
              variables: [
                Variable.withString('options:${opened.id}:leapsOpen'),
              ],
            )
            .get();
        expect(openRows.map((row) => row.read<String>('units')), ['2', '-51']);
        expect(openRows.first.read<String>('unit'), 'option:${opened.id}');

        final closed = await repo.update(
          opened.copyWith(
            status: LeapsCallStatus.closed,
            closedAt: DateTime.utc(2027, 7, 1),
            exitCredit: Decimal.fromInt(40),
          ),
        );
        await ledger.mirrorLeaps(closed);
        final closeRows = await env.db
            .customSelect(
              '''
            SELECT units, unit FROM postings
            WHERE journal_entry_id = ? AND deleted_at IS NULL
            ORDER BY position
            ''',
              variables: [
                Variable.withString('options:${opened.id}:leapsClose'),
              ],
            )
            .get();
      expect(closeRows.map((row) => row.read<String>('units')), [
        '-2',
        '-29',
        '80',
      ]);
      },
      tags: 'integration',
    );

    test(
      'LEAPS exercise rolls premium into underlying share basis',
      () async {
        final env = await IntegrationEnv.create();
        final accountRepo = await env.container.read(
          accountRepositoryProvider.future,
        );
        final broker = await accountRepo.create(
          type: AccountCategory.broker,
          name: 'Broker',
          currency: 'USD',
        );
        final cash = await accountRepo.create(
          type: AccountCategory.cash,
          name: 'Options Cash',
          currency: 'USD',
        );
        final repo = await env.container.read(
          leapsCallPositionRepositoryProvider.future,
        );
        final ledger = await env.container.read(
          optionsJournalLedgerServiceProvider.future,
        );
        final opened = await repo.create(
          symbol: 'AAPL',
          optionSymbol: 'AAPL280120C00200000',
          openedAt: DateTime.utc(2026, 7, 1),
          expirationAt: DateTime.utc(2028, 1, 20),
          strikePrice: Decimal.fromInt(200),
          entryDebit: Decimal.fromInt(25),
          contractQuantity: 1,
          contractSize: 100,
          brokerageAccountId: broker.id,
          cashAccountId: cash.id,
          underlyingMarket: 'us_stock',
        );
        await ledger.mirrorLeaps(opened);
        await ledger.mirrorLeaps(
          await repo.update(
            opened.copyWith(
              status: LeapsCallStatus.exercised,
              closedAt: DateTime.utc(2028, 1, 10),
            ),
          ),
        );

        final rows = await env.db
            .customSelect(
              '''
            SELECT units, unit FROM postings
            WHERE journal_entry_id = ? AND deleted_at IS NULL
            ORDER BY position
            ''',
              variables: [
                Variable.withString('options:${opened.id}:leapsClose'),
              ],
            )
            .get();
        expect(rows.map((row) => row.read<String>('unit')), [
          'option:${opened.id}',
          'us_stock:AAPL',
          'USD',
        ]);
        expect(rows.map((row) => row.read<String>('units')), [
          '-1',
          '100',
          '-20000',
        ]);
      },
      tags: 'integration',
    );
  });
}
