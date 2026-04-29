import 'package:flutter/material.dart';

/// ISO-4217 codes the app surfaces in the picker by default.
///
/// The DB-side currency dictionary (FIR-19's `currencies` table) is the
/// long-tail source of truth; this list is the short, opinionated default
/// the form ships with so users don't have to hunt for the common ones.
const List<({String code, String label})> kCommonCurrencies = [
  (code: 'CNY', label: 'CNY · 人民币'),
  (code: 'USD', label: 'USD · US Dollar'),
  (code: 'HKD', label: 'HKD · Hong Kong Dollar'),
  (code: 'EUR', label: 'EUR · Euro'),
  (code: 'JPY', label: 'JPY · 日元'),
  (code: 'GBP', label: 'GBP · British Pound'),
  (code: 'SGD', label: 'SGD · Singapore Dollar'),
  (code: 'AUD', label: 'AUD · Australian Dollar'),
  (code: 'CAD', label: 'CAD · Canadian Dollar'),
  (code: 'TWD', label: 'TWD · 新台币'),
];

/// Form-friendly currency dropdown.
///
/// Backed by [DropdownButtonFormField] so it composes with [Form] +
/// [Form.validate] the same way the other shared widgets do.
class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '币种',
    this.options = kCommonCurrencies,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final List<({String code, String label})> options;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // `value` is deprecated for `initialValue` after Flutter 3.33, but the
      // replacement is one-shot: it only honours the prop on first build.
      // Our pickers re-render with a fresh selection on every state change,
      // so the deprecated form-state-managed prop is still the right tool.
      // ignore: deprecated_member_use
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option.code, child: Text(option.label)),
      ],
      onChanged: onChanged,
      validator: (v) => (v == null || v.isEmpty) ? '请选择币种' : null,
    );
  }
}
