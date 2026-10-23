import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/shell/shell_chrome.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/core/shell/sync_attention.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_greeting_header.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full shell heading stays usable at $width with text $scale', (
        tester,
      ) async {
        await _pump(tester, width: width, textScale: scale, syncFailed: true);

        expect(tester.takeException(), isNull);
        final titleSize = tester.getSize(find.text('Inbox'));
        // The title must stay on one line, even with every production control.
        expect(titleSize.height, lessThanOrEqualTo(32 * scale));
        expect(
          find.bySemanticsLabel('Quick note').hitTestable(),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('More actions'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('New decision'), findsOneWidget);
        expect(find.text('Search'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.byIcon(FLucideIcons.cloudOff), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      });
    }
  }

  testWidgets('shared heading menu navigates to global settings', (
    tester,
  ) async {
    await _pump(tester, width: 360);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings destination'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('desktop heading keeps only domain actions', (tester) async {
    await _pump(tester, width: 1440);
    expect(find.bySemanticsLabel('Quick note'), findsOneWidget);
    expect(find.byType(DomainSwitcherChip), findsNothing);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('New decision'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Search'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  bool syncFailed = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/knowledge',
    routes: [
      GoRoute(
        path: '/knowledge',
        builder: (_, _) => const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(children: [KnowledgeGreetingHeader()]),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('Settings destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...appShellChromeOverrides(),
        activeDomainShellsProvider.overrideWithValue([
          _spec(DomainScope.finance, 'Finance', '/'),
          _spec(DomainScope.knowledge, 'Knowledge', '/knowledge'),
        ]),
        syncAttentionProvider.overrideWithValue(
          syncFailed
              ? SyncStatusEvent(status: SyncStatus.failed, at: DateTime(2026))
              : null,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: FTheme(
            data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DomainShellSpec _spec(DomainScope scope, String label, String path) =>
    DomainShellSpec(
      scope: scope,
      label: label,
      icon: FLucideIcons.layers,
      selectedIcon: FLucideIcons.layers,
      tabs: [
        DomainShellTab(
          icon: FLucideIcons.layers,
          selectedIcon: FLucideIcons.layers,
          label: label,
          routePath: path,
        ),
      ],
    );
