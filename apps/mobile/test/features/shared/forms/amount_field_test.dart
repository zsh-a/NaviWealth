import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/shared/forms/forms.dart';

void main() {
  testWidgets('rejects empty input when required', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: const AmountField(label: '金额'),
          ),
        ),
      ),
    );
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请输入金额'), findsOneWidget);
  });

  testWidgets('accepts a Decimal-shaped input', (tester) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AmountField(label: '金额', controller: controller),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '12345.6789');
    expect(formKey.currentState!.validate(), isTrue);
    expect(readAmount(controller), Decimal.parse('12345.6789'));
  });

  testWidgets('blocks negative input when allowNegative is false', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmountField(label: '金额', controller: controller),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '-5');
    // FilteringTextInputFormatter.allow rejects any value whose final form
    // doesn't match the pattern, so a typed `-5` reverts to the previous
    // (empty) string — which is the right user-facing outcome regardless.
    expect(controller.text, '');
  });

  testWidgets(
    'preserves text and cursor across rebuilds when no controller is supplied',
    (tester) async {
      var counter = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                // Avoid `const` so Flutter doesn't short-circuit the rebuild
                // and skip AmountField.build — the bug only surfaces when
                // build actually re-runs.
                return Column(
                  children: [
                    AmountField(label: '金额 #$counter'),
                    TextButton(
                      onPressed: () => setState(() => counter++),
                      child: const Text('rebuild'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), '1234.5');
      // Place the cursor in the middle of the entered text.
      final beforeRebuild = tester.widget<TextField>(find.byType(TextField));
      beforeRebuild.controller!.selection = const TextSelection.collapsed(
        offset: 3,
      );
      await tester.pump();
      expect(find.text('1234.5'), findsOneWidget);

      await tester.tap(find.text('rebuild'));
      await tester.pump();

      // The rendered text and cursor must survive the parent rebuild.
      expect(find.text('1234.5'), findsOneWidget);
      final afterRebuild = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(afterRebuild.controller.text, '1234.5');
      expect(afterRebuild.controller.selection.baseOffset, 3);
    },
  );
}
