import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/shell/desktop_sidebar.dart';
import 'package:naviwealth/core/shell/shell_preferences.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('collapse and expand remain overflow-free at every frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DesktopSidebar(
                workspace: DesktopSidebarWorkspace(
                  icon: FLucideIcons.layers3,
                  label: 'A workspace name that must truncate cleanly',
                  onPress: () {},
                ),
                destinations: const [
                  DesktopSidebarDestination(
                    icon: FLucideIcons.house,
                    selectedIcon: FLucideIcons.house,
                    label: 'A destination name that must truncate cleanly',
                  ),
                ],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                footerActions: [
                  DesktopSidebarAction(
                    icon: FLucideIcons.sparkles,
                    label: 'A pinned action that must truncate cleanly',
                    onPress: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.chevronLeft));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      kSidebarCollapsedWidth,
    );
    expect(find.textContaining('destination name'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.chevronRight));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      kSidebarExpandedWidth,
    );
    expect(find.textContaining('destination name'), findsOneWidget);
  });
}
