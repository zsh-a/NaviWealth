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
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (final (type, label) in entries)
          FButton(
            key: Key('corp-action-type-${type.name}'),
            variant: (selected == type)
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () => onChanged(type),
            child: Text(label),
          ),
      ],
    );
  }
}
