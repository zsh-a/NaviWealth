import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../account_l10n.dart';

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
  final Set<AccountCategory>? allowedTypes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = allowedTypes == null
        ? accounts
        : accounts.where((a) => allowedTypes!.contains(a.type)).toList();
    final effectiveValue = filtered.any((a) => a.id == value) ? value : null;
    final labelById = <String, String>{
      for (final a in filtered)
        a.id: '${localizedAccountName(l10n, a)} · ${a.currency}',
    };
    return FSelect<String>.rich(
      format: (id) => labelById[id] ?? '',
      control: FSelectControl<String>.lifted(
        value: effectiveValue,
        onChange: onChanged,
      ),
      label: RequiredLabel(label ?? l10n.formAccountPickerLabelDefault),
      enabled: filtered.isNotEmpty,
      validator: (v) =>
          (v == null || v.isEmpty) ? l10n.formAccountPickerRequired : null,
      children: [
        for (final account in filtered)
          FSelectItem<String>(
            value: account.id,
            title: Text(
              labelById[account.id]!,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
