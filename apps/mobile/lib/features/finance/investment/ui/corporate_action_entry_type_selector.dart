part of 'corporate_action_entry_page.dart';

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onChanged,
    required this.l10n,
  });

  final CorporateActionType selected;
  final ValueChanged<CorporateActionType?> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final entries = <(CorporateActionType, String)>[
      (CorporateActionType.cashDividend, l10n.corpActionTypeCashDividend),
      (CorporateActionType.stockDividend, l10n.corpActionTypeStockDividend),
      (CorporateActionType.split, l10n.corpActionTypeSplit),
      (CorporateActionType.rightsIssue, l10n.corpActionTypeRightsIssue),
      (CorporateActionType.drip, l10n.corpActionTypeDrip),
    ];
    return AppAdaptiveChoice<CorporateActionType>(
      key: const Key('corp-action-type'),
      title: l10n.corpActionEventTypeTitle,
      options: [for (final (type, _) in entries) type],
      value: selected,
      labelOf: (type) => entries.firstWhere((entry) => entry.$1 == type).$2,
      onChanged: onChanged,
    );
  }
}
