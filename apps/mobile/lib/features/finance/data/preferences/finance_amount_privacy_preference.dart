import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';

/// FinanceOS-wide preference for masking monetary values on screen.
///
/// This is deliberately separate from the AI privacy posture: it controls
/// presentation only and persists locally so moving between Finance tabs (or
/// relaunching the app) never reveals amounts unexpectedly.
final financeAmountsHiddenProvider =
    StateNotifierProvider<FinanceAmountsHiddenController, bool>((ref) {
      return FinanceAmountsHiddenController(
        ref.watch(sharedPreferencesProvider),
      );
    });

class FinanceAmountsHiddenController extends StateNotifier<bool> {
  FinanceAmountsHiddenController(this._preferences)
    : super(_preferences.getBool(_key) ?? false);

  static const String _key = 'naviwealth.finance.amounts_hidden';

  final SharedPreferences _preferences;

  Future<void> setHidden(bool hidden) async {
    if (hidden == state) return;
    state = hidden;
    await _preferences.setBool(_key, hidden);
  }

  Future<void> toggle() => setHidden(!state);
}
