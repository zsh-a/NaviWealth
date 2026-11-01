import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_typography.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('AI text follows the active app type scale in both presets', (
    tester,
  ) async {
    final heights = <double>[];
    for (final visual in AppVisualStyle.values) {
      final theme = resolveAppTheme(
        ThemeInputs(
          brightness: Brightness.light,
          marketMode: MarketColorMode.redUpGreenDown,
          visualStyle: visual,
        ),
      );
      await tester.pumpWidget(
        AppThemeScope(
          data: theme,
          child: MaterialApp(
            home: FTheme(
              data: buildAppForuiTheme(
                brightness: Brightness.light,
                visualStyle: visual,
                touch: true,
              ),
              child: Builder(
                builder: (context) => Column(
                  children: [
                    Text('chat', style: AiType.body(context)),
                    Text('reading', style: AiType.readingBody(context)),
                    Text('metadata', style: AiType.meta(context)),
                    Text('label', style: AiType.label(context)),
                    Text('title', style: AiType.title(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final roles = {
        'chat': theme.type.bodySmall,
        'reading': theme.type.body,
        'metadata': theme.type.caption,
        'label': theme.type.labelSmall,
        'title': theme.type.title,
      };
      for (final entry in roles.entries) {
        final actual = tester.widget<Text>(find.text(entry.key)).style!;
        expect(actual.fontSize, entry.value.fontSize);
        expect(actual.height, entry.value.height);
        expect(actual.letterSpacing, entry.value.letterSpacing);
      }
      heights.add(tester.widget<Text>(find.text('chat')).style!.height!);
    }
    expect(heights.last, lessThan(heights.first));
  });
}
