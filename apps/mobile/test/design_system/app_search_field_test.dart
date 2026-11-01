import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('search waits for IME commit and emits clear once', (
    tester,
  ) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(
            body: AppSearchField(
              controller: controller,
              hint: 'Search',
              clearLabel: 'Clear',
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'bei',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(changes, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '北',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(changes, ['北']);
    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pumpAndSettle();
    expect(changes, ['北', '']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });

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
