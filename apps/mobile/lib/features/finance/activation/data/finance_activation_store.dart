import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../design_system/preferences/theme_preferences.dart';

final financeImportConfirmedProvider =
    StateNotifierProvider<FinanceImportConfirmedController, bool>((ref) {
      return FinanceImportConfirmedController(
        ref.watch(sharedPreferencesProvider),
        ownerUserId: ref.watch(activeUserIdProvider) ?? 'local',
      );
    });

final financeActivationDismissedProvider =
    StateNotifierProvider<FinanceActivationDismissedController, bool>((ref) {
      return FinanceActivationDismissedController(
        ref.watch(sharedPreferencesProvider),
        ownerUserId: ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId,
      );
    });

/// User-owned visibility choice for the optional setup guide. Activation
/// progress continues to update even while the guide is hidden.
final class FinanceActivationDismissedController extends StateNotifier<bool> {
  FinanceActivationDismissedController(
    this._preferences, {
    required String ownerUserId,
  }) : _key = 'naviwealth.finance_activation.$ownerUserId.dismissed.v2',
       super(
         _preferences.getBool(
               'naviwealth.finance_activation.$ownerUserId.dismissed.v2',
             ) ??
             false,
       );

  final SharedPreferences _preferences;
  final String _key;

  Future<void> dismiss() async {
    state = true;
    await _preferences.setBool(_key, true);
  }
}

/// A device-local activation milestone. Draft rows are housekeeping data and
/// may be pruned, so they cannot be the long-term source of truth for whether
/// the user has already completed a first import.
final class FinanceImportConfirmedController extends StateNotifier<bool> {
  FinanceImportConfirmedController(
    this._preferences, {
    required String ownerUserId,
  }) : _key = 'naviwealth.finance_activation.import_confirmed.$ownerUserId',
       super(
         _preferences.getBool(
               'naviwealth.finance_activation.import_confirmed.$ownerUserId',
             ) ??
             false,
       );

  final SharedPreferences _preferences;
  final String _key;

  Future<void> markConfirmed() async {
    if (state) return;
    state = true;
    await _preferences.setBool(_key, true);
  }
}
