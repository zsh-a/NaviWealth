import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('softPrimary paints a circular primary-tint surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppIconButton.softPrimary(
          icon: FLucideIcons.check,
          tooltip: 'Done',
          onPress: () {},
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.rectangle);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.full));
    expect(decoration.color, isNotNull);
  });

  testWidgets('plain surface stays undecorated', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppIconButton(
          icon: FLucideIcons.settings,
          tooltip: 'Settings',
          onPress: () {},
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container).first);
    expect(container.decoration, isNull);
  });

  testWidgets('softPrimaryRing and softPrimaryTile paint borders', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppIconButton.softPrimaryRing(
          icon: FLucideIcons.sparkles,
          tooltip: 'Ask AI',
          onPress: () {},
        ),
      ),
    );
    final ring = tester.widget<Container>(find.byType(Container).first);
    final ringDeco = ring.decoration! as BoxDecoration;
    expect(ringDeco.border, isNotNull);
    expect(ringDeco.borderRadius, BorderRadius.circular(AppRadius.full));

    await tester.pumpWidget(
      wrap(
        AppIconButton.softPrimaryTile(
          icon: FLucideIcons.check,
          tooltip: 'Accept',
          onPress: () {},
        ),
      ),
    );
    final tile = tester.widget<Container>(find.byType(Container).first);
    final tileDeco = tile.decoration! as BoxDecoration;
    expect(tileDeco.border, isNotNull);
    expect(tileDeco.borderRadius, BorderRadius.circular(AppRadius.sm));
  });
}
