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

enum _ObservationStatus {
  comparable,
  late,
  incomplete,
  currencyMismatch,
  zeroBaseline,
}

class RunwayForecastRepository {
  const RunwayForecastRepository({
    required AppDatabase db,
    required String ownerUserId,
  }) : _db = db,
       _ownerUserId = ownerUserId;

  final AppDatabase _db;
  final String _ownerUserId;

  /// Returns whether observation evidence changed and quality should refresh.
  Future<bool> recordAndEvaluate(MoneyRunwaySnapshot snapshot) {
    return _db.transaction(() async {
      final changed = await _evaluateDue(snapshot);
      if (!snapshot.hasData) return changed;
      final day = _dayKey(snapshot.asOf);
      for (final horizon in const [30, 90]) {
        await _db.customStatement(
          '''
INSERT OR IGNORE INTO runway_forecast_snapshots (
  id, owner_user_id, as_of_day, target_at, horizon_days, currency,
  starting_balance, predicted_balance, data_completeness, balance_is_complete,
  evidence_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            snapshot.balanceIsComplete,
            jsonEncode(snapshot.toEvidenceJson()),
          ],
        );
      }
      return changed;
    });
  }

  Future<RunwayForecastQuality> quality() async {
    final rows = await _db
        .customSelect(
          '''
SELECT predicted_balance, starting_balance, absolute_error
FROM runway_forecast_snapshots
WHERE owner_user_id = ? AND evaluation_status = ?
ORDER BY target_at DESC, observed_at DESC, id DESC
LIMIT 12
''',
          variables: [
            Variable<String>(_ownerUserId),
            Variable<String>(_ObservationStatus.comparable.name),
          ],
        )
        .get();
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
    return RunwayForecastQuality(
      evaluatedCount: evaluated,
      meanRelativeError: evaluated == 0 ? null : total / evaluated,
    );
  }

  Future<bool> _evaluateDue(MoneyRunwaySnapshot current) async {
    final day = current.asOf.millisecondsSinceEpoch;
    final now = current.observedAt.millisecondsSinceEpoch;
    final due = await _db
        .customSelect(
          '''
SELECT id, target_at, currency, starting_balance, predicted_balance,
       balance_is_complete
FROM runway_forecast_snapshots
WHERE owner_user_id = ? AND target_at <= ?
  AND (observed_at IS NULL OR (
    target_at = ? AND observed_at < ? AND evaluation_status IN (?, ?)
  ))
''',
          variables: [
            Variable<String>(_ownerUserId),
            Variable<int>(day),
            Variable<int>(day),
            Variable<int>(now),
            Variable<String>(_ObservationStatus.incomplete.name),
            Variable<String>(_ObservationStatus.currencyMismatch.name),
          ],
        )
        .get();
    for (final row in due) {
      final predicted = Decimal.parse(row.read<String>('predicted_balance'));
      final starting = Decimal.parse(row.read<String>('starting_balance'));
      final status = row.read<int>('target_at') != day
          ? _ObservationStatus.late
          : row.read<String>('currency') != current.currency
          ? _ObservationStatus.currencyMismatch
          : !row.read<bool>('balance_is_complete') ||
                !current.balanceIsComplete ||
                !current.hasData
          ? _ObservationStatus.incomplete
          : predicted == Decimal.zero && starting == Decimal.zero
          ? _ObservationStatus.zeroBaseline
          : _ObservationStatus.comparable;
      final error = status == _ObservationStatus.comparable
          ? (current.startingBalance - predicted).abs()
          : null;
      await _db.customStatement(
        '''
UPDATE runway_forecast_snapshots
SET observed_balance = ?, observed_currency = ?, observed_at = ?,
    observed_data_completeness = ?, observed_balance_is_complete = ?,
    evaluation_status = ?, absolute_error = ?
WHERE id = ?
''',
        [
          current.startingBalance.toString(),
          current.currency,
          now,
          current.dataCompleteness,
          current.balanceIsComplete && current.hasData,
          status.name,
          error?.toString(),
          row.read<String>('id'),
        ],
      );
    }
    return due.isNotEmpty;
  }

  String _dayKey(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
