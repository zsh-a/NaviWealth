import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';
import 'crash_reporter.dart';

/// User preference: ship anonymised crash reports + breadcrumbs.
///
/// **Defaults to OFF.** Per `roadmap-next.md` §3.6 + `roadmap-midterm-
/// execution.md` MT-2.6.M1, crash reporting must be opt-in — sending
/// telemetry without explicit consent is a non-starter for a local-first
/// finance app where the same process holds the user's keys, balances,
/// and Decimal P&L history.
///
/// The flag is stored locally in [SharedPreferences] (not synced) so a
/// shared install on a partner's device doesn't import the original user's
/// consent. The provider only gates upload — the [CrashReporter] interface
/// itself stays installed so call-sites can still drop `recordBreadcrumb`
/// calls without an env check.
final crashReportingEnabledProvider =
    StateNotifierProvider<CrashReportingPreferenceController, bool>((ref) {
      return CrashReportingPreferenceController(
        ref.watch(sharedPreferencesProvider),
      );
    });

class CrashReportingPreferenceController extends StateNotifier<bool> {
  CrashReportingPreferenceController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.crash_reporting.enabled';
  final SharedPreferences _prefs;

  static bool _load(SharedPreferences p) => p.getBool(_key) ?? false;

  Future<void> setEnabled(bool value) async {
    if (value == state) return;
    state = value;
    await _prefs.setBool(_key, value);
  }
}

/// [CrashReporter] decorator that drops every event when the user has not
/// opted in. Breadcrumbs are also dropped — recording them locally in
/// memory only to silently discard later would just waste cycles.
///
/// The wrapper lets us register one provider for the underlying reporter
/// (Sentry or test stub) and gate it from a single place rather than
/// scattering `if (enabled)` checks across every logger call site.
class OptInCrashReporter extends CrashReporter {
  OptInCrashReporter({required CrashReporter delegate, required this.enabled})
      : _delegate = delegate;

  final CrashReporter _delegate;

  /// Live update from the preference controller — no need to recreate the
  /// reporter when the user toggles the switch.
  bool enabled;

  @override
  void captureError(Object error, {StackTrace? stackTrace, String? hint}) {
    if (!enabled) return;
    _delegate.captureError(error, stackTrace: stackTrace, hint: hint);
  }

  @override
  void captureMessage(
    String message, {
    BreadcrumbLevel level = BreadcrumbLevel.info,
  }) {
    if (!enabled) return;
    _delegate.captureMessage(message, level: level);
  }

  @override
  void recordBreadcrumb({
    required String message,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    String? category,
  }) {
    if (!enabled) return;
    _delegate.recordBreadcrumb(
      message: message,
      level: level,
      category: category,
    );
  }

  @override
  void identifyUser({String? userId}) {
    if (!enabled) return;
    _delegate.identifyUser(userId: userId);
  }
}
