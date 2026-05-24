import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/data/dashboard_providers.dart';
import '../../home/domain/dashboard_models.dart';
import '../../shared/forms/forms.dart';
import '../data/fire_bucket_rules_preferences.dart';
import '../domain/fire_bucket.dart';

/// Per-asset bucket mapping editor.
///
/// Lists every asset surfaced by the dashboard snapshot and lets the
/// user pin a [FireBucketRole] for each. Leaving a row at "Default"
/// removes any existing rule and falls back to the allocator's
/// category-based default.
Future<void> showFireBucketMappingSheet(BuildContext context) {
  return showGuardedFormSheet<void>(
    context: context,
    builder: (_, dirty) => _MappingSheet(dirty: dirty),
  );
}

class _MappingSheet extends ConsumerStatefulWidget {
  const _MappingSheet({required this.dirty});
  final FormDirtyController dirty;

  @override
  ConsumerState<_MappingSheet> createState() => _MappingSheetState();
}

class _MappingSheetState extends ConsumerState<_MappingSheet> {
  /// `null` value = "Default" (no rule). Non-null = the chosen role.
  final Map<String, FireBucketRole?> _selection = <String, FireBucketRole?>{};
  bool _saving = false;
  bool _seeded = false;

  void _seed(List<FireBucketRule> rules, List<CategoryItem> items) {
    if (_seeded) return;
    _seeded = true;
    final ruleByItem = {
      for (final r in rules)
        if (r.targetTable == 'assets') r.targetId: r.role,
    };
    for (final item in items) {
      _selection[item.id] = ruleByItem[item.id];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    final rules = ref.watch(fireBucketRulesProvider);

    return AppSheet(
      title: l10n.fireOsBucketsMappingTitle,
      subtitle: l10n.fireOsBucketsMappingSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.fireOsBucketsMappingSave,
        cancelLabel: l10n.fireOsBucketsMappingCancel,
        onSubmit: _submit,
        busy: _saving,
      ),
      child: snapshotAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox.shrink(),
        ),
        error: (e, _) =>
            Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
        data: (snapshot) {
          final items = _flattenItems(snapshot);
          _seed(rules, items);
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.fireOsBucketsMappingEmpty),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final selected = _selection[item.id];
              return _MappingRow(
                item: item,
                value: selected,
                onChanged: (role) => setState(() {
                  _selection[item.id] = role;
                  widget.dirty.markDirty();
                }),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final newRules = <FireBucketRule>[];
      _selection.forEach((id, role) {
        if (role == null) return;
        newRules.add(
          FireBucketRule(
            id: id,
            role: role,
            targetTable: 'assets',
            targetId: id,
          ),
        );
      });
      await ref.read(fireBucketRulesProvider.notifier).save(newRules);
      if (!mounted) return;
      widget.dirty.markPristine();
      Haptics.success();
      Navigator.of(context).pop();
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  List<CategoryItem> _flattenItems(DashboardSnapshot s) {
    final items = <CategoryItem>[];
    for (final allocation in s.allocations) {
      if (allocation.category == AssetCategory.liability) continue;
      items.addAll(allocation.items);
    }
    return items;
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final CategoryItem item;
  final FireBucketRole? value;
  final ValueChanged<FireBucketRole?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.theme.colors.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: context.theme.typography.sm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RolePill(
                label: l10n.fireOsBucketsMappingDefault,
                selected: value == null,
                onTap: () => onChanged(null),
              ),
              for (final role in FireBucketRole.values)
                _RolePill(
                  label: _roleLabel(l10n, role),
                  selected: value == role,
                  onTap: () => onChanged(role),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _roleLabel(AppLocalizations l10n, FireBucketRole role) {
    switch (role) {
      case FireBucketRole.cash:
        return l10n.fireOsBucketRoleCash;
      case FireBucketRole.defensive:
        return l10n.fireOsBucketRoleDefensive;
      case FireBucketRole.growth:
        return l10n.fireOsBucketRoleGrowth;
      case FireBucketRole.riskReserve:
        return l10n.fireOsBucketRoleRiskReserve;
      case FireBucketRole.dream:
        return l10n.fireOsBucketRoleDream;
    }
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final bg = selected ? colors.primary : Colors.transparent;
    final fg = selected ? colors.primaryForeground : colors.foreground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(color: fg),
        ),
      ),
    );
  }
}
