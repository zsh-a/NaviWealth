import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/account.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'expense_category_visuals.dart';

/// Tap-grid expense category picker. Each tile shows the category
/// icon + name, anchored to the category's user-defined accent color.
///
/// Visual rules align with the rest of the app:
///   - container: 14% accent fill when selected, 4% foreground tint
///     otherwise (matches SoftCard's resting tint)
///   - selection: thin teal/accent border + bolder label, no heavy
///     1.5px outline
///   - icon disc: 36×36 rounded square (not a circle) so the
///     vocabulary matches AccountCategoryPicker / Accounts hub rows
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
          child: Text(
            (label ?? l10n.expenseCategoryPickerLabelDefault).toUpperCase(),
            style: context.theme.typography.xs2.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        FormField<String>(
          initialValue: selectedId,
          validator: (v) => (v == null || v.isEmpty)
              ? l10n.expenseCategoryPickerRequired
              : null,
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
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
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
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      state.errorText!,
                      style: context.theme.typography.xs.copyWith(
                        color: context.theme.colors.destructive,
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
    final colors = context.theme.colors;
    final accent = account.accentColor ?? colors.primary;
    final fill = selected
        ? accent.withValues(alpha: 0.10)
        : colors.foreground.withValues(alpha: 0.04);
    final border = selected
        ? accent.withValues(alpha: 0.65)
        : colors.foreground.withValues(alpha: 0.06);
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: selected ? 1.2 : 1),
      ),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(account.iconData, color: accent, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                account.name,
                style: context.theme.typography.xs.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? accent : colors.foreground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
