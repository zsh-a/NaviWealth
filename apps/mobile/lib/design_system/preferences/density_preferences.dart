import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_preferences.dart';

/// User preference: compact UI density on desktop / web.
///
/// Defaults to `true` on web and on desktop platforms (macOS / Windows /
/// Linux) where the primary input is a mouse — denser list rows and
/// controls fit more information per viewport without hurting hit
/// targets. Touch platforms (iOS / Android) default to `false` so 48dp
/// tap targets remain.
///
/// User-overridable via the appearance section in Settings.
final compactDensityProvider =
    StateNotifierProvider<CompactDensityController, bool>((ref) {
      return CompactDensityController(ref.watch(sharedPreferencesProvider));
    });

class CompactDensityController extends StateNotifier<bool> {
  CompactDensityController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.ui.density.compact';
  final SharedPreferences _prefs;

  static bool _load(SharedPreferences prefs) {
    final stored = prefs.getBool(_key);
    if (stored != null) return stored;
    return _platformDefault();
  }

  static bool _platformDefault() {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> set(bool compact) async {
    if (compact == state) return;
    state = compact;
    await _prefs.setBool(_key, compact);
  }

  Future<void> toggle() => set(!state);
}
