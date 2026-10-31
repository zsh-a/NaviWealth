import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(visualStyle: AppVisualStyle.classic),
    home: AppThemeScope(
      data: resolveAppTheme(
        const ThemeInputs(
          brightness: Brightness.light,
          marketMode: MarketColorMode.redUpGreenDown,
          visualStyle: AppVisualStyle.classic,
        ),
      ),
      child: FTheme(
        data: buildAppForuiTheme(
          brightness: Brightness.light,
          touch: false,
          visualStyle: AppVisualStyle.classic,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('exposes one named button with semantic activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(
      wrap(
        AppIconButton(
          icon: FLucideIcons.settings,
          tooltip: 'Open settings',
          onPress: () => presses += 1,
        ),
      ),
    );

    final action = find.semantics.byLabel('Open settings');
    final data = action.evaluate().single.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    tester.semantics.tap(action);
    await tester.pump();
    expect(presses, 1);
    semantics.dispose();
  });

  testWidgets('softPrimary shares the text action radius', (tester) async {
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
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
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

  testWidgets('clamps compact requests to the shared touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppIconButton(
          icon: FLucideIcons.settings,
          tooltip: 'Settings',
          size: 24,
          onPress: () {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppIconButton)), const Size(48, 48));
  });

  testWidgets('dock ring stays circular while review tiles use a quiet fill', (
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
    final ring = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
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
    final tile = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final tileDeco = tile.decoration! as BoxDecoration;
    expect(tileDeco.border, isNull);
    expect(tileDeco.borderRadius, BorderRadius.circular(AppRadius.md));
  });
}
