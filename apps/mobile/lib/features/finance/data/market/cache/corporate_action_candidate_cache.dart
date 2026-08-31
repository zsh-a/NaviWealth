import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_cache.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

/// Drift-backed cache of normalized provider candidates.
///
/// Rows are replaced atomically per `(market, symbol)`. This cache is
/// intentionally absent from Sync v3: all values are public market reference
/// data and can be rebuilt from providers.
class CorporateActionCandidateCache implements CorporateActionCache {
  CorporateActionCandidateCache({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<CorporateActionFetchResult?> read({
    required String symbol,
    required AssetMarket market,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final state =
        await (_db.select(_db.marketCorporateActionFetchStates)..where(
              (table) =>
                  table.market.equals(market.wire) &
                  table.symbol.equals(normalizedSymbol),
            ))
            .getSingleOrNull();
    if (state == null) return null;

    final disposition = _enumValue(
      CorporateActionFetchDisposition.values,
      state.disposition,
    );
    if (disposition == null) return null;

    final rows =
        await (_db.select(_db.marketCorporateActionCandidates)
              ..where(
                (table) =>
                    table.market.equals(market.wire) &
                    table.symbol.equals(normalizedSymbol),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.id)]))
            .get();
    final actions = <MarketCorporateAction>[];
    for (final row in rows) {
      final action = _actionFromRow(row);
      if (action != null) actions.add(action);
    }
    return CorporateActionFetchResult(
      provider: state.provider,
      disposition: disposition,
      actions: actions,
      fetchedAt: state.fetchedAt.toUtc(),
      warning: state.warning,
    );
  }

  @override
  Future<void> write({
    required String symbol,
    required AssetMarket market,
    required CorporateActionFetchResult result,
  }) async {
    if (!_isPersistable(result.disposition)) return;
    final normalizedSymbol = symbol.trim().toUpperCase();
    await _db.transaction(() async {
      await (_db.delete(_db.marketCorporateActionCandidates)..where(
            (table) =>
                table.market.equals(market.wire) &
                table.symbol.equals(normalizedSymbol),
          ))
          .go();
      for (final action in result.actions) {
        await _db
            .into(_db.marketCorporateActionCandidates)
            .insertOnConflictUpdate(
              MarketCorporateActionCandidatesCompanion.insert(
                id: action.id,
                source: action.source,
                dataset: action.dataset,
                sourceKey: action.sourceKey,
                revisionHash: action.revisionHash,
                identityStrength: action.identityStrength.name,
                symbol: normalizedSymbol,
                market: market.wire,
                kind: action.kind.name,
                status: action.status.name,
                reportDate: Value(action.reportDate),
                announcementDate: Value(action.announcementDate),
                recordDate: Value(action.recordDate),
                exDate: Value(action.exDate),
                payDate: Value(action.payDate),
                currency: Value(action.currency),
                cashPerShare: Value(action.cashPerShare),
                bonusRatio: Value(action.bonusRatio),
                capitalizationRatio: Value(action.capitalizationRatio),
                totalStockDistributionRatio: Value(
                  action.totalStockDistributionRatio,
                ),
                splitNumerator: Value(action.splitNumerator),
                splitDenominator: Value(action.splitDenominator),
                note: Value(action.note),
                fetchedAt: result.fetchedAt,
              ),
            );
      }
      await _db
          .into(_db.marketCorporateActionFetchStates)
          .insertOnConflictUpdate(
            MarketCorporateActionFetchStatesCompanion.insert(
              market: market.wire,
              symbol: normalizedSymbol,
              provider: result.provider,
              disposition: result.disposition.name,
              fetchedAt: result.fetchedAt,
              warning: Value(result.warning),
            ),
          );
    });
  }

  @override
  Future<void> invalidate({
    required String symbol,
    required AssetMarket market,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    await _db.transaction(() async {
      await (_db.delete(_db.marketCorporateActionCandidates)..where(
            (table) =>
                table.market.equals(market.wire) &
                table.symbol.equals(normalizedSymbol),
          ))
          .go();
      await (_db.delete(_db.marketCorporateActionFetchStates)..where(
            (table) =>
                table.market.equals(market.wire) &
                table.symbol.equals(normalizedSymbol),
          ))
          .go();
    });
  }
}

bool _isPersistable(CorporateActionFetchDisposition disposition) {
  return switch (disposition) {
    CorporateActionFetchDisposition.success ||
    CorporateActionFetchDisposition.authoritativeEmpty ||
    CorporateActionFetchDisposition.partial ||
    CorporateActionFetchDisposition.unsupported => true,
    CorporateActionFetchDisposition.stale ||
    CorporateActionFetchDisposition.failure => false,
  };
}

MarketCorporateAction? _actionFromRow(MarketCorporateActionCandidateRow row) {
  final market = assetMarketFromWire(row.market);
  final kind = _enumValue(MarketCorporateActionKind.values, row.kind);
  final status = _enumValue(MarketCorporateActionStatus.values, row.status);
  final identityStrength = _enumValue(
    MarketCorporateActionIdentityStrength.values,
    row.identityStrength,
  );
  if (market == null ||
      kind == null ||
      status == null ||
      identityStrength == null) {
    return null;
  }
  return MarketCorporateAction(
    id: row.id,
    source: row.source,
    dataset: row.dataset,
    sourceKey: row.sourceKey,
    revisionHash: row.revisionHash,
    identityStrength: identityStrength,
    symbol: row.symbol,
    market: market,
    kind: kind,
    status: status,
    reportDate: row.reportDate?.toUtc(),
    announcementDate: row.announcementDate?.toUtc(),
    recordDate: row.recordDate?.toUtc(),
    exDate: row.exDate?.toUtc(),
    payDate: row.payDate?.toUtc(),
    currency: row.currency,
    cashPerShare: row.cashPerShare,
    bonusRatio: row.bonusRatio,
    capitalizationRatio: row.capitalizationRatio,
    totalStockDistributionRatio: row.totalStockDistributionRatio,
    splitNumerator: row.splitNumerator,
    splitDenominator: row.splitDenominator,
    note: row.note,
  );
}

T? _enumValue<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
