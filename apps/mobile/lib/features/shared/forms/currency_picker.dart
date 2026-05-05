import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// ISO-4217 codes the app surfaces in the picker by default.
///
/// The DB-side currency dictionary (FIR-19's `currencies` table) is the
/// long-tail source of truth; this list is the short, opinionated default
/// the form ships with so users don't have to hunt for the common ones.
/// Display labels resolve through [currencyDisplayLabel] so each currency
/// reads in the user's locale.
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
/// Falls back to the bare code when no entry exists in the ARB tables.
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

/// Picker-row label (`"USD · US Dollar"` / `"USD · 美元"`). Composed via
/// the `currencyOptionLabel` ARB so locales that prefer a different
/// separator can override the template.
String currencyDisplayLabel(AppLocalizations l10n, String code) {
  return l10n.currencyOptionLabel(code, currencyDisplayName(l10n, code));
}

/// Form-friendly currency dropdown.
///
/// Backed by [DropdownButtonFormField] so it composes with [Form] +
/// [Form.validate] the same way the other shared widgets do.
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

  /// Override the label. When null the localised default
  /// (`formCurrencyPickerLabelDefault`) is used.
  final String? label;
  final List<String> options;

  /// When `false`, the picker is rendered in a disabled (read-only) state.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDropdown<String>(
      label: label ?? l10n.formCurrencyPickerLabelDefault,
      value: value,
      enabled: enabled,
      items: [
        for (final code in options)
          DropdownMenuItem(
            value: code,
            child: Text(currencyDisplayLabel(l10n, code)),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (v) =>
          (v == null || v.isEmpty) ? l10n.formCurrencyPickerRequired : null,
    );
  }
}
