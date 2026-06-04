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
    home: FTheme(data: FThemes.slate.light.desktop, child: child),
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
  });
}
