import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/design_system.dart';

/// Decimal-precision amount entry.
///
/// We expose a plain [TextFormField] under the hood — Material's currency
/// fields don't preserve trailing zeros and silently coerce to `double`,
/// which is exactly the bug we're trying to avoid by using [Decimal] in
/// the model.
///
/// `validator` returns `null` on success, or the localised error string;
/// callers compose it with [FormState.validate] in the usual way.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.currencyCode,
    this.allowNegative = false,
    this.required = true,
    this.helperText,
    this.onChanged,
  });

  final String label;
  final Decimal? initialValue;
  final TextEditingController? controller;
  final String? currencyCode;
  final bool allowNegative;
  final bool required;
  final String? helperText;
  final void Function(Decimal? value)? onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveController =
        controller ??
        TextEditingController(text: initialValue?.toString() ?? '');
    final pattern = allowNegative
        ? RegExp(r'^-?\d*\.?\d*$')
        : RegExp(r'^\d*\.?\d*$');
    return TextFormField(
      controller: effectiveController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(pattern)],
      style: TypographyTokens.numericBody.copyWith(
        fontFeatures: TypographyTokens.tabularFigures,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: currencyCode == null ? null : '$currencyCode ',
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) {
          return required ? '请输入金额' : null;
        }
        final parsed = Decimal.tryParse(trimmed);
        if (parsed == null) return '金额格式不正确';
        if (!allowNegative && parsed < Decimal.zero) return '金额不能为负';
        return null;
      },
      onChanged: onChanged == null
          ? null
          : (raw) {
              onChanged!(Decimal.tryParse(raw.trim()));
            },
    );
  }
}

/// Resolve the entered text from an [AmountField] to a [Decimal].
Decimal? readAmount(TextEditingController controller) {
  return Decimal.tryParse(controller.text.trim());
}
