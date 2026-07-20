import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';

import '../domain/dividend_cash_projection.dart';
import '../domain/dividend_center.dart';

final class DividendForecastQuality {
  const DividendForecastQuality({
    required this.evaluatedCount,
    required this.meanRelativeError,
  });

  final int evaluatedCount;
  final double? meanRelativeError;
}

/// Stores local-only 90-day after-tax dividend forecasts and evaluates them
/// against later ledger truth. Forecast snapshots never sync and never feed
/// back into the recorded dividend history.
class DividendForecastRepository {
  const DividendForecastRepository({
    required AppDatabase db,
    required String ownerUserId,
  }) : _db = db,
       _ownerUserId = ownerUserId;

  final AppDatabase _db;
  final String _ownerUserId;

  Future<void> recordAndEvaluate({
    required DateTime asOf,
    required String currency,
    required Iterable<DividendCashProjection> projections,
    required Iterable<DividendCenterEvent> actualEvents,
    required String strategy,
    required DividendForecastConfidence confidence,
    int horizonDays = 90,
  }) async {
    final start = _day(asOf);
    await _evaluateDue(
      asOf: start,
      currency: currency,
      actualEvents: actualEvents,
    );

    // Projections include both the as-of day and day N, so the evaluation
    // window ends at the start of day N+1.
    final endExclusive = start.add(Duration(days: horizonDays + 1));
    var predictedNet = Decimal.zero;
    var declaredCount = 0;
    var inferredCount = 0;
    var taxEvidenceCount = 0;
    for (final projection in projections) {
      final date = _day(projection.date);
      if (date.isBefore(start) || !date.isBefore(endExclusive)) continue;
      predictedNet += projection.netAmount;
      if (projection.certainty == DividendCashCertainty.declared) {
        declaredCount++;
      } else {
        inferredCount++;
      }
      if (projection.hasTaxEvidence) taxEvidenceCount++;
    }
    final day = _dayKey(start);
    await _db.customStatement(
      '''
INSERT OR IGNORE INTO dividend_forecast_snapshots (
  id, owner_user_id, as_of_day, window_start, target_at, horizon_days,
  currency, predicted_net, strategy, confidence, evidence_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        '$_ownerUserId:$day:$horizonDays',
        _ownerUserId,
        day,
        start.millisecondsSinceEpoch,
        endExclusive.millisecondsSinceEpoch,
        horizonDays,
        currency.trim().toUpperCase(),
        predictedNet.toString(),
        strategy,
        confidence.name,
        jsonEncode(<String, Object?>{
          'declared_count': declaredCount,
          'inferred_count': inferredCount,
          'tax_evidence_count': taxEvidenceCount,
        }),
      ],
    );
  }

  Future<DividendForecastQuality> quality() async {
    final rows = await _db
        .customSelect(
          '''
SELECT predicted_net, actual_net, absolute_error
FROM dividend_forecast_snapshots
WHERE owner_user_id = ? AND evaluated_at IS NOT NULL
ORDER BY evaluated_at DESC
LIMIT 12
''',
          variables: [Variable<String>(_ownerUserId)],
        )
        .get();
    if (rows.isEmpty) {
      return const DividendForecastQuality(
        evaluatedCount: 0,
        meanRelativeError: null,
      );
    }
    var total = 0.0;
    var comparableCount = 0;
    for (final row in rows) {
      final predicted = Decimal.parse(row.read<String>('predicted_net'));
      final actual = Decimal.parse(row.read<String>('actual_net'));
      final error = Decimal.parse(row.read<String>('absolute_error'));
      final denominator = predicted.abs() > actual.abs()
          ? predicted.abs()
          : actual.abs();
      if (denominator <= Decimal.zero) continue;
      total += (error / denominator).toDouble();
      comparableCount++;
    }
    return DividendForecastQuality(
      evaluatedCount: rows.length,
      meanRelativeError: comparableCount == 0 ? null : total / comparableCount,
    );
  }

  Future<void> _evaluateDue({
    required DateTime asOf,
    required String currency,
    required Iterable<DividendCenterEvent> actualEvents,
  }) async {
    final normalizedCurrency = currency.trim().toUpperCase();
    final due = await _db
        .customSelect(
          '''
SELECT id, window_start, target_at, predicted_net
FROM dividend_forecast_snapshots
WHERE owner_user_id = ? AND evaluated_at IS NULL AND target_at <= ?
  AND currency = ?
''',
          variables: [
            Variable<String>(_ownerUserId),
            Variable<int>(asOf.millisecondsSinceEpoch),
            Variable<String>(normalizedCurrency),
          ],
        )
        .get();
    for (final row in due) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('window_start'),
        isUtc: true,
      );
      final end = DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('target_at'),
        isUtc: true,
      );
      var actualNet = Decimal.zero;
      for (final event in actualEvents) {
        final date = event.event.date.toUtc();
        if (!date.isBefore(start) && date.isBefore(end)) {
          actualNet += event.netInBase;
        }
      }
      final predicted = Decimal.parse(row.read<String>('predicted_net'));
      final error = (actualNet - predicted).abs();
      await _db.customStatement(
        '''
UPDATE dividend_forecast_snapshots
SET actual_net = ?, absolute_error = ?, evaluated_at = ?
WHERE id = ?
''',
        [
          actualNet.toString(),
          error.toString(),
          asOf.millisecondsSinceEpoch,
          row.read<String>('id'),
        ],
      );
    }
  }
}

DateTime _day(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

String _dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
