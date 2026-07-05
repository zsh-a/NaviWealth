import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/async/isolate_runner.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../domain/holding_service.dart';
import '../domain/returns/portfolio_return.dart';
import '../domain/returns/xirr_engine.dart';

class LedgerPortfolioReturnService implements PortfolioReturnService {
  LedgerPortfolioReturnService({
    required AppDatabase db,
    required this.ownerUserId,
    required this.baseCurrency,
    required this.holdings,
    required this.converter,
    XirrEngine xirr = const XirrEngine(),
  }) : _db = db,
       _xirr = xirr;

  final AppDatabase _db;
  final String ownerUserId;
  final String baseCurrency;
  final HoldingService holdings;
  final CurrencyConverter converter;
  final XirrEngine _xirr;

  @override
  Future<PortfolioReturnResult> compute({
    required DateTime from,
    required DateTime to,
  }) async {
    final start = from.toUtc();
    final end = to.toUtc();
    if (!end.isAfter(start)) {
      const empty = <XirrCashFlow>[];
      return PortfolioReturnResult(
        from: start,
        to: end,
        baseCurrency: baseCurrency,
        cashFlows: empty,
        solution: _xirr.compute(empty),
      );
    }

    final flows = <XirrCashFlow>[];
    final missingCurrencies = <String>{};

    final startValue = await _portfolioValueAt(start);
    if (startValue > Decimal.zero) {
      flows.add(XirrCashFlow(date: start, amount: -startValue.toDouble()));
    }

    flows.addAll(
      await _ledgerCashFlows(
        from: start,
        to: end,
        missingCurrencies: missingCurrencies,
      ),
    );

    final endValue = await _portfolioValueAt(end);
    if (endValue > Decimal.zero) {
      flows.add(XirrCashFlow(date: end, amount: endValue.toDouble()));
    }

    final solution = await runInIsolate(() => computeXirr(flows));
    return PortfolioReturnResult(
      from: start,
      to: end,
      baseCurrency: baseCurrency,
      cashFlows: List.unmodifiable(flows),
      solution: solution,
      missingCurrencies: Set.unmodifiable(missingCurrencies),
    );
  }

  Future<Decimal> _portfolioValueAt(DateTime asOf) async {
    final snapshots = await holdings.computeAt(asOf);
    return snapshots.values.fold<Decimal>(
      Decimal.zero,
      (sum, h) => sum + h.marketValueInBase,
    );
  }

  Future<List<XirrCashFlow>> _ledgerCashFlows({
    required DateTime from,
    required DateTime to,
    required Set<String> missingCurrencies,
  }) async {
    final securityEntryIds = await _securityJournalEntryIds(from: from, to: to);
    if (securityEntryIds.isEmpty) return const <XirrCashFlow>[];

    final assetIds = await _assetIds();
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
            innerJoin(
              _db.accounts,
              _db.accounts.id.equalsExp(_db.postings.accountId),
            ),
          ])
          ..where(_db.postings.ownerUserId.equals(ownerUserId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull())
          ..where(_db.accounts.deletedAt.isNull())
          ..where(_db.postings.journalEntryId.isIn(securityEntryIds))
          ..where(_db.accounts.category.equals(AccountSide.asset.name))
          ..orderBy([
            OrderingTerm.asc(_db.journalEntries.date),
            OrderingTerm.asc(_db.postings.position),
            OrderingTerm.asc(_db.postings.id),
          ]);

    if (assetIds.isNotEmpty) {
      query.where(_db.postings.unit.isNotIn(assetIds));
    }

    final rows = await query.get();
    final flows = <XirrCashFlow>[];
    for (final row in rows) {
      final posting = row.readTable(_db.postings);
      if (posting.units == Decimal.zero) continue;
      final date = row.readTable(_db.journalEntries).date.toUtc();
      try {
        final converted = converter.convert(
          Money(posting.units, posting.unit),
          baseCurrency,
          on: date,
        );
        if (converted.amount != Decimal.zero) {
          flows.add(
            XirrCashFlow(date: date, amount: converted.amount.toDouble()),
          );
        }
      } on FxRateNotFoundError {
        missingCurrencies.add(posting.unit);
      }
    }
    return flows;
  }

  Future<List<String>> _securityJournalEntryIds({
    required DateTime from,
    required DateTime to,
  }) async {
    final query =
        _db.select(_db.postings).join([
            innerJoin(
              _db.journalEntries,
              _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
            ),
            innerJoin(_db.assets, _db.assets.id.equalsExp(_db.postings.unit)),
          ])
          ..where(_db.postings.ownerUserId.equals(ownerUserId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull())
          ..where(_db.assets.deletedAt.isNull())
          ..where(_db.journalEntries.date.isBiggerThanValue(from))
          ..where(_db.journalEntries.date.isSmallerOrEqualValue(to))
          ..where(
            _db.assets.type.isIn(kSecuritiesAssetTypes.map((t) => t.name)),
          );

    final rows = await query.get();
    return rows
        .map((row) => row.readTable(_db.postings).journalEntryId)
        .toSet()
        .toList(growable: false);
  }

  Future<List<String>> _assetIds() async {
    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.deletedAt.isNull())).get();
    return rows.map((row) => row.id).toList(growable: false);
  }
}
