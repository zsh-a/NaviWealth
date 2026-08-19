import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap({
  required TargetPlatform platform,
  required List<AppAdaptiveAction> actions,
}) {
  return MaterialApp(
    theme: AppTheme.light().copyWith(platform: platform),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: AppAdaptiveActionMenu(
            title: 'More actions',
            actions: actions,
            triggerBuilder: (context, openMenu, focusNode) => Focus(
              focusNode: focusNode,
              child: Semantics(
                button: true,
                label: 'More',
                child: GestureDetector(
                  onTap: openMenu,
                  child: const SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.more_horiz),
                  ),
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
  testWidgets('uses a bottom sheet on touch platforms', (tester) async {
    var selected = false;
    await tester.pumpWidget(
      _wrap(
        platform: TargetPlatform.android,
        actions: [
          AppAdaptiveAction(
            icon: Icons.edit_outlined,
            title: 'Edit',
            subtitle: 'Update details',
            onPress: () => selected = true,
          ),
        ],
      ),
    );

    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.byType(AppActionSheetList), findsOneWidget);
    expect(find.text('Update details'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(selected, isTrue);
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('uses an anchored compact menu on pointer platforms', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      _wrap(
        platform: TargetPlatform.macOS,
        actions: [
          AppAdaptiveAction(
            icon: Icons.delete_outline,
            title: 'Delete',
            subtitle: 'This hint belongs to the touch sheet',
            destructive: true,
            onPress: () => selected = true,
          ),
        ],
      ),
    );

    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-adaptive-action-menu.popover')),
      findsOneWidget,
    );
    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('This hint belongs to the touch sheet'), findsNothing);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(selected, isTrue);
    expect(find.text('Delete'), findsNothing);
  });
}
