import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 320,
  double textScale = 1,
}) {
  final dark = brightness == Brightness.dark;
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: FTheme(
        data: dark ? FTheme.neutral.dark.desktop : FTheme.neutral.light.desktop,
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selection indicator reserves its slot in both states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSelectionIndicator(selected: true),
            AppSelectionIndicator(selected: false),
          ],
        ),
      ),
    );

    final indicators = find.byType(AppSelectionIndicator);
    expect(indicators, findsNWidgets(2));
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((widget) => widget.opacity),
      orderedEquals(const [1.0, 0.0]),
    );
    expect(tester.getSize(indicators.at(0)), tester.getSize(indicators.at(1)));
  });

  testWidgets('metadata stays background-free and wraps in dark large type', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppMetadataStrip(
          children: [
            AppMetadataItem(label: 'Created', value: 'August 21, 2026'),
            AppMetadataItem(label: 'Updated', value: 'August 21, 2026'),
            AppMetadataTags(label: 'Tags', values: ['options', 'strategy']),
          ],
        ),
        brightness: Brightness.dark,
        width: 280,
        textScale: 1.8,
      ),
    );

    expect(find.byType(SoftCard), findsNothing);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('options'), findsOneWidget);
    expect(find.byType(Wrap), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
