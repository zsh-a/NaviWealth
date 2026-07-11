import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  for (final width in <double>[390, 1023]) {
    testWidgets('uses one compact sliver stream at ${width.toInt()}dp', (
      tester,
    ) async {
      await _pumpTask(tester, size: Size(width, 844));

      expect(find.text('Compact controls'), findsOneWidget);
      expect(find.byKey(const Key('app-task-cockpit-rail')), findsNothing);
      expect(find.byType(Scrollable), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('app-task-primary-scroll')),
          matching: find.text('Compact controls'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[1024, 1200]) {
    testWidgets('switches to a fixed cockpit rail at ${width.toInt()}dp', (
      tester,
    ) async {
      await _pumpTask(tester, size: Size(width, 844));

      expect(find.text('Compact controls'), findsNothing);
      expect(find.byKey(const Key('app-task-cockpit-rail')), findsOneWidget);
      expect(find.text('Cockpit rail'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('app-task-cockpit-rail'))).width,
        340,
      );
      expect(find.byType(Scrollable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps footer outside the scroll and above bottom safe inset', (
    tester,
  ) async {
    await _pumpTask(
      tester,
      size: const Size(390, 844),
      bottomPadding: 34,
      textScaler: const TextScaler.linear(2),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('app-task-primary-scroll')),
        matching: find.text('Footer action'),
      ),
      findsNothing,
    );
    final footerBottom = tester.getBottomRight(find.text('Footer action')).dy;
    expect(844 - footerBottom, greaterThanOrEqualTo(34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds queue rows lazily', (tester) async {
    await _pumpTask(tester, size: const Size(390, 500));

    expect(find.text('Queue row 0'), findsOneWidget);
    expect(find.text('Queue row 99'), findsNothing);
    expect(find.textContaining('Queue row').evaluate().length, lessThan(100));
  });
}

Future<void> _pumpTask(
  WidgetTester tester, {
  required Size size,
  double bottomPadding = 0,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(compact: size.width >= Breakpoints.mobile),
      home: FTheme(
        data: buildAppForuiTheme(
          brightness: Brightness.light,
          touch: Breakpoints.isMobile(size.width),
        ),
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: bottomPadding),
            textScaler: textScaler,
          ),
          child: AppTaskScaffold(
            title: 'Tasks',
            showBack: false,
            compactLeadingSliversBuilder: (_) => const [
              SliverToBoxAdapter(child: Text('Compact controls')),
            ],
            primarySliversBuilder: (_) => [
              SliverList.builder(
                itemCount: 100,
                itemBuilder: (_, index) =>
                    SizedBox(height: 52, child: Text('Queue row $index')),
              ),
            ],
            railBuilder: (_) => const Text('Cockpit rail'),
            footerBuilder: (_) => const Text('Footer action'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
