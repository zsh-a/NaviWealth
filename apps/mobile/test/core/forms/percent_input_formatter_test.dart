import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/forms/percent_input_formatter.dart';

void main() {
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
