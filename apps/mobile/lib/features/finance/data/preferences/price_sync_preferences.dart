import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';

/// Whether [PriceSyncCoordinator] writes daily-close snapshots into the
/// synced `prices` ledger. Default ON — cross-device historical valuation
/// is the eventually-consistent valuation contract.
const bool kDefaultWriteDailyPriceSnapshots = true;

/// User preference controlling the coordinator's daily snapshot write-back.
/// When OFF, the coordinator still warms the local `MarketQuotes` cache
/// but never enqueues `auto:*` rows on the OpLog, so other devices fetch
/// their own prices independently.
final writeDailyPriceSnapshotsProvider =
    StateNotifierProvider<WriteDailyPriceSnapshotsController, bool>((ref) {
      return WriteDailyPriceSnapshotsController(
        ref.watch(sharedPreferencesProvider),
      );
    });

class WriteDailyPriceSnapshotsController extends StateNotifier<bool> {
  WriteDailyPriceSnapshotsController(this._prefs) : super(_load(_prefs));

  static const String _key = 'naviwealth.settings.write_daily_price_snapshots';
  final SharedPreferences _prefs;

  static bool _load(SharedPreferences p) {
    return p.getBool(_key) ?? kDefaultWriteDailyPriceSnapshots;
  }

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    await _prefs.setBool(_key, value);
  }
}
