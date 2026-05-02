import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';

/// Per-device "last used" defaults for the entry forms (FIR-95).
///
/// Snapshots the most recently chosen account / currency / category so
/// repeat entries pre-fill with whatever the user picked last time. The
/// data is intentionally per-device — these are workflow ergonomics, not
/// synced settings, and we do not want device A's habits to override the
/// last selection on device B mid-entry.
@immutable
class FormDefaults {
  const FormDefaults({
    this.tradeAccountId,
    this.tradeCurrency,
    this.expenseAccountId,
    this.expenseCategoryId,
    this.expenseCurrency,
    this.assetAccountId,
    this.assetCurrency,
  });

  final String? tradeAccountId;
  final String? tradeCurrency;
  final String? expenseAccountId;
  final String? expenseCategoryId;
  final String? expenseCurrency;
  final String? assetAccountId;
  final String? assetCurrency;

  FormDefaults copyWith({
    Object? tradeAccountId = _sentinel,
    Object? tradeCurrency = _sentinel,
    Object? expenseAccountId = _sentinel,
    Object? expenseCategoryId = _sentinel,
    Object? expenseCurrency = _sentinel,
    Object? assetAccountId = _sentinel,
    Object? assetCurrency = _sentinel,
  }) {
    return FormDefaults(
      tradeAccountId: tradeAccountId == _sentinel
          ? this.tradeAccountId
          : tradeAccountId as String?,
      tradeCurrency: tradeCurrency == _sentinel
          ? this.tradeCurrency
          : tradeCurrency as String?,
      expenseAccountId: expenseAccountId == _sentinel
          ? this.expenseAccountId
          : expenseAccountId as String?,
      expenseCategoryId: expenseCategoryId == _sentinel
          ? this.expenseCategoryId
          : expenseCategoryId as String?,
      expenseCurrency: expenseCurrency == _sentinel
          ? this.expenseCurrency
          : expenseCurrency as String?,
      assetAccountId: assetAccountId == _sentinel
          ? this.assetAccountId
          : assetAccountId as String?,
      assetCurrency: assetCurrency == _sentinel
          ? this.assetCurrency
          : assetCurrency as String?,
    );
  }

  static const Object _sentinel = Object();
}

/// Persists [FormDefaults] in [SharedPreferences].
///
/// Keys are prefixed `naviwealth.forms.*` to keep them adjacent in the
/// device's preferences blob and easy to grep when a future feature needs
/// to migrate or wipe them.
final formDefaultsProvider =
    StateNotifierProvider<FormDefaultsController, FormDefaults>((ref) {
  return FormDefaultsController(ref.watch(sharedPreferencesProvider));
});

class FormDefaultsController extends StateNotifier<FormDefaults> {
  FormDefaultsController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _kTradeAccount = 'naviwealth.forms.trade.account';
  static const _kTradeCurrency = 'naviwealth.forms.trade.currency';
  static const _kExpenseAccount = 'naviwealth.forms.expense.account';
  static const _kExpenseCategory = 'naviwealth.forms.expense.category';
  static const _kExpenseCurrency = 'naviwealth.forms.expense.currency';
  static const _kAssetAccount = 'naviwealth.forms.asset.account';
  static const _kAssetCurrency = 'naviwealth.forms.asset.currency';

  static FormDefaults _load(SharedPreferences p) => FormDefaults(
        tradeAccountId: _read(p, _kTradeAccount),
        tradeCurrency: _read(p, _kTradeCurrency),
        expenseAccountId: _read(p, _kExpenseAccount),
        expenseCategoryId: _read(p, _kExpenseCategory),
        expenseCurrency: _read(p, _kExpenseCurrency),
        assetAccountId: _read(p, _kAssetAccount),
        assetCurrency: _read(p, _kAssetCurrency),
      );

  static String? _read(SharedPreferences p, String key) {
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> rememberTrade({String? accountId, String? currency}) async {
    state = state.copyWith(
      tradeAccountId: accountId ?? state.tradeAccountId,
      tradeCurrency: currency ?? state.tradeCurrency,
    );
    await _writeIfPresent(_kTradeAccount, accountId);
    await _writeIfPresent(_kTradeCurrency, currency);
  }

  Future<void> rememberExpense({
    String? accountId,
    String? categoryId,
    String? currency,
  }) async {
    state = state.copyWith(
      expenseAccountId: accountId ?? state.expenseAccountId,
      expenseCategoryId: categoryId ?? state.expenseCategoryId,
      expenseCurrency: currency ?? state.expenseCurrency,
    );
    await _writeIfPresent(_kExpenseAccount, accountId);
    await _writeIfPresent(_kExpenseCategory, categoryId);
    await _writeIfPresent(_kExpenseCurrency, currency);
  }

  Future<void> rememberAsset({String? accountId, String? currency}) async {
    state = state.copyWith(
      assetAccountId: accountId ?? state.assetAccountId,
      assetCurrency: currency ?? state.assetCurrency,
    );
    await _writeIfPresent(_kAssetAccount, accountId);
    await _writeIfPresent(_kAssetCurrency, currency);
  }

  Future<void> _writeIfPresent(String key, String? value) async {
    if (value == null || value.isEmpty) return;
    await _prefs.setString(key, value);
  }
}
