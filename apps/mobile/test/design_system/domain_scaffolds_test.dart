import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: FTheme(data: FTheme.neutral.light.desktop, child: child),
  );
}

void main() {
  group('DomainTabScaffold', () {
    testWidgets('renders the title and NO back arrow (tab roots)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DomainTabScaffold(
            title: '今日 · HealthOS',
            child: Text('body', key: Key('body')),
          ),
        ),
      );
      expect(find.text('今日 · HealthOS'), findsOneWidget);
      expect(find.byKey(const Key('body')), findsOneWidget);
      // Tab roots are the back-target — they must not render a back arrow.
      expect(find.byKey(const ValueKey('app.back')), findsNothing);
    });

    testWidgets('keeps header controls reachable when title collapses', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DomainTabScaffold(
            title: 'Activity',
            actions: [
              FHeaderAction(
                icon: const Icon(FLucideIcons.search, key: Key('search')),
                onPress: () {},
              ),
            ],
            child: ListView.builder(
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(height: 48, child: Text('row $index')),
            ),
          ),
        ),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.byKey(const Key('search')), findsOneWidget);

      await tester.drag(find.text('row 10'), const Offset(0, -260));
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsNothing);
      expect(find.byKey(const Key('search')), findsOneWidget);
    });
  });

  group('ObjectDetailScaffold', () {
    testWidgets('injects the back arrow automatically', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ObjectDetailScaffold(
            title: '概念',
            child: Text('detail', key: Key('detail')),
          ),
        ),
      );
      expect(find.text('概念'), findsOneWidget);
      expect(find.byKey(const Key('detail')), findsOneWidget);
      // The whole point: a pushed detail page can never forget the back
      // arrow — it comes from the scaffold, not the page.
      expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
    });

    testWidgets('renders trailing actions alongside the back arrow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ObjectDetailScaffold(
            title: '决策详情',
            actions: [
              FHeaderAction(
                icon: const Icon(FLucideIcons.pencil, key: Key('edit')),
                onPress: () {},
              ),
            ],
            child: const Text('detail'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
      expect(find.byKey(const Key('edit')), findsOneWidget);
    });

    testWidgets('accepts a custom title widget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ObjectDetailScaffold(
            titleWidget: Text('Hero title', key: Key('title')),
            child: Text('detail'),
          ),
        ),
      );

      expect(find.byKey(const Key('title')), findsOneWidget);
      expect(find.byKey(const ValueKey('app.back')), findsOneWidget);
    });
  });

  group('FloatingGlassNavBar', () {
    testWidgets('renders a compact trailing assistant action', (tester) async {
      var assistantTaps = 0;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SizedBox(
              width: 420,
              child: FloatingGlassNavBar(
                items: const [
                  FloatingNavTab(
                    icon: FLucideIcons.inbox,
                    selectedIcon: FLucideIcons.inbox,
                    label: 'Inbox',
                  ),
                  FloatingNavTab(
                    icon: FLucideIcons.bookOpen,
                    selectedIcon: FLucideIcons.bookOpen,
                    label: 'Library',
                  ),
                  FloatingNavTab(
                    icon: FLucideIcons.clipboardCheck,
                    selectedIcon: FLucideIcons.clipboardCheck,
                    label: 'Review',
                  ),
                ],
                selectedIndex: 1,
                onIndexChanged: (_) {},
                onAssistantAction: () => assistantTaps += 1,
                assistantLabel: 'Ask AI',
                assistantSemanticLabel: 'Open assistant',
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(FloatingGlassNavBar)).height,
        kFloatingGlassNavBarHeight,
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      final glassSurface = tester.widget<AppGlassSurface>(
        find.descendant(
          of: find.byType(FloatingGlassNavBar),
          matching: find.byType(AppGlassSurface),
        ),
      );
      expect(glassSurface.boxShadow, hasLength(1));
      expect(glassSurface.borderRadius, BorderRadius.circular(AppRadius.full));
      final selectionIndicators = find.descendant(
        of: find.byType(FloatingGlassNavBar),
        matching: find.byType(AppSelectionIndicator),
      );
      expect(selectionIndicators, findsNWidgets(3));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.descendant(
                of: selectionIndicators,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .map((widget) => widget.opacity),
        orderedEquals(const [0.0, 1.0, 0.0]),
      );
      final assistant = find.byKey(
        const ValueKey<String>('floating-nav.assistant'),
      );
      expect(tester.getSize(assistant).height, AppSpacing.s40);
      expect(find.text('Ask AI'), findsOneWidget);
      expect(find.bySemanticsLabel('Open assistant'), findsOneWidget);

      final surface = tester.widget<Container>(assistant);
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.border, isNull);

      await tester.tap(assistant);
      await tester.pumpAndSettle();
      expect(assistantTaps, 1);
    });

    testWidgets('hides the assistant label on narrow navigation bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SizedBox(
              width: 360,
              child: FloatingGlassNavBar(
                items: const [
                  FloatingNavTab(
                    icon: FLucideIcons.inbox,
                    selectedIcon: FLucideIcons.inbox,
                    label: 'Inbox',
                  ),
                  FloatingNavTab(
                    icon: FLucideIcons.bookOpen,
                    selectedIcon: FLucideIcons.bookOpen,
                    label: 'Library',
                  ),
                  FloatingNavTab(
                    icon: FLucideIcons.clipboardCheck,
                    selectedIcon: FLucideIcons.clipboardCheck,
                    label: 'Review',
                  ),
                ],
                selectedIndex: 0,
                onIndexChanged: (_) {},
                onAssistantAction: () {},
                assistantLabel: 'Ask AI',
                assistantSemanticLabel: 'Open assistant',
              ),
            ),
          ),
        ),
      );

      final assistant = find.byKey(
        const ValueKey<String>('floating-nav.assistant'),
      );
      expect(find.text('Ask AI'), findsNothing);
      expect(find.bySemanticsLabel('Open assistant'), findsOneWidget);
      expect(tester.getSize(assistant).width, AppSpacing.s40);
    });
  });
}
