import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
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
      expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
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
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
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
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      expect(find.byKey(const Key('edit')), findsOneWidget);
    });
  });
}
