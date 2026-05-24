import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('settings_page', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'settings_page',
      variant: variant,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const SettingsPage(),
    );
  });
}
