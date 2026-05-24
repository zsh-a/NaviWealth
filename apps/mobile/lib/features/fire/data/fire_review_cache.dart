import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../domain/fire_review.dart';

/// Local-only cache of generated FIRE reviews, keyed by (kind, periodKey).
///
/// Per `docs/roadmap-fire-os.md` §4.4 "Review 应是 deterministic
/// summary + optional AI explanation" — and §7.1 keeps it out of the
/// sync protocol for MVP. The cache is bounded at 24 entries (~two
/// years of monthlies, plus a year of quarterlies and the latest
/// annual) so a long-lived install doesn't bloat SharedPreferences.
final fireReviewCacheProvider =
    StateNotifierProvider<FireReviewCacheController, List<FireReview>>(
      (ref) => FireReviewCacheController(ref.watch(sharedPreferencesProvider)),
    );

class FireReviewCacheController extends StateNotifier<List<FireReview>> {
  FireReviewCacheController(this._prefs) : super(_load(_prefs));

  static const _kKey = 'naviwealth.fire.reviews_json';
  static const _kCap = 24;

  final SharedPreferences _prefs;

  static List<FireReview> _load(SharedPreferences p) {
    final raw = p.getString(_kKey);
    if (raw == null || raw.isEmpty) return const <FireReview>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <FireReview>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => FireReview.fromJson(Map<String, Object?>.from(m)))
          .toList(growable: false);
    } on FormatException {
      return const <FireReview>[];
    }
  }

  /// Insert or replace the review under (kind, periodKey). Newer
  /// entries bubble to the front; the list is capped at [_kCap].
  Future<void> upsert(FireReview review) async {
    final next = <FireReview>[
      review,
      for (final existing in state)
        if (!(existing.kind == review.kind &&
            existing.periodKey == review.periodKey))
          existing,
    ];
    final trimmed = next.length > _kCap ? next.sublist(0, _kCap) : next;
    state = List.unmodifiable(trimmed);
    await _prefs.setString(
      _kKey,
      jsonEncode(trimmed.map((r) => r.toJson()).toList()),
    );
  }

  /// Latest cached review for [kind]. `null` when none exist yet.
  FireReview? latest(FireReviewKind kind) {
    for (final r in state) {
      if (r.kind == kind) return r;
    }
    return null;
  }

  Future<void> clear() async {
    state = const <FireReview>[];
    await _prefs.remove(_kKey);
  }
}
