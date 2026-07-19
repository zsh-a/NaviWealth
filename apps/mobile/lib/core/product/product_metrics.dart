import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';

enum ProductFunnelEvent {
  activationStarted,
  importReviewCompleted,
  financialInboxOpened,
  financialInboxCleared,
  moneyRunwayOpened,
  executionActionCreated,
  lifeEventCompared,
  financialDecisionSaved,
  financialDecisionReviewed,
  monthlyCloseCompleted,
}

final productMetricsProvider =
    StateNotifierProvider<ProductMetricsController, bool>((ref) {
      return ProductMetricsController(ref.watch(sharedPreferencesProvider));
    });

/// Opt-in, device-only counters. No balances, labels, routes, or identifiers
/// are recorded, and nothing is uploaded by this service.
class ProductMetricsController extends StateNotifier<bool> {
  ProductMetricsController(this._preferences)
    : super(_preferences.getBool(_enabledKey) ?? false);

  static const _enabledKey = 'naviwealth.product_metrics.enabled';
  static const _aggregatesKey = 'naviwealth.product_metrics.aggregates.v2';
  final SharedPreferences _preferences;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _preferences.setBool(_enabledKey, value);
  }

  Future<void> record(
    ProductFunnelEvent event, {
    Duration? duration,
    bool? success,
  }) async {
    if (!state) return;
    final raw = _preferences.getString(_aggregatesKey);
    final aggregates = raw == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
    final aggregate = Map<String, Object?>.from(
      aggregates[event.name] as Map? ?? const <String, Object?>{},
    );
    aggregate['count'] = ((aggregate['count'] as num?)?.toInt() ?? 0) + 1;
    if (duration != null) {
      aggregate['duration_ms_total'] =
          ((aggregate['duration_ms_total'] as num?)?.toInt() ?? 0) +
          duration.inMilliseconds;
    }
    if (success != null) {
      aggregate[success ? 'success_count' : 'failure_count'] =
          ((aggregate[success ? 'success_count' : 'failure_count'] as num?)
                  ?.toInt() ??
              0) +
          1;
    }
    aggregates[event.name] = aggregate;
    await _preferences.setString(_aggregatesKey, jsonEncode(aggregates));
  }

  Map<String, Object?> exportAggregates() {
    if (!state) return const <String, Object?>{};
    final raw = _preferences.getString(_aggregatesKey);
    return raw == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }
}
