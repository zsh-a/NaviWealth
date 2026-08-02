import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {MediaQueryData? mediaQueryData}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: MediaQuery(
        data: mediaQueryData ?? const MediaQueryData(),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('ordinary sheet surfaces use the shared frosted material', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppSheetSurface(child: Text('content'))),
    );

    final surface = tester.widget<AppGlassSurface>(
      find.byKey(const ValueKey<String>('app-sheet.surface')),
    );
    expect(surface.role, AppGlassRole.sheet);
    expect(surface.frosted, isTrue);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('rendering-heavy sheets can opt out of live blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppSheetSurface(frosted: false, child: Text('content'))),
    );

    final surface = tester.widget<AppGlassSurface>(
      find.byKey(const ValueKey<String>('app-sheet.surface')),
    );
    expect(surface.role, AppGlassRole.sheet);
    expect(surface.frosted, isFalse);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('sheet ignores shell padding and keeps the device safe inset', (
    tester,
  ) async {
    const deviceSafeInset = 12.0;
    await tester.pumpWidget(
      _wrap(
        mediaQueryData: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 120),
          viewPadding: EdgeInsets.only(bottom: deviceSafeInset),
        ),
        const AppSheetSurface(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(key: Key('content'), height: 20),
          ),
        ),
      ),
    );

    final surfaceBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('app-sheet.surface')))
        .dy;
    final contentBottom = tester
        .getBottomRight(find.byKey(const Key('content')))
        .dy;

    expect(surfaceBottom - contentBottom, deviceSafeInset);
  });
}
