/// User-facing notification preferences.
///
/// OS permissions still live in [NotificationService]. These flags are
/// app-level intent: when disabled, app agents should skip registering
/// background jobs or posting local notifications even if the OS allows it.
library;

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';

final notificationsEnabledProvider =
    StateNotifierProvider<SharedBoolPreferenceController, bool>((ref) {
      return SharedBoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: SharedBoolPreferenceController.notificationsEnabledKey,
        defaultValue: true,
      );
    });

final healthBriefingNotificationsEnabledProvider =
    StateNotifierProvider<SharedBoolPreferenceController, bool>((ref) {
      return SharedBoolPreferenceController(
        ref.watch(sharedPreferencesProvider),
        key: SharedBoolPreferenceController.healthBriefingEnabledKey,
        defaultValue: true,
      );
    });

class SharedBoolPreferenceController extends StateNotifier<bool> {
  SharedBoolPreferenceController(
    this._prefs, {
    required this.key,
    required this.defaultValue,
  }) : super(_prefs.getBool(key) ?? defaultValue);

  static const String notificationsEnabledKey = 'lifeos.notifications.enabled';
  static const String healthBriefingEnabledKey =
      'lifeos.notifications.health.briefing.enabled';

  final SharedPreferences _prefs;
  final String key;
  final bool defaultValue;

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    await _prefs.setBool(key, enabled);
  }
}
