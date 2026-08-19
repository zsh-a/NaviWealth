import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap({
  required TargetPlatform platform,
  required ValueChanged<String> onChanged,
}) {
  return MaterialApp(
    theme: AppTheme.light().copyWith(platform: platform),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: AppAdaptiveSelectionMenu<String>(
            title: 'Choose portfolio',
            subtitle: '2 holdings',
            value: 'all',
            onChanged: onChanged,
            options: const [
              AppAdaptiveSelection<String>(
                value: 'all',
                title: 'All holdings',
                icon: Icons.layers_outlined,
              ),
              AppAdaptiveSelection<String>(
                value: 'long-term',
                title: 'Long term',
                icon: Icons.work_outline,
              ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => Focus(
              focusNode: focusNode,
              child: AppTappable(
                semanticsLabel: 'Portfolio scope',
                onPress: openMenu,
                child: const SizedBox(
                  width: 160,
                  height: 48,
                  child: Text('All holdings'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('uses a draggable app sheet on touch platforms', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        platform: TargetPlatform.android,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.text('All holdings'));
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Choose portfolio'), findsOneWidget);
    expect(find.text('2 holdings'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.check), findsOneWidget);

    await tester.tap(find.text('Long term'));
    await tester.pumpAndSettle();

    expect(selected, 'long-term');
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('uses an anchored single-choice menu on pointer platforms', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        platform: TargetPlatform.macOS,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.text('All holdings'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-adaptive-selection-menu.popover')),
      findsOneWidget,
    );
    expect(find.byType(AppSheet), findsNothing);
    expect(find.byIcon(FLucideIcons.check), findsOneWidget);

    await tester.tap(find.text('Long term'));
    await tester.pumpAndSettle();

    expect(selected, 'long-term');
    expect(find.text('Long term'), findsNothing);
  });
}
