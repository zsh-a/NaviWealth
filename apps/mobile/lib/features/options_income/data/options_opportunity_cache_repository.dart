import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../data/db/app_database.dart';
import '../../../domain/values/asset_market.dart';
import '../../../domain/values/money.dart';
import '../domain/opportunity_explanation.dart';
import '../domain/option_contract.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';

/// Local-only cache repository for [OptionsOpportunity]s.
///
/// Behaviour rules (`docs/options-income.md` §6.2):
///   * Single batch retained per scan id; the latest batch is the canonical
///     read source.
///   * On `replaceBatch`, batches older than 1 week are vacuumed.
class OptionsOpportunityCacheRepository {
  OptionsOpportunityCacheRepository({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// Fires the affected `ownerUserId` after every successful batch write.
  /// UI providers translate this into a `ref.invalidateSelf` to re-pull.
  Stream<String> get changes => _changes.stream;

  void dispose() {
    _changes.close();
  }

  /// Replace the user's full set of cached opportunities atomically. Older
  /// batches (>1 week) for the same user are vacuumed.
  Future<void> replaceBatch({
    required String ownerUserId,
    required String scanId,
    required List<OptionsOpportunity> opportunities,
  }) async {
    final ttlCutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    await _db.transaction(() async {
      // Vacuum old batches.
      await _db.customStatement(
        'DELETE FROM options_opportunity_cache '
        'WHERE owner_user_id = ? AND scanned_at < ?',
        <Object?>[ownerUserId, _iso(ttlCutoff)],
      );
      // Replace this user's previous batch entirely — UI shows only the
      // newest scan, so we don't need to keep the prior one around.
      await _db.customStatement(
        'DELETE FROM options_opportunity_cache WHERE owner_user_id = ?',
        <Object?>[ownerUserId],
      );
      for (final opp in opportunities) {
        await _insertOne(ownerUserId, scanId, opp);
      }
    });
    if (!_changes.isClosed) _changes.add(ownerUserId);
  }

  /// Mark a stale cache by deleting all rows for the user. Used when the
  /// user clears their profile.
  Future<void> clearForUser(String ownerUserId) async {
    await _db.customStatement(
      'DELETE FROM options_opportunity_cache WHERE owner_user_id = ?',
      <Object?>[ownerUserId],
    );
    if (!_changes.isClosed) _changes.add(ownerUserId);
  }

  Future<List<OptionsOpportunity>> getLatest(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM options_opportunity_cache '
          'WHERE owner_user_id = ? AND scan_id = ('
          '  SELECT scan_id FROM options_opportunity_cache '
          '  WHERE owner_user_id = ? '
          '  ORDER BY scanned_at DESC LIMIT 1'
          ') '
          'ORDER BY score DESC',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(ownerUserId),
          ],
        )
        .get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  /// Metadata about the latest scan batch. Returns `null` when the user has
  /// no cached opportunities yet.
  Future<ScanCacheState?> latestScanState(String ownerUserId) async {
    final row = await _db
        .customSelect(
          'SELECT scan_id, scanned_at, COUNT(*) AS n '
          'FROM options_opportunity_cache '
          'WHERE owner_user_id = ? AND scan_id = ('
          '  SELECT scan_id FROM options_opportunity_cache '
          '  WHERE owner_user_id = ? '
          '  ORDER BY scanned_at DESC LIMIT 1'
          ') '
          'GROUP BY scan_id',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withString(ownerUserId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final scanId = row.read<String>('scan_id');
    final scannedAtRaw = row.read<String>('scanned_at');
    final count = row.read<int>('n');
    final scannedAt = DateTime.parse(scannedAtRaw).toUtc();
    return ScanCacheState(scanId: scanId, scannedAt: scannedAt, count: count);
  }

  Future<void> _insertOne(
    String ownerUserId,
    String scanId,
    OptionsOpportunity opp,
  ) async {
    final c = opp.contract;
    final m = opp.metrics;
    await _db.customStatement(
      'INSERT OR REPLACE INTO options_opportunity_cache ('
      '  scan_id, option_symbol, owner_user_id, underlying, market, strategy,'
      '  expiration, dte, type, currency, strike, bid, ask, mid,'
      '  underlying_price, volume, open_interest, implied_volatility, delta,'
      '  bid_ask_spread_pct, premium, cash_required, breakeven, static_return,'
      '  annualized_yield, margin_of_safety, score, risk_level,'
      '  explanation_json, scanned_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        scanId,
        c.optionSymbol,
        ownerUserId,
        c.underlying,
        c.market.wire,
        opp.strategy.wire,
        _iso(c.expiration),
        c.dte,
        c.type.wire,
        c.strike.currency,
        c.strike.amount.toString(),
        c.bid.amount.toString(),
        c.ask.amount.toString(),
        c.mid.amount.toString(),
        c.underlyingPrice.amount.toString(),
        c.volume,
        c.openInterest,
        c.impliedVolatility?.toString(),
        c.delta?.toString(),
        c.bidAskSpreadPct.toString(),
        m.premium.amount.toString(),
        m.cashRequired.amount.toString(),
        m.breakeven.amount.toString(),
        m.staticReturn.toString(),
        m.annualizedYield.toString(),
        m.marginOfSafety.toString(),
        opp.score.toString(),
        opp.risk.wire,
        opp.explanation.encode(),
        _iso(opp.scannedAt),
      ],
    );
  }
}

class ScanCacheState {
  const ScanCacheState({
    required this.scanId,
    required this.scannedAt,
    required this.count,
  });

  final String scanId;
  final DateTime scannedAt;
  final int count;

  bool get isStale =>
      DateTime.now().toUtc().difference(scannedAt) > const Duration(hours: 24);
}

OptionsOpportunity _rowToDomain(QueryRow row) {
  final currency = row.read<String>('currency');
  final marketWire = row.read<String>('market');
  final market = assetMarketFromWire(marketWire) ?? AssetMarket.unknown;
  final type = parseOptionType(row.read<String>('type')) ?? OptionType.put;
  final strategy =
      parseOptionsStrategyKind(row.read<String>('strategy')) ??
      OptionsStrategyKind.cashSecuredPut;
  final scannedAt = DateTime.parse(row.read<String>('scanned_at')).toUtc();
  final expiration = DateTime.parse(row.read<String>('expiration')).toUtc();
  final explanation = OpportunityExplanation.decode(
    row.read<String>('explanation_json'),
  );
  final contract = OptionContract(
    underlying: row.read<String>('underlying'),
    market: market,
    optionSymbol: row.read<String>('option_symbol'),
    type: type,
    expiration: expiration,
    dte: row.read<int>('dte'),
    strike: Money.parse(row.read<String>('strike'), currency),
    bid: Money.parse(row.read<String>('bid'), currency),
    ask: Money.parse(row.read<String>('ask'), currency),
    mid: Money.parse(row.read<String>('mid'), currency),
    volume: row.read<int>('volume'),
    openInterest: row.read<int>('open_interest'),
    impliedVolatility: _decimalOrNull(row.read<String?>('implied_volatility')),
    delta: _decimalOrNull(row.read<String?>('delta')),
    underlyingPrice: Money.parse(
      row.read<String>('underlying_price'),
      currency,
    ),
    bidAskSpreadPct: Decimal.parse(row.read<String>('bid_ask_spread_pct')),
    fetchedAt: scannedAt,
  );
  final metrics = OpportunityMetrics(
    premium: Money.parse(row.read<String>('premium'), currency),
    cashRequired: Money.parse(row.read<String>('cash_required'), currency),
    breakeven: Money.parse(row.read<String>('breakeven'), currency),
    staticReturn: Decimal.parse(row.read<String>('static_return')),
    annualizedYield: Decimal.parse(row.read<String>('annualized_yield')),
    marginOfSafety: Decimal.parse(row.read<String>('margin_of_safety')),
  );
  return OptionsOpportunity(
    strategy: strategy,
    contract: contract,
    metrics: metrics,
    risk: parseOpportunityRiskLevel(row.read<String>('risk_level')),
    explanation: explanation,
    score: Decimal.parse(row.read<String>('score')),
    scannedAt: scannedAt,
    scanId: row.read<String>('scan_id'),
  );
}

Decimal? _decimalOrNull(String? raw) =>
    raw == null || raw.isEmpty ? null : Decimal.parse(raw);

String _iso(DateTime value) => value.toUtc().toIso8601String();
