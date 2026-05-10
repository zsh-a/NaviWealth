import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefsKey = 'perf.glass.quality';

GlassQuality? loadSavedGlassQuality(SharedPreferences prefs) {
  final raw = prefs.getString(_kPrefsKey);
  if (raw == null) return null;
  for (final q in GlassQuality.values) {
    if (q.name == raw) return q;
  }
  return null;
}

Future<void> persistGlassQuality(
  SharedPreferences prefs,
  GlassQuality quality,
) async {
  await prefs.setString(_kPrefsKey, quality.name);
}
