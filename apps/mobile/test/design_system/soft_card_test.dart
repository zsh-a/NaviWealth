import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(data: FTheme.neutral.light.desktop, child: child),
  );
}

Widget _wrapDark(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: FTheme(
      data: buildAppForuiTheme(brightness: Brightness.dark, touch: false),
      child: child,
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
  return box.decoration as BoxDecoration;
}

void main() {
  testWidgets('flat cards stay shadowless for dense repeated rows', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SoftCard(child: Text('flat'))));

    expect(_decoration(tester).boxShadow, isNull);
  });

  testWidgets('flat cards avoid hard borders in dense lists', (tester) async {
    await tester.pumpWidget(_wrap(const SoftCard(child: Text('flat'))));

    expect(_decoration(tester).border, isNull);
  });

  testWidgets('raised cards separate with a solid fill', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoftCard(level: SoftCardLevel.raised, child: Text('raised'))),
    );

    expect(_decoration(tester).boxShadow, isNull);
    expect(_decoration(tester).color, isNotNull);
  });

  testWidgets('raised cards remain borderless at rest', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoftCard(level: SoftCardLevel.raised, child: Text('raised'))),
    );

    expect(_decoration(tester).border, isNull);
  });

  testWidgets('dark raised cards use tonal lift without a shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapDark(
        const SoftCard(level: SoftCardLevel.raised, child: Text('raised')),
      ),
    );

    expect(_decoration(tester).boxShadow, isNull);
    expect(_decoration(tester).border, isNull);
  });

  testWidgets('hero cards resolve a larger corner radius by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const SoftCard(level: SoftCardLevel.hero, child: Text('hero'))),
    );

    final radius = _decoration(tester).borderRadius as BorderRadius?;
    expect(radius?.topLeft.x, AppRadius.lg);
  });

  testWidgets('hero cards remain neutral and shadowless', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoftCard(level: SoftCardLevel.hero, child: Text('hero'))),
    );

    expect(_decoration(tester).gradient, isNull);
    expect(_decoration(tester).boxShadow, isNull);
  });
}
