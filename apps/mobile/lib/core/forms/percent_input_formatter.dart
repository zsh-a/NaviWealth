import 'package:flutter/services.dart';

const percentInputFormatter = PercentInputFormatter();

class PercentInputFormatter extends TextInputFormatter {
  const PercentInputFormatter({
    this.allowNegative = false,
    this.decimalPlaces = 2,
  });

  final bool allowNegative;
  final int? decimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final decimals = decimalPlaces == null ? '*' : '{0,$decimalPlaces}';
    final pattern = RegExp(
      '^${allowNegative ? '-?' : ''}\\d{0,3}(?:\\.\\d$decimals)?\$',
    );
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
