import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';

const String kKnowledgeReviewCadenceDaysKey =
    'lifeos.knowledge.review.cadence_days';
const String kKnowledgeStaleAssumptionDaysKey =
    'lifeos.knowledge.review.stale_assumption_days';

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
      return KnowledgeReviewPreferencesController(preferences);
    });

class KnowledgeReviewPreferencesController
    extends StateNotifier<KnowledgeReviewPreferences> {
  KnowledgeReviewPreferencesController(this._preferences)
    : super(
        KnowledgeReviewPreferences(
          cadenceDays:
              _preferences?.getInt(kKnowledgeReviewCadenceDaysKey) ?? 7,
          staleAssumptionDays:
              _preferences?.getInt(kKnowledgeStaleAssumptionDaysKey) ?? 90,
        ),
      );

  final SharedPreferences? _preferences;

  Future<void> setCadenceDays(int days) async {
    final value = days.clamp(1, 30);
    state = state.copyWith(cadenceDays: value);
    await _preferences?.setInt(kKnowledgeReviewCadenceDaysKey, value);
  }

  Future<void> setStaleAssumptionDays(int days) async {
    final value = days.clamp(14, 365);
    state = state.copyWith(staleAssumptionDays: value);
    await _preferences?.setInt(kKnowledgeStaleAssumptionDaysKey, value);
  }
}
