import 'package:flutter/services.dart';

const percentInputFormatter = PercentInputFormatter();

class PercentInputFormatter extends TextInputFormatter {
  const PercentInputFormatter();

  static final _pattern = RegExp(r'^\d{0,3}(?:\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
