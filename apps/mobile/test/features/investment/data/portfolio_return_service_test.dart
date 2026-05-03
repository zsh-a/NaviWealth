import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/investment/data/portfolio_return_service.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/returns/xirr_engine.dart';

import '../../../data/db/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    return Decimal.one;
  }
}

class _MapConverter implements CurrencyConverter {
  const _MapConverter(this.rates);

  final Map<String, Decimal> rates;

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    if (amount.currency == to) return amount;
    final rate = rates['${amount.currency}:$to'];
    if (rate == null) throw FxRateNotFoundError(amount.currency, to, on);
    return Money(amount.amount * rate, to);
  }
}

class _FakeHoldingService implements HoldingService {
  _FakeHoldingService(this.valuesByDay, {required this.baseCurrency});

  final Map<DateTime, Decimal> valuesByDay;
  final String baseCurrency;

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async {
    final day = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final value = valuesByDay[day] ?? Decimal.zero;
    if (value == Decimal.zero) return const {};
    return {
      'NASDAQ:AAPL': HoldingSnapshot(
        assetId: 'NASDAQ:AAPL',
        quantity: Decimal.one,
        costBasisInAssetCurrency: value,
        marketValueInAssetCurrency: value,
        assetCurrency: baseCurrency,
        costBasisInBase: value,
        marketValueInBase: value,
        unrealizedPnlInBase: Decimal.zero,
        weight: Decimal.one,
        baseCurrency: baseCurrency,
        asOf: asOf,
      ),
    };
  }

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async {
    return LotInventorySnapshot(
      ownerUserId: 'u-test',
      day: day,
      lots: const [],
    );
  }
}

void main() {
  late AppDatabase db;
  late JournalEntryRepository repo;

  setUp(() async {
    db = makeTestDatabase();
    repo = JournalEntryRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'USD',
    );
    await _seedAccounts(db);
    await _seedSecurity(db, currency: 'USD');
  });

  tearDown(() async {
    await db.close();
  });

  test('buy cash outflow includes same-currency fees from postings', () async {
    final build = JournalEntryBuilders.buy(
      date: DateTime.utc(2026, 1, 10),
      accountId: 'broker',
      cashAccountId: 'cash',
      assetUnit: 'NASDAQ:AAPL',
      qty: Decimal.parse('100'),
      price: Decimal.parse('10'),
      quoteCurrency: 'USD',
      feeAmount: Decimal.parse('5'),
      feeAccountId: 'fee',
    );
    await repo.create(entry: build.entry, postings: build.postings);

    final service = LedgerPortfolioReturnService(
      db: db,
      ownerUserId: 'u-test',
      baseCurrency: 'USD',
      holdings: _FakeHoldingService({
        DateTime.utc(2026, 12, 31): Decimal.parse('1200'),
      }, baseCurrency: 'USD'),
      converter: const _MapConverter({}),
    );

    final result = await service.compute(
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 12, 31),
    );

    expect(result.cashFlows.map((f) => f.amount), [-1005.0, 1200.0]);
    expect(result.solution, isA<XirrConverged>());
    expect(result.displayReturn, isNotNull);
  });

  test(
    'sell cash inflow is net of fee and ignores income/expense legs',
    () async {
      final build = JournalEntryBuilders.sell(
        date: DateTime.utc(2026, 6, 1),
        accountId: 'broker',
        cashAccountId: 'cash',
        capitalGainsAccountId: 'capital-gains',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('50'),
        price: Decimal.parse('12'),
        quoteCurrency: 'USD',
        costPerUnit: Decimal.parse('10'),
        costCurrency: 'USD',
        feeAmount: Decimal.parse('5'),
        feeAccountId: 'fee',
      );
      await repo.create(entry: build.entry, postings: build.postings);

      final service = LedgerPortfolioReturnService(
        db: db,
        ownerUserId: 'u-test',
        baseCurrency: 'USD',
        holdings: _FakeHoldingService({
          DateTime.utc(2026, 1, 1): Decimal.parse('1000'),
          DateTime.utc(2026, 12, 31): Decimal.parse('700'),
        }, baseCurrency: 'USD'),
        converter: const _MapConverter({}),
      );

      final result = await service.compute(
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 12, 31),
      );

      expect(result.cashFlows.map((f) => f.amount), [-1000.0, 595.0, 700.0]);
      expect(result.solution, isA<XirrConverged>());
    },
  );

  test(
    'cross-currency cash flows convert into the requested base currency',
    () async {
      final build = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 1, 10),
        accountId: 'broker',
        cashAccountId: 'cash',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('100'),
        price: Decimal.parse('10'),
        quoteCurrency: 'USD',
      );
      await repo.create(entry: build.entry, postings: build.postings);

      final service = LedgerPortfolioReturnService(
        db: db,
        ownerUserId: 'u-test',
        baseCurrency: 'CNY',
        holdings: _FakeHoldingService({
          DateTime.utc(2026, 12, 31): Decimal.parse('8400'),
        }, baseCurrency: 'CNY'),
        converter: _MapConverter({'USD:CNY': Decimal.parse('7')}),
      );

      final result = await service.compute(
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 12, 31),
      );

      expect(result.cashFlows.map((f) => f.amount), [-7000.0, 8400.0]);
      expect(result.displayReturn, isNotNull);
    },
  );

  test('missing FX makes the display return incomplete', () async {
    final build = JournalEntryBuilders.buy(
      date: DateTime.utc(2026, 1, 10),
      accountId: 'broker',
      cashAccountId: 'cash',
      assetUnit: 'NASDAQ:AAPL',
      qty: Decimal.parse('100'),
      price: Decimal.parse('10'),
      quoteCurrency: 'USD',
    );
    await repo.create(entry: build.entry, postings: build.postings);

    final service = LedgerPortfolioReturnService(
      db: db,
      ownerUserId: 'u-test',
      baseCurrency: 'CNY',
      holdings: _FakeHoldingService({
        DateTime.utc(2026, 12, 31): Decimal.parse('8400'),
      }, baseCurrency: 'CNY'),
      converter: const _MapConverter({}),
    );

    final result = await service.compute(
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 12, 31),
    );

    expect(result.missingCurrencies, {'USD'});
    expect(result.displayReturn, isNull);
  });
}

Future<void> _seedAccounts(AppDatabase db) async {
  await _insertAccount(
    db,
    id: 'broker',
    type: AccountType.brokerage,
    category: AccountCategory.asset,
  );
  await _insertAccount(
    db,
    id: 'cash',
    type: AccountType.bank,
    category: AccountCategory.asset,
  );
  await _insertAccount(
    db,
    id: 'fee',
    type: AccountType.other,
    category: AccountCategory.expense,
  );
  await _insertAccount(
    db,
    id: 'capital-gains',
    type: AccountType.other,
    category: AccountCategory.income,
  );
}

Future<void> _insertAccount(
  AppDatabase db, {
  required String id,
  required AccountType type,
  required AccountCategory category,
}) {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          type: type,
          category: Value(category),
          name: id,
          currency: 'USD',
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}

Future<void> _seedSecurity(AppDatabase db, {required String currency}) {
  return db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: 'NASDAQ:AAPL',
          type: AssetType.stock,
          symbol: 'AAPL',
          currency: currency,
          market: const Value('NASDAQ'),
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}
