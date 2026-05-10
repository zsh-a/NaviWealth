import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/account.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/activity_feed_provider.dart';
import '../data/activity_feed_query.dart';

class ActivityFeedFilterSheet extends ConsumerWidget {
  const ActivityFeedFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showAppSheet<void>(
      context: context,
      title: l10n.activityFeedFilterTitle,
      builder: (_) => const ActivityFeedFilterSheet(),
      actions: [
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () {
              ProviderScope.containerOf(ctx)
                  .read(activityFeedQueryProvider.notifier)
                  .clearFilters();
            },
            child: Text(l10n.activityFeedFilterClear),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final controller = ref.read(activityFeedQueryProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetSectionLabel(text: l10n.activityFeedFilterKind),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in ActivityKind.values)
              _PillChip(
                label: _kindLabel(l10n, kind),
                selected: query.kinds.contains(kind),
                onTap: () {
                  final wasSelected = query.kinds.contains(kind);
                  controller.mutateQuery((q) {
                    final kinds = {...q.kinds};
                    wasSelected ? kinds.remove(kind) : kinds.add(kind);
                    return q.copyWith(kinds: kinds);
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SheetSectionLabel(text: l10n.activityFeedFilterAccount),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final account in accounts)
                _AccountFilterRow(
                  account: account,
                  selected: query.accountIds.contains(account.id),
                  onToggle: () {
                    controller.mutateQuery((q) {
                      final ids = {...q.accountIds};
                      ids.contains(account.id)
                          ? ids.remove(account.id)
                          : ids.add(account.id);
                      return q.copyWith(accountIds: ids);
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month);
                  final end = DateTime(now.year, now.month + 1);
                  controller.mutateQuery(
                    (q) => q.copyWith(
                      dateRange: DateTimeRange(start: start, end: end),
                    ),
                  );
                },
                child: Text(l10n.activityFeedFilterThisMonth),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FButton(
                onPress: () => Navigator.of(context).pop(),
                child: Text(l10n.formSave),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Inline section eyebrow used inside [AppSheet] bodies. Same look as
/// the inset-grouped headers on the Settings page so the sheet reads
/// like a tightly-scoped settings micro-page rather than a separate
/// component family.
class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: context.theme.typography.xs2.copyWith(
          color: context.theme.colors.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
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
    final fg = selected ? colors.primaryForeground : colors.foreground;
    final bg = selected
        ? colors.primary
        : colors.foreground.withValues(alpha: 0.04);
    return FTappable(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AccountFilterRow extends StatelessWidget {
  const _AccountFilterRow({
    required this.account,
    required this.selected,
    required this.onToggle,
  });

  final Account account;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                account.name,
                style: context.theme.typography.sm,
              ),
            ),
            FCheckbox(value: selected, onChange: (_) => onToggle()),
          ],
        ),
      ),
    );
  }
}

String _kindLabel(AppLocalizations l10n, ActivityKind kind) {
  return switch (kind) {
    ActivityKind.expense => l10n.entryKindExpense,
    ActivityKind.transfer => l10n.entryKindTransfer,
    ActivityKind.trade => l10n.entryKindTrade,
    ActivityKind.income => l10n.entryKindIncome,
    ActivityKind.payment => l10n.entryKindPayment,
    ActivityKind.adjustment => l10n.entryKindAdjustment,
    ActivityKind.opening => l10n.entryKindOpening,
    ActivityKind.other => l10n.entryKindEntry,
  };
}
