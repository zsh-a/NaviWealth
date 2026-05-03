import 'package:flutter/material.dart';

import '../../../data/domain/account.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'expense_category_visuals.dart';

/// Tap-grid expense account picker. Each tile shows the icon, name,
/// and a faint accent badge so the user can scan visually.
class CategoryGridPicker extends StatelessWidget {
  const CategoryGridPicker({
    super.key,
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
    this.label,
  });

  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
          child: Text(
            label ?? l10n.expenseCategoryPickerLabelDefault,
            style: theme.textTheme.labelLarge,
          ),
        ),
        FormField<String>(
          initialValue: selectedId,
          validator: (v) =>
              (v == null || v.isEmpty) ? l10n.expenseCategoryPickerRequired : null,
          builder: (state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const tileWidth = 84.0;
                    final crossAxisCount = (constraints.maxWidth / tileWidth)
                        .floor()
                        .clamp(3, 6);
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: Spacing.s8,
                      crossAxisSpacing: Spacing.s8,
                      childAspectRatio: 0.85,
                      children: [
                        for (final account in accounts)
                          _AccountTile(
                            account: account,
                            selected: account.id == state.value,
                            onTap: () {
                              state.didChange(account.id);
                              onSelect(account.id);
                            },
                          ),
                      ],
                    );
                  },
                ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s8, left: 4),
                    child: Text(
                      state.errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = account.accentColor ?? theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: 0.15),
              child: Icon(account.iconData, color: accent, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              account.name,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
