import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('ordinary sheet surfaces are fully opaque', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppSheetSurface(child: Text('content'))),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('app-sheet.surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color!.a, 1);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('frosted sheets retain blur and translucent tint', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppSheetSurface(frosted: true, child: Text('content'))),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('app-sheet.surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color!.a, lessThan(1));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
