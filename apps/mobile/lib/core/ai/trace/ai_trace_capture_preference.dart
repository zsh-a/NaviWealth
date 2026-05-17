/// User preference: AI trace capture verbosity.
///
/// `false` (default) → **metadata-only**: spans keep
/// name/duration/tokens/status but drop tool input/output and the LLM
/// text digest. Small blob, no payload sitting in local storage.
///
/// `true` → **verbose**: spans also persist (clipped) input/output so
/// the transparency page can show exactly what the model passed each
/// tool and what came back — the Opik-style debugging view.
///
/// Persisted via the shared [SharedPreferences] handle, same pattern
/// as the theme preferences. Read in `_prepareChatTrace`; the value is
/// snapshotted into the per-turn trace builder so flipping it never
/// affects an in-flight turn.
library;

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/preferences/theme_preferences.dart'
    show sharedPreferencesProvider;

const String _kPrefKey = 'naviwealth.ai.trace_verbose';

final aiTraceVerboseProvider =
    StateNotifierProvider<AiTraceVerboseController, bool>((ref) {
      return AiTraceVerboseController(ref.watch(sharedPreferencesProvider));
    });

class AiTraceVerboseController extends StateNotifier<bool> {
  AiTraceVerboseController(this._prefs)
    : super(_prefs.getBool(_kPrefKey) ?? false);

  final SharedPreferences _prefs;

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    await _prefs.setBool(_kPrefKey, value);
  }

  Future<void> toggle() => set(!state);
}
