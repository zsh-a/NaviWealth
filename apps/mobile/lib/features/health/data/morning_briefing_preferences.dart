/// User preference: preferred local-time hour for the daily Morning
/// Briefing agent (`docs/domains/healthos-domain.md` §8, D-2.5b follow-up).
///
/// Persisted as a 0–23 integer in [SharedPreferences]. The agent reads
/// this via the `morningBriefingAgentProvider` override in
/// `bootstrap.dart` and feeds it into its [AgentSchedule]. Changing
/// the value rebuilds the agent provider; the next runner tick picks
/// up the new hour.
///
/// Note on background fidelity: the workmanager periodic task fires
/// at OS-discretion windows (≈24h, no wall-clock guarantee). The
/// preferred hour is honoured by the in-process `AgentRunner.tick`
/// gate; the background-flag path runs whenever the OS wakes us.
library;

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart';

const int kDefaultMorningBriefingHourLocal = 7;

final morningBriefingHourProvider =
    StateNotifierProvider<MorningBriefingHourController, int>((ref) {
      return MorningBriefingHourController(ref.watch(sharedPreferencesProvider));
    });

class MorningBriefingHourController extends StateNotifier<int> {
  MorningBriefingHourController(this._prefs) : super(_load(_prefs));

  static const String _key = 'lifeos.health.briefing.hourLocal';
  final SharedPreferences _prefs;

  static int _load(SharedPreferences p) {
    final raw = p.getInt(_key);
    if (raw == null) return kDefaultMorningBriefingHourLocal;
    return raw.clamp(0, 23);
  }

  Future<void> set(int hour) async {
    final clamped = hour.clamp(0, 23);
    if (clamped == state) return;
    state = clamped;
    await _prefs.setInt(_key, clamped);
  }
}
