import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('search exposes clear and restores input focus', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(
            body: AppSearchField(
              controller: controller,
              focusNode: focus,
              hint: 'Search',
              clearLabel: 'Clear search',
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(FLucideIcons.x), findsNothing);
    await tester.enterText(find.byType(EditableText), 'query');
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).textInputAction,
      TextInputAction.search,
    );
    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
    expect(focus.hasFocus, isTrue);
    expect(find.byIcon(FLucideIcons.x), findsNothing);
  });
}
