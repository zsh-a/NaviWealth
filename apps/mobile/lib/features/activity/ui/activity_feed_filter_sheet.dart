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
    return showFSheet<void>(
      side: FLayout.btt,
      context: context,
      mainAxisMaxRatio: null,
      builder: (_) => const ActivityFeedFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final controller = ref.read(activityFeedQueryProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.activityFeedFilterTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: controller.clearFilters,
                  child: Text(l10n.activityFeedFilterClear),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SectionHeader(title: l10n.activityFeedFilterKind),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in ActivityKind.values)
                  FButton(
                    variant: query.kinds.contains(kind)
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    onPress: () {
                      final wasSelected = query.kinds.contains(kind);
                      controller.mutateQuery((q) {
                        final kinds = {...q.kinds};
                        wasSelected ? kinds.remove(kind) : kinds.add(kind);
                        return q.copyWith(kinds: kinds);
                      });
                    },
                    child: Text(_kindLabel(l10n, kind)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SectionHeader(title: l10n.activityFeedFilterAccount),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final account in accounts)
                    FTile(
                      title: Text(account.name),
                      suffix: FCheckbox(
                        value: query.accountIds.contains(account.id),
                        onChange: (selected) {
                          controller.mutateQuery((q) {
                            final ids = {...q.accountIds};
                            selected
                                ? ids.add(account.id)
                                : ids.remove(account.id);
                            return q.copyWith(accountIds: ids);
                          });
                        },
                      ),
                      onPress: () {
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
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(l10n.activityFeedFilterThisMonth),
                    onPressed: () {
                      final now = DateTime.now();
                      final start = DateTime(now.year, now.month);
                      final end = DateTime(now.year, now.month + 1);
                      controller.mutateQuery(
                        (q) => q.copyWith(
                          dateRange: DateTimeRange(start: start, end: end),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.formSave),
                  ),
                ),
              ],
            ),
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
