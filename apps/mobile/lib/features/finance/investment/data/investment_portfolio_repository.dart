import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/investment_portfolio.dart';

const _uuid = Uuid();

class InvestmentPortfolioRepository {
  InvestmentPortfolioRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const portfoliosTable = 'investment_portfolios';
  static const membershipsTable = 'portfolio_lot_memberships';

  Stream<List<InvestmentPortfolio>> watchActive(String ownerUserId) {
    final query = _db.select(_db.investmentPortfolios)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.archived.equals(false))
      ..orderBy([
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.name),
      ]);
    return query.watch().map(
      (rows) => rows.map(_portfolioFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioLotMembership>> watchMemberships(String ownerUserId) {
    final query = _db.select(_db.portfolioLotMemberships)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull());
    return query.watch().map(
      (rows) => rows.map(_membershipFromRow).toList(growable: false),
    );
  }

  Future<InvestmentPortfolio> create({
    required String name,
    required InvestmentPortfolioStrategy strategy,
    String? baseCurrency,
    String? goalId,
    String? targetAllocationJson,
    Decimal? targetAnnualIncome,
    String? color,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final row = InvestmentPortfoliosCompanion.insert(
      id: id,
      name: normalizedName,
      strategy: strategy.name,
      baseCurrency: Value(_nullableTrimmed(baseCurrency)?.toUpperCase()),
      goalId: Value(_nullableTrimmed(goalId)),
      targetAllocationJson: Value(_nullableTrimmed(targetAllocationJson)),
      targetAnnualIncome: Value(targetAnnualIncome),
      color: Value(_nullableTrimmed(color)),
      createdAt: stamp.now,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );
    await _db.transaction(() async {
      await _db.into(_db.investmentPortfolios).insert(row);
      await _outbox.enqueue(table: portfoliosTable, rowId: id);
    });
    return InvestmentPortfolio(
      id: id,
      name: normalizedName,
      strategy: strategy,
      baseCurrency: _nullableTrimmed(baseCurrency)?.toUpperCase(),
      goalId: _nullableTrimmed(goalId),
      targetAllocationJson: _nullableTrimmed(targetAllocationJson),
      targetAnnualIncome: targetAnnualIncome,
      color: _nullableTrimmed(color),
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
  }

  Future<InvestmentPortfolio> update(InvestmentPortfolio portfolio) async {
    final normalizedName = portfolio.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(portfolio.name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.investmentPortfolios,
      )..where((table) => table.id.equals(portfolio.id))).write(
        InvestmentPortfoliosCompanion(
          name: Value(normalizedName),
          strategy: Value(portfolio.strategy.name),
          baseCurrency: Value(portfolio.baseCurrency),
          goalId: Value(portfolio.goalId),
          targetAllocationJson: Value(portfolio.targetAllocationJson),
          targetAnnualIncome: Value(portfolio.targetAnnualIncome),
          color: Value(portfolio.color),
          archived: Value(portfolio.archived),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
    return portfolio.copyWith(
      name: normalizedName,
      sync: _syncFromStamp(stamp),
    );
  }

  Future<void> remove(InvestmentPortfolio portfolio) async {
    final stamp = await _stamper.stamp();
    final memberships =
        await (_db.select(_db.portfolioLotMemberships)
              ..where((table) => table.ownerUserId.equals(stamp.ownerUserId))
              ..where((table) => table.portfolioId.equals(portfolio.id))
              ..where((table) => table.deletedAt.isNull()))
            .get();
    await _db.transaction(() async {
      await (_db.update(
        _db.investmentPortfolios,
      )..where((table) => table.id.equals(portfolio.id))).write(
        InvestmentPortfoliosCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      for (final membership in memberships) {
        await (_db.update(
          _db.portfolioLotMemberships,
        )..where((table) => table.id.equals(membership.id))).write(
          PortfolioLotMembershipsCompanion(
            deletedAt: Value(stamp.now),
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
          ),
        );
        await _outbox.enqueue(table: membershipsTable, rowId: membership.id);
      }
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
  }

  /// Moves [lotId] into [portfolioId]. The lot id is the membership row id,
  /// making the one-lot/one-portfolio invariant structural.
  Future<void> assignLot({
    required String lotId,
    required String portfolioId,
  }) async {
    final stamp = await _stamper.stamp();
    final normalizedLotId = lotId.trim();
    if (normalizedLotId.isEmpty) {
      throw ArgumentError.value(lotId, 'lotId', 'must not be empty');
    }
    final row = PortfolioLotMembershipsCompanion.insert(
      id: normalizedLotId,
      portfolioId: portfolioId,
      assignedAt: stamp.now,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );
    await _db.transaction(() async {
      await _db.into(_db.portfolioLotMemberships).insertOnConflictUpdate(row);
      await _outbox.enqueue(table: membershipsTable, rowId: normalizedLotId);
    });
  }

  Future<void> unassignLot(String lotId) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.portfolioLotMemberships,
      )..where((table) => table.id.equals(lotId))).write(
        PortfolioLotMembershipsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: membershipsTable, rowId: lotId);
    });
  }
}

InvestmentPortfolio _portfolioFromRow(InvestmentPortfolioRow row) {
  return InvestmentPortfolio(
    id: row.id,
    name: row.name,
    strategy: investmentPortfolioStrategyFromWire(row.strategy),
    baseCurrency: row.baseCurrency,
    goalId: row.goalId,
    targetAllocationJson: row.targetAllocationJson,
    targetAnnualIncome: row.targetAnnualIncome,
    color: row.color,
    createdAt: row.createdAt,
    archived: row.archived,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

PortfolioLotMembership _membershipFromRow(PortfolioLotMembershipRow row) {
  return PortfolioLotMembership(
    lotId: row.id,
    portfolioId: row.portfolioId,
    assignedAt: row.assignedAt,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);

SyncMeta _syncFromRow({
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
}) => SyncMeta(
  ownerUserId: ownerUserId,
  updatedAt: updatedAt,
  updatedByDevice: updatedByDevice,
  hlc: hlc,
);

String? _nullableTrimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
