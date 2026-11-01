import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {MediaQueryData? mediaQueryData}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: MediaQuery(
        data: mediaQueryData ?? const MediaQueryData(),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('disabled motion resizes changing sheet content immediately', (
    tester,
  ) async {
    var expanded = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AppSheet(
              title: 'Details',
              child: SizedBox(
                key: const Key('sheet-content'),
                height: expanded ? 240 : 60,
              ),
            );
          },
        ),
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    rebuild(() => expanded = true);
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('sheet-content'))).height, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary sheet surfaces default to solid material', (
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
    expect(surface.softLight, isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
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
    expect(surface.softLight, isTrue);
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
