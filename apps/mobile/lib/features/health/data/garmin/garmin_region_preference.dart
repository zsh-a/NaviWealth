/// Local preference for Garmin Connect region.
///
/// Garmin accounts are region-bound. The Rust client already supports China
/// and global endpoints; this preference removes the Dart-side hard-code.
library;

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/preferences/theme_preferences.dart';

enum GarminRegion { china, global }

extension GarminRegionX on GarminRegion {
  bool get isCn => this == GarminRegion.china;

  String get label => switch (this) {
    GarminRegion.china => 'CN',
    GarminRegion.global => 'Global',
  };

  String get description => switch (this) {
    GarminRegion.china => 'connect.garmin.cn',
    GarminRegion.global => 'connect.garmin.com',
  };

  String get wire => switch (this) {
    GarminRegion.china => 'china',
    GarminRegion.global => 'global',
  };

  static GarminRegion parse(String? raw) => switch (raw) {
    'global' => GarminRegion.global,
    _ => GarminRegion.china,
  };
}

final garminRegionProvider =
    StateNotifierProvider<GarminRegionController, GarminRegion>((ref) {
      return GarminRegionController(ref.watch(sharedPreferencesProvider));
    });

class GarminRegionController extends StateNotifier<GarminRegion> {
  GarminRegionController(this._prefs)
    : super(GarminRegionX.parse(_prefs.getString(_key)));

  static const String _key = 'lifeos.health.garmin.region';
  final SharedPreferences _prefs;

  Future<void> set(GarminRegion region) async {
    if (region == state) return;
    state = region;
    await _prefs.setString(_key, region.wire);
  }
}
