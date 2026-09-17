import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/forms/percent_input_formatter.dart';

void main() {
  test('signed rates retain caller-selected precision', () {
    const formatter = PercentInputFormatter(
      allowNegative: true,
      decimalPlaces: null,
    );
    const value = TextEditingValue(text: '-2.123456');
    expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    expect(
      formatter.formatEditUpdate(value, const TextEditingValue(text: '-2..1')),
      value,
    );
  });

  test('accepts a bounded percentage shape and rejects malformed edits', () {
    const formatter = PercentInputFormatter();
    const empty = TextEditingValue.empty;
    const valid = TextEditingValue(text: '33.33');

    expect(formatter.formatEditUpdate(empty, valid), valid);
    expect(
      formatter.formatEditUpdate(valid, const TextEditingValue(text: '33.333')),
      valid,
    );
    expect(
      formatter.formatEditUpdate(valid, const TextEditingValue(text: '33..3')),
      valid,
    );
  });
}
