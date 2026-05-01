import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    // FIR-84: the shell now picks NavigationBar / Rail / Drawer by viewport
    // width. Pin a mobile-sized surface so this smoke test keeps asserting
    // bottom-nav behavior; the responsive switch is covered in router_test.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // The dashboard subscribes to live DB streams. With no real
          // database in the test environment, short-circuit the streams
          // so the home page resolves to its empty state.
          manualAssetsStreamProvider.overrideWith(
            (ref) => Stream<List<Asset>>.value(const []),
          ),
          physicalAssetsListProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          liabilitiesStreamProvider.overrideWith(
            (ref) => Stream<List<Liability>>.value(const []),
          ),
          accountsStreamProvider.overrideWith(
            (ref) => Stream<List<Account>>.value(const []),
          ),
        ],
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
