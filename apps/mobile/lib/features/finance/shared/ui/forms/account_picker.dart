import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../../design_system/design_system.dart';
import '../../../../../l10n/gen/app_localizations.dart';
import '../../l10n/account_l10n.dart';

/// Drop-down picker over the user's existing accounts, built on [FSelect].
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    super.key,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.label,
    this.allowedTypes,
    this.enabled = true,
    this.required = true,
    this.contentConstraints = const FAutoWidthPortalConstraints(maxHeight: 300),
  });

  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final Set<AccountCategory>? allowedTypes;
  final bool enabled;
  final bool required;
  final FPortalConstraints contentConstraints;

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
    return FSelect<String>.searchBuilder(
      format: (id) => labelById[id] ?? '',
      searchFieldProperties: FSelectSearchFieldProperties(
        hint: l10n.formAccountPickerSearch,
      ),
      filter: (query) {
        final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
        return filtered
            .where((account) {
              final label = labelById[account.id]!.toLowerCase();
              return terms.every(label.contains);
            })
            .map((account) => account.id);
      },
      contentEmptyBuilder: (context, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Text(l10n.formAccountPickerNoResults),
      ),
      control: FSelectControl<String>.lifted(
        value: effectiveValue,
        onChange: onChanged,
      ),
      label: RequiredLabel(
        label ?? l10n.formAccountPickerLabelDefault,
        required: required,
      ),
      enabled: enabled && filtered.isNotEmpty,
      contentConstraints: contentConstraints,
      validator: (v) => required && (v == null || v.isEmpty)
          ? l10n.formAccountPickerRequired
          : null,
      contentBuilder: (context, _, ids) => [
        for (final id in ids)
          FSelectItem<String>(value: id, title: Text(labelById[id]!)),
      ],
    );
  }
}
