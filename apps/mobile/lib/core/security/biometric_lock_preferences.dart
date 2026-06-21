import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';

final biometricUnlockEnabledProvider =
    StateNotifierProvider<BiometricUnlockPreferenceController, bool>((ref) {
      return BiometricUnlockPreferenceController(
        ref.watch(sharedPreferencesProvider),
      );
    });

final biometricUnlockSessionProvider =
    StateNotifierProvider<BiometricUnlockSessionController, bool>((ref) {
      return BiometricUnlockSessionController();
    });

class BiometricUnlockPreferenceController extends StateNotifier<bool> {
  BiometricUnlockPreferenceController(this._prefs)
    : super(_prefs.getBool(_key) ?? false);

  static const String _key = 'lifeos.security.biometric_unlock.enabled';

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    await _prefs.setBool(_key, enabled);
  }
}

class BiometricUnlockSessionController extends StateNotifier<bool> {
  BiometricUnlockSessionController() : super(false);

  void unlock() => state = true;

  void lock() => state = false;
}
