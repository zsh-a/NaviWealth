import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../domain/money_runway.dart';

final class RunwayForecastQuality {
  const RunwayForecastQuality({
    required this.evaluatedCount,
    required this.meanRelativeError,
  });

  final int evaluatedCount;
  final double? meanRelativeError;
}

class RunwayForecastRepository {
  const RunwayForecastRepository({
    required AppDatabase db,
    required String ownerUserId,
  }) : _db = db,
       _ownerUserId = ownerUserId;

  final AppDatabase _db;
  final String _ownerUserId;

  Future<void> recordAndEvaluate(MoneyRunwaySnapshot snapshot) async {
    await _evaluateDue(snapshot);
    final day = _dayKey(snapshot.asOf);
    for (final horizon in const [30, 90]) {
      await _db.customStatement(
        '''
INSERT OR IGNORE INTO runway_forecast_snapshots (
  id, owner_user_id, as_of_day, target_at, horizon_days, currency,
  starting_balance, predicted_balance, data_completeness, evidence_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          '$_ownerUserId:$day:$horizon',
          _ownerUserId,
          day,
          snapshot.asOf.add(Duration(days: horizon)).millisecondsSinceEpoch,
          horizon,
          snapshot.currency,
          snapshot.startingBalance.toString(),
          snapshot.balanceAt(horizon).toString(),
          snapshot.dataCompleteness,
          jsonEncode(snapshot.toEvidenceJson()),
        ],
      );
    }
  }

  Future<RunwayForecastQuality> quality() async {
    final rows = await _db
        .customSelect(
          '''
SELECT predicted_balance, starting_balance, absolute_error
FROM runway_forecast_snapshots
WHERE owner_user_id = ? AND evaluated_at IS NOT NULL
ORDER BY evaluated_at DESC
LIMIT 12
''',
          variables: [Variable<String>(_ownerUserId)],
        )
        .get();
    if (rows.isEmpty) {
      return const RunwayForecastQuality(
        evaluatedCount: 0,
        meanRelativeError: null,
      );
    }
    var total = 0.0;
    var evaluated = 0;
    for (final row in rows) {
      final predicted = Decimal.parse(row.read<String>('predicted_balance'));
      final starting = Decimal.parse(row.read<String>('starting_balance'));
      final error = Decimal.parse(row.read<String>('absolute_error'));
      final denominator = predicted.abs() > starting.abs()
          ? predicted.abs()
          : starting.abs();
      if (denominator > Decimal.zero) {
        total += (error / denominator).toDouble();
        evaluated++;
      }
    }
    if (evaluated == 0) {
      return RunwayForecastQuality(
        evaluatedCount: rows.length,
        meanRelativeError: null,
      );
    }
    return RunwayForecastQuality(
      evaluatedCount: rows.length,
      meanRelativeError: total / evaluated,
    );
  }

  Future<void> _evaluateDue(MoneyRunwaySnapshot current) async {
    final now = current.asOf.millisecondsSinceEpoch;
    final due = await _db
        .customSelect(
          '''
SELECT id, predicted_balance
FROM runway_forecast_snapshots
WHERE owner_user_id = ? AND evaluated_at IS NULL AND target_at <= ?
  AND currency = ?
''',
          variables: [
            Variable<String>(_ownerUserId),
            Variable<int>(now),
            Variable<String>(current.currency),
          ],
        )
        .get();
    for (final row in due) {
      final predicted = Decimal.parse(row.read<String>('predicted_balance'));
      final error = (current.startingBalance - predicted).abs();
      await _db.customStatement(
        '''
UPDATE runway_forecast_snapshots
SET actual_balance = ?, absolute_error = ?, evaluated_at = ?
WHERE id = ?
''',
        [
          current.startingBalance.toString(),
          error.toString(),
          now,
          row.read<String>('id'),
        ],
      );
    }
  }

  String _dayKey(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
