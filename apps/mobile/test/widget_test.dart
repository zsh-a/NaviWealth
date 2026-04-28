import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const NaviWealthApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home page localized title — "Overview" in en-US, "总览" in zh-CN.
    // Test environment falls back to the first supported locale (en).
    expect(find.text('Overview'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
