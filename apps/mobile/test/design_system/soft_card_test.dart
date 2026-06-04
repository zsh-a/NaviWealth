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

  testWidgets('raised cards add a modern surface shadow', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoftCard(level: SoftCardLevel.raised, child: Text('raised'))),
    );

    expect(_decoration(tester).boxShadow, isNotNull);
    expect(_decoration(tester).boxShadow, isNotEmpty);
  });
}
