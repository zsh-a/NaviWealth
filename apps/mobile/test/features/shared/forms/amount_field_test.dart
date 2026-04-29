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
}
