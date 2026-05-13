import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// ISO-4217 codes the app surfaces in the picker by default.
const List<String> kCommonCurrencies = [
  'CNY',
  'USD',
  'HKD',
  'EUR',
  'JPY',
  'GBP',
  'SGD',
  'AUD',
  'CAD',
  'TWD',
];

/// Look up the localised display name for an ISO-4217 currency code.
String currencyDisplayName(AppLocalizations l10n, String code) {
  switch (code) {
    case 'CNY':
      return l10n.currencyNameCNY;
    case 'USD':
      return l10n.currencyNameUSD;
    case 'HKD':
      return l10n.currencyNameHKD;
    case 'EUR':
      return l10n.currencyNameEUR;
    case 'JPY':
      return l10n.currencyNameJPY;
    case 'GBP':
      return l10n.currencyNameGBP;
    case 'SGD':
      return l10n.currencyNameSGD;
    case 'AUD':
      return l10n.currencyNameAUD;
    case 'CAD':
      return l10n.currencyNameCAD;
    case 'TWD':
      return l10n.currencyNameTWD;
    default:
      return code;
  }
}

/// Picker-row label (`"USD · US Dollar"` / `"USD · 美元"`).
String currencyDisplayLabel(AppLocalizations l10n, String code) {
  return l10n.currencyOptionLabel(code, currencyDisplayName(l10n, code));
}

/// Form-friendly currency dropdown built on forui's [FSelect].
class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.options = kCommonCurrencies,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final List<String> options;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveValue = value == null || value!.isEmpty ? null : value;
    final effectiveOptions = [
      ...options,
      if (effectiveValue != null && !options.contains(effectiveValue))
        effectiveValue,
    ];
    final items = <String, String>{
      for (final code in effectiveOptions)
        currencyDisplayLabel(l10n, code): code,
    };
    return FSelect<String>(
      items: items,
      control: FSelectControl<String>.managed(
        initial: effectiveValue,
        onChange: enabled ? onChanged : (_) {},
      ),
      label: Text(label ?? l10n.formCurrencyPickerLabelDefault),
      enabled: enabled,
      validator: (v) =>
          (v == null || v.isEmpty) ? l10n.formCurrencyPickerRequired : null,
    );
  }
}
