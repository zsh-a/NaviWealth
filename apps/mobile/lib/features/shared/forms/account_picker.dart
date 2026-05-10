import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Drop-down picker over the user's existing accounts, built on [FSelect].
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
  final String? label;
  final Set<AccountType>? allowedTypes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = allowedTypes == null
        ? accounts
        : accounts.where((a) => allowedTypes!.contains(a.type)).toList();
    final effectiveValue = filtered.any((a) => a.id == value) ? value : null;
    final items = <String, String>{
      for (final a in filtered) '${a.name} · ${a.currency}': a.id,
    };
    return FSelect<String>(
      items: items,
      control: FSelectControl<String>.managed(
        initial: effectiveValue,
        onChange: onChanged,
      ),
      label: Text(label ?? l10n.formAccountPickerLabelDefault),
      enabled: filtered.isNotEmpty,
      validator: (v) =>
          (v == null || v.isEmpty) ? l10n.formAccountPickerRequired : null,
    );
  }
}
