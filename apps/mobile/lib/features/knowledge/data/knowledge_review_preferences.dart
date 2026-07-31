import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/current_user.dart';
import '../../../design_system/preferences/theme_preferences.dart';

String knowledgeReviewCadenceDaysKey(String ownerUserId) =>
    'lifeos.knowledge.$ownerUserId.review.cadence_days.v2';
String knowledgeStaleAssumptionDaysKey(String ownerUserId) =>
    'lifeos.knowledge.$ownerUserId.review.stale_assumption_days.v2';

class KnowledgeReviewPreferences {
  const KnowledgeReviewPreferences({
    this.cadenceDays = 7,
    this.staleAssumptionDays = 90,
  });

  final int cadenceDays;
  final int staleAssumptionDays;

  KnowledgeReviewPreferences copyWith({
    int? cadenceDays,
    int? staleAssumptionDays,
  }) {
    return KnowledgeReviewPreferences(
      cadenceDays: cadenceDays ?? this.cadenceDays,
      staleAssumptionDays: staleAssumptionDays ?? this.staleAssumptionDays,
    );
  }
}

final knowledgeReviewPreferencesProvider =
    StateNotifierProvider<
      KnowledgeReviewPreferencesController,
      KnowledgeReviewPreferences
    >((ref) {
      SharedPreferences? preferences;
      try {
        preferences = ref.watch(sharedPreferencesProvider);
      } on Object {
        // Defaults keep isolated tests and recovery surfaces operational.
      }
      final ownerUserId = ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId;
      return KnowledgeReviewPreferencesController(preferences, ownerUserId);
    });

class KnowledgeReviewPreferencesController
    extends StateNotifier<KnowledgeReviewPreferences> {
  KnowledgeReviewPreferencesController(this._preferences, this._ownerUserId)
    : super(
        KnowledgeReviewPreferences(
          cadenceDays:
              _preferences?.getInt(
                knowledgeReviewCadenceDaysKey(_ownerUserId),
              ) ??
              7,
          staleAssumptionDays:
              _preferences?.getInt(
                knowledgeStaleAssumptionDaysKey(_ownerUserId),
              ) ??
              90,
        ),
      );

  final SharedPreferences? _preferences;
  final String _ownerUserId;

  Future<void> setCadenceDays(int days) async {
    final value = days.clamp(1, 30);
    state = state.copyWith(cadenceDays: value);
    await _preferences?.setInt(
      knowledgeReviewCadenceDaysKey(_ownerUserId),
      value,
    );
  }

  Future<void> setStaleAssumptionDays(int days) async {
    final value = days.clamp(14, 365);
    state = state.copyWith(staleAssumptionDays: value);
    await _preferences?.setInt(
      knowledgeStaleAssumptionDaysKey(_ownerUserId),
      value,
    );
  }
}
