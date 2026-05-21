import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/preferences/theme_preferences.dart'
    show sharedPreferencesProvider;

/// How the user has chosen to operate the app.
///
/// - [unset]: first launch; the onboarding page is shown so the user can pick.
/// - [cloud]: traditional flow — login wall, data syncs through the backend.
/// - [localOnly]: data stays on this device; the sync engine and outbox are
///   inert. One-way: there is no UI affordance to upgrade to a cloud account.
enum AppMode {
  unset,
  cloud,
  localOnly;

  static AppMode parse(String? raw) {
    switch (raw) {
      case 'cloud':
        return AppMode.cloud;
      case 'local_only':
        return AppMode.localOnly;
      default:
        return AppMode.unset;
    }
  }

  String get wire => switch (this) {
    AppMode.unset => 'unset',
    AppMode.cloud => 'cloud',
    AppMode.localOnly => 'local_only',
  };
}

const String _kAppModeKey = 'app.mode.v1';

class AppModeStore {
  AppModeStore(this._ref);

  final Ref _ref;

  AppMode read() {
    final prefs = _ref.read(sharedPreferencesProvider);
    return AppMode.parse(prefs.getString(_kAppModeKey));
  }

  Future<void> write(AppMode mode) async {
    final prefs = _ref.read(sharedPreferencesProvider);
    await prefs.setString(_kAppModeKey, mode.wire);
  }
}

final appModeStoreProvider = Provider<AppModeStore>(AppModeStore.new);

/// Reactive snapshot of the persisted mode. Watch this from providers that
/// need to swap behaviour (router guard, outbox, mutation stamper). The
/// underlying SharedPreferences read is synchronous so no FutureProvider
/// is needed.
final appModeProvider = Provider<AppMode>((ref) {
  // Depend on the prefs handle so an in-test override propagates.
  ref.watch(sharedPreferencesProvider);
  return ref.watch(appModeStoreProvider).read();
});
