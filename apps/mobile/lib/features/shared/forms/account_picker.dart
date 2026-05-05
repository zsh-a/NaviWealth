import 'package:flutter/material.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Drop-down picker over the user's existing accounts.
///
/// The asset entry forms need to associate the new holding with one of
/// the user's accounts; this widget centralises the rendering so all of
/// them stay consistent.
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    super.key,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.label,
    this.allowedTypes,
  });

  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Override the label. When null the localised default
  /// (`formAccountPickerLabelDefault`) is used.
  final String? label;

  /// If non-null, only accounts whose [AccountType] is in this set are
  /// shown. Asset forms restrict by appropriate account family — e.g.
  /// cash flows are only meaningful in bank/cash accounts.
  final Set<AccountType>? allowedTypes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = allowedTypes == null
        ? accounts
        : accounts.where((a) => allowedTypes!.contains(a.type)).toList();
    // Null out value if it doesn't exist in the filtered list to avoid
    // AppDropdown assertion errors.
    final effectiveValue =
        filtered.any((a) => a.id == value) ? value : null;
    return AppDropdown<String>(
      label: label ?? l10n.formAccountPickerLabelDefault,
      value: effectiveValue,
      enabled: filtered.isNotEmpty,
      items: [
        for (final a in filtered)
          DropdownMenuItem(
            value: a.id,
            child: Text(
              '${a.name} · ${a.currency}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: filtered.isEmpty ? null : onChanged,
      validator: (v) =>
          (v == null || v.isEmpty) ? l10n.formAccountPickerRequired : null,
    );
  }
}
