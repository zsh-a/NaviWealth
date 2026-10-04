import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_validation.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('reveals and focuses the first error without losing input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final formKey = GlobalKey<FormState>();
    final focus = FocusNode();
    final controller = TextEditingController(text: 'Keep this note');
    final scroll = ScrollController();
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    bool? valid;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: Form(
                      key: formKey,
                      child: Column(
                        children: [
                          FTextFormField(
                            key: const ValueKey('required-field'),
                            focusNode: focus,
                            label: const Text('Amount'),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Enter an amount'
                                : null,
                          ),
                          const SizedBox(height: 1000),
                          FTextFormField(
                            control: FTextFieldControl.managed(
                              controller: controller,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                FButton(
                  onPress: () => valid = validateAndRevealForm(formKey),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(valid, isFalse);
    expect(focus.hasFocus, isTrue);
    expect(scroll.offset, lessThan(100));
    expect(find.text('Enter an amount').hitTestable(), findsOneWidget);
    expect(controller.text, 'Keep this note');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('required-field')),
        matching: find.byType(EditableText),
      ),
      '25',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(valid, isTrue);
    expect(find.text('Enter an amount'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('focuses a missing select without opening its popup', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(
            body: Form(
              key: key,
              child: FSelect<String>.rich(
                format: (value) => value,
                focusNode: focus,
                validator: (value) => value == null ? 'Choose account' : null,
                children: const [
                  FSelectItem(value: 'bank', title: Text('Bank')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(validateAndRevealForm(key), isFalse);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.text('Bank'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
