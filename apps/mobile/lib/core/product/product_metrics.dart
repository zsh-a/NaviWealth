import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';

enum ProductFunnelEvent {
  activationStarted,
  firstUsefulResultCompleted,
  importCycleCompleted,
  importRowsAccepted,
  importRowsRejected,
  importRowsDeduplicated,
  importReviewCorrected,
  importReviewCompleted,
  financialInboxOpened,
  financialInboxCleared,
  moneyRunwayOpened,
  executionActionCreated,
  executionActionCompleted,
  executionActionDropped,
  financialSignalRevalidatedCleared,
  financialSignalRevalidatedStillActive,
  financialSignalRevalidationInconclusive,
  lifeEventCompared,
  financialDecisionSaved,
  financialDecisionReviewed,
  knowledgeDecisionCreated,
  knowledgeDecisionActionCreated,
  knowledgeDecisionReviewed,
  monthlyCloseCompleted,
}

final productMetricsProvider =
    StateNotifierProvider<ProductMetricsController, bool>((ref) {
      return ProductMetricsController(ref.watch(sharedPreferencesProvider));
    });

/// Records optional local product evidence without putting the user action at
/// risk. An unavailable preference store or failed aggregate write must never
/// fail the domain mutation that produced the evidence.
Future<void> recordProductMetric(
  ProductMetricsController Function() readController,
  ProductFunnelEvent event, {
  Duration? duration,
  bool? success,
  int quantity = 1,
}) async {
  try {
    await readController().record(
      event,
      duration: duration,
      success: success,
      quantity: quantity,
    );
  } on Object {
    // Product evidence is optional and privacy-safe, never transactional.
  }
}

/// Opt-in, device-only aggregates. The report contains stable event names,
/// counters, duration totals, success states, and UTC day buckets only.
class ProductMetricsController extends StateNotifier<bool> {
  ProductMetricsController(
    this._preferences, {
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock,
       _firstUsefulResultRecorded =
           _preferences.getBool(_firstUsefulResultRecordedKey) ?? false,
       super(_preferences.getBool(_enabledKey) ?? false);

  static const _enabledKey = 'naviwealth.product_metrics.enabled';
  static const _aggregatesKey = 'naviwealth.product_metrics.aggregates.v5';
  static const _activationStartedAtKey =
      'naviwealth.product_metrics.activation_started_at';
  static const _firstUsefulResultRecordedKey =
      'naviwealth.product_metrics.first_useful_result_recorded';
  static const _retainedDays = 90;
  final SharedPreferences _preferences;
  final DateTime Function() _clock;
  bool _firstUsefulResultRecorded;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _preferences.setBool(_enabledKey, value);
  }

  Future<void> record(
    ProductFunnelEvent event, {
    Duration? duration,
    bool? success,
    int quantity = 1,
  }) async {
    if (!state || quantity <= 0) return;
    if (event == ProductFunnelEvent.firstUsefulResultCompleted &&
        _firstUsefulResultRecorded) {
      return;
    }
    if (event == ProductFunnelEvent.firstUsefulResultCompleted &&
        success == true) {
      _firstUsefulResultRecorded = true;
    }
    final occurredAt = _clock();
    if (event == ProductFunnelEvent.activationStarted &&
        !_preferences.containsKey(_activationStartedAtKey)) {
      await _preferences.setInt(
        _activationStartedAtKey,
        occurredAt.toUtc().millisecondsSinceEpoch,
      );
    }
    var measuredDuration = duration;
    if (event == ProductFunnelEvent.firstUsefulResultCompleted &&
        success == true) {
      final activationStartedAt = _preferences.getInt(_activationStartedAtKey);
      if (activationStartedAt != null) {
        measuredDuration = occurredAt.toUtc().difference(
          DateTime.fromMillisecondsSinceEpoch(activationStartedAt, isUtc: true),
        );
        await _preferences.remove(_activationStartedAtKey);
      }
    }
    final report = _readReport();
    final totals = Map<String, Object?>.from(report['totals']! as Map);
    _increment(
      totals,
      event,
      duration: measuredDuration,
      success: success,
      quantity: quantity,
    );

    final days = Map<String, Object?>.from(report['days']! as Map);
    final day = _dayKey(occurredAt);
    final dayEvents = Map<String, Object?>.from(
      days[day] as Map? ?? const <String, Object?>{},
    );
    _increment(
      dayEvents,
      event,
      duration: measuredDuration,
      success: success,
      quantity: quantity,
    );
    days[day] = dayEvents;
    final orderedDays = days.keys.toList()..sort();
    for (final expired in orderedDays.take(
      (orderedDays.length - _retainedDays).clamp(0, orderedDays.length),
    )) {
      days.remove(expired);
    }

    await _preferences.setString(
      _aggregatesKey,
      jsonEncode(<String, Object?>{
        'schema_version': 5,
        'totals': totals,
        'days': days,
      }),
    );
    if (event == ProductFunnelEvent.firstUsefulResultCompleted &&
        success == true) {
      await _preferences.setBool(_firstUsefulResultRecordedKey, true);
    }
  }

  Map<String, Object?> exportAggregates() {
    if (!state) return const <String, Object?>{};
    final report = _readReport();
    final days = Map<String, Object?>.from(report['days']! as Map);
    final totals = Map<String, Object?>.from(report['totals']! as Map);
    final importCycles = _eventCount(
      totals,
      ProductFunnelEvent.importCycleCompleted,
    );
    return <String, Object?>{
      ...report,
      'derived': <String, Object?>{
        'active_day_count': days.length,
        'first_useful_result_day_count': _daysWith(
          days,
          ProductFunnelEvent.firstUsefulResultCompleted,
        ),
        'import_cycle_day_count': _daysWith(
          days,
          ProductFunnelEvent.importCycleCompleted,
        ),
        'import_cycle_count': importCycles,
        'completed_second_import_cycle': importCycles >= 2,
        'completed_third_import_cycle': importCycles >= 3,
        'inbox_clear_day_count': _daysWith(
          days,
          ProductFunnelEvent.financialInboxCleared,
        ),
        'monthly_close_day_count': _daysWith(
          days,
          ProductFunnelEvent.monthlyCloseCompleted,
        ),
        'knowledge_decision_created_count': _eventCount(
          totals,
          ProductFunnelEvent.knowledgeDecisionCreated,
        ),
        'knowledge_decision_action_created_count': _eventCount(
          totals,
          ProductFunnelEvent.knowledgeDecisionActionCreated,
        ),
        'knowledge_decision_reviewed_count': _eventCount(
          totals,
          ProductFunnelEvent.knowledgeDecisionReviewed,
        ),
        'knowledge_decision_created_day_count': _daysWith(
          days,
          ProductFunnelEvent.knowledgeDecisionCreated,
        ),
        'knowledge_decision_reviewed_day_count': _daysWith(
          days,
          ProductFunnelEvent.knowledgeDecisionReviewed,
        ),
      },
    };
  }

  Map<String, Object?> _readReport() {
    final raw = _preferences.getString(_aggregatesKey);
    if (raw == null) {
      return <String, Object?>{
        'schema_version': 5,
        'totals': <String, Object?>{},
        'days': <String, Object?>{},
      };
    }
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  void _increment(
    Map<String, Object?> scope,
    ProductFunnelEvent event, {
    required Duration? duration,
    required bool? success,
    required int quantity,
  }) {
    final aggregate = Map<String, Object?>.from(
      scope[event.name] as Map? ?? const <String, Object?>{},
    );
    aggregate['count'] =
        ((aggregate['count'] as num?)?.toInt() ?? 0) + quantity;
    if (duration != null) {
      aggregate['duration_ms_total'] =
          ((aggregate['duration_ms_total'] as num?)?.toInt() ?? 0) +
          duration.inMilliseconds;
    }
    if (success != null) {
      final key = success ? 'success_count' : 'failure_count';
      aggregate[key] = ((aggregate[key] as num?)?.toInt() ?? 0) + quantity;
    }
    scope[event.name] = aggregate;
  }

  int _daysWith(Map<String, Object?> days, ProductFunnelEvent event) =>
      days.values.where((value) {
        final events = Map<String, Object?>.from(value! as Map);
        return events.containsKey(event.name);
      }).length;

  int _eventCount(Map<String, Object?> totals, ProductFunnelEvent event) {
    final aggregate = totals[event.name] as Map?;
    return (aggregate?['count'] as num?)?.toInt() ?? 0;
  }

  String _dayKey(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
