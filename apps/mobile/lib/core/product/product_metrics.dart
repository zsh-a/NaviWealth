import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';

enum ProductFunnelEvent {
  financialInboxOpened,
  moneyRunwayOpened,
  lifeEventCompared,
  financialDecisionSaved,
  financialDecisionReviewed,
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
  static const _countsKey = 'naviwealth.product_metrics.counts';
  final SharedPreferences _preferences;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _preferences.setBool(_enabledKey, value);
  }

  Future<void> record(ProductFunnelEvent event) async {
    if (!state) return;
    final raw = _preferences.getString(_countsKey);
    final counts = raw == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
    counts[event.name] = ((counts[event.name] as num?)?.toInt() ?? 0) + 1;
    await _preferences.setString(_countsKey, jsonEncode(counts));
  }
}
