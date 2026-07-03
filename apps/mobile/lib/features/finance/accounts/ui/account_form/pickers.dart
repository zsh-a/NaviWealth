part of '../account_form_page.dart';

/// Parent picker + clear button. Filters the candidate list to
/// same-category accounts and excludes the current account plus its
/// descendants so the tree can never form a cycle.
class _ParentAccountPickerSection extends ConsumerWidget {
  const _ParentAccountPickerSection({
    required this.currentAccountId,
    required this.category,
    required this.parentId,
    required this.onChanged,
  });

  /// `null` in the create flow.
  final String? currentAccountId;
  final AccountSide category;
  final String? parentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? const <Account>[];
    final filtered = _candidates(accounts);

    return Row(
      children: [
        Expanded(
          child: AccountTreePicker(
            accounts: filtered,
            value: parentId,
            onChanged: onChanged,
            category: category,
            label: l10n.accountFormParentLabel,
            helperText: l10n.accountFormParentHelper,
            allowSystemAccounts: false,
          ),
        ),
        if (parentId != null)
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountFormMakeTopLevelTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: () => onChanged(null),
              child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
            ),
          ),
      ],
    );
  }

  /// Same-category accounts minus self minus self's descendants.
  List<Account> _candidates(List<Account> all) {
    final selfId = currentAccountId;
    if (selfId == null) {
      return all.where((a) => a.category == category).toList();
    }
    final descendants = _descendantIds(selfId, all);
    return all
        .where(
          (a) =>
              a.id != selfId &&
              !descendants.contains(a.id) &&
              a.category == category,
        )
        .toList();
  }

  Set<String> _descendantIds(String rootId, List<Account> all) {
    final byParent = <String, List<Account>>{};
    for (final a in all) {
      final pid = a.parentId;
      if (pid == null) continue;
      byParent.putIfAbsent(pid, () => []).add(a);
    }
    final out = <String>{};
    final stack = <String>[rootId];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final child in byParent[cur] ?? const <Account>[]) {
        if (out.add(child.id)) stack.add(child.id);
      }
    }
    return out;
  }
}

/// Horizontal grid of icon options keyed off [kAccountIconCatalogue].
/// Selecting an icon snaps the form's `_icon`; the leading "None"
/// tile clears it.
class _IconPickerSection extends StatelessWidget {
  const _IconPickerSection({
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final String? selected;
  final String? color;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tint = parseAccountColor(color) ?? context.theme.colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.accountFormIconHeading,
          style: context.theme.typography.body.xs,
        ),
        const SizedBox(height: AppSpacing.s4),
        SizedBox(
          height: AppSpacing.s56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kAccountIconCatalogue.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s8),
            itemBuilder: (context, index) {
              if (index == 0) {
                final isSelected = selected == null;
                return _IconChip(
                  isSelected: isSelected,
                  selectionTint: tint,
                  onTap: () => onChanged(null),
                  tooltip: l10n.accountFormNoIconTooltip,
                  child: Icon(
                    FLucideIcons.ban,
                    color: context.theme.colors.mutedForeground,
                  ),
                );
              }
              final entry = kAccountIconCatalogue[index - 1];
              final isSelected = selected == entry.name;
              return _IconChip(
                isSelected: isSelected,
                selectionTint: tint,
                onTap: () => onChanged(entry.name),
                tooltip: entry.name,
                child: Icon(
                  entry.icon,
                  color: isSelected ? tint : context.theme.colors.foreground,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.isSelected,
    required this.selectionTint,
    required this.onTap,
    required this.child,
    required this.tooltip,
  });

  final bool isSelected;
  final Color selectionTint;
  final VoidCallback onTap;
  final Widget child;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FTappable(
        onPress: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            color: isSelected
                ? selectionTint.withValues(alpha: AppOpacity.subtle)
                : colors.muted,
            border: Border.all(
              color: isSelected ? selectionTint : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Horizontal palette of preset hex colours from
/// [kAccountColorPalette]. Tapping a swatch snaps `_color`; the
/// leading "None" tile clears it.
class _ColorPickerSection extends StatelessWidget {
  const _ColorPickerSection({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.accountFormColorHeading,
          style: context.theme.typography.body.xs,
        ),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            _ColorSwatch(
              isSelected: selected == null,
              onTap: () => onChanged(null),
              tooltip: l10n.accountFormNoColorTooltip,
              fill: context.theme.colors.muted,
              border: context.theme.colors.border,
              child: Icon(
                FLucideIcons.ban,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
            ),
            for (final hex in kAccountColorPalette)
              _ColorSwatch(
                isSelected: selected == hex,
                onTap: () => onChanged(hex),
                fill: parseAccountColor(hex) ?? context.theme.colors.secondary,
                tooltip: hex,
                border: selected == hex
                    ? context.theme.colors.primary
                    : context.theme.colors.border,
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.isSelected,
    required this.onTap,
    required this.fill,
    required this.border,
    required this.tooltip,
    this.child,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Color fill;
  final Color border;
  final String tooltip;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: FTappable(
        onPress: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: border, width: isSelected ? 3 : 1),
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}
