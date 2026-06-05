import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/recurring_transaction_providers.dart';
import '../data/recurring_transaction_repository.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';
import 'recurring_transaction_form.dart';

/// Manage recurring income / expense rules. The data layer (repository,
/// recurrence engine, materialisation) already exists; this is the
/// missing UI for it. Reachable from the cash-flow page header and the
/// command palette.
class RecurringTransactionsPage extends ConsumerWidget {
  const RecurringTransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rulesAsync = ref.watch(recurringTransactionsProvider);
    return AppPageScaffold(
      title: l10n.recurringListTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          onPress: () => showRecurringTransactionForm(context, ref),
        ),
      ],
      childPad: false,
      child: PageSkeletonShell<List<RecurringTransaction>>(
        skeleton: const _RecurringSkeleton(),
        isLoading: rulesAsync.isLoading,
        child: rulesAsync.when(
          loading: () => const _RecurringSkeleton(),
          error: (error, _) => AppEmptyState.error(
            title: l10n.recurringLoadError('$error'),
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () => ref.invalidate(recurringTransactionsProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (rules) => rules.isEmpty
              ? AppEmptyState(
                  icon: FLucideIcons.calendarClock,
                  iconSize: 56,
                  title: l10n.recurringEmptyTitle,
                  message: l10n.recurringEmptyBody,
                  action: FButton(
                    onPress: () => showRecurringTransactionForm(context, ref),
                    child: Text(l10n.recurringEmptyCta),
                  ),
                )
              : _RecurringList(rules: rules),
        ),
      ),
    );
  }
}

class _RecurringList extends ConsumerWidget {
  const _RecurringList({required this.rules});

  final List<RecurringTransaction> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.page,
        padding: EdgeInsets.zero,
        primary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i != 0) const SizedBox(height: AppSpacing.s12),
              _RecurringRow(rule: rules[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecurringRow extends ConsumerWidget {
  const _RecurringRow({required this.rule});

  final RecurringTransaction rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final muted = context.theme.colors.mutedForeground;

    String amountLabel;
    try {
      final template = JournalBuildTemplateCodec.decode(
        rule.templateJournalBuildJson,
      );
      final cash = template.postings.isNotEmpty
          ? template.postings.first
          : null;
      amountLabel = cash == null
          ? l10n.recurringTemplateCorrupt
          : formatters.currency(cash.units.abs(), code: cash.unit);
    } catch (_) {
      amountLabel = l10n.recurringTemplateCorrupt;
    }

    return SoftCard(
      onPress: () => showRecurringTransactionForm(context, ref, existing: rule),
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _describeRecurrence(l10n, rule.rrule),
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.recurringNextDue(formatters.date(rule.nextDueAt)),
                  style: context.theme.typography.xs.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            amountLabel,
            style: context.theme.typography.sm.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FTappable(
            onPress: () => _showRowActions(context, ref, rule),
            child: Icon(
              FLucideIcons.ellipsisVertical,
              size: AppIconSizes.md,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRowActions(
  BuildContext context,
  WidgetRef ref,
  RecurringTransaction rule,
) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.recurringRowActionsTitle,
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: FLucideIcons.pencil,
          title: l10n.recurringActionEdit,
          subtitle: l10n.recurringActionEditHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            showRecurringTransactionForm(context, ref, existing: rule);
          },
        ),
        AppActionSheetTile(
          icon: FLucideIcons.circlePause,
          title: l10n.recurringActionDisable,
          subtitle: l10n.recurringActionDisableHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            _disableRule(context, ref, rule);
          },
        ),
        AppActionSheetTile(
          icon: FLucideIcons.trash2,
          title: l10n.commonDelete,
          subtitle: l10n.recurringActionDeleteHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            _deleteRule(context, ref, rule);
          },
        ),
      ],
    ),
  );
}

Future<void> _disableRule(
  BuildContext context,
  WidgetRef ref,
  RecurringTransaction rule,
) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showConfirmDialog(
    context: context,
    title: Text(l10n.recurringDisableTitle),
    body: Text(l10n.recurringDisableBody),
    confirmLabel: l10n.recurringActionDisable,
    cancelLabel: l10n.commonCancel,
  );
  if (ok != true) return;
  try {
    final repo = await ref.read(recurringTransactionRepositoryProvider.future);
    await repo.update(rule.id, enabled: false);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.recurringDisabled);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.recurringActionFailed);
    }
  }
}

Future<void> _deleteRule(
  BuildContext context,
  WidgetRef ref,
  RecurringTransaction rule,
) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showConfirmDialog(
    context: context,
    title: Text(l10n.recurringDeleteTitle),
    body: Text(l10n.recurringDeleteBody),
    confirmLabel: l10n.commonDelete,
    cancelLabel: l10n.commonCancel,
    destructive: true,
  );
  if (ok != true) return;
  try {
    final repo = await ref.read(recurringTransactionRepositoryProvider.future);
    await repo.softDelete(rule.id);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.recurringDeleted);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.recurringActionFailed);
    }
  }
}

String _describeRecurrence(AppLocalizations l10n, String rrule) {
  final RecurrenceRule rule;
  try {
    rule = const RecurrenceEngine().parse(rrule);
  } catch (_) {
    return rrule;
  }
  final base = switch (rule.frequency) {
    RecurrenceFrequency.daily => l10n.recurringEveryDay(rule.interval),
    RecurrenceFrequency.weekly => l10n.recurringEveryWeek(rule.interval),
    RecurrenceFrequency.monthly => l10n.recurringEveryMonth(rule.interval),
    RecurrenceFrequency.yearly => l10n.recurringEveryYear(rule.interval),
  };
  final parts = <String>[base];
  if (rule.byMonthDay != null) {
    parts.add(l10n.recurringByMonthDay(rule.byMonthDay!));
  }
  final until = rule.until;
  if (until != null) {
    final y = until.year.toString().padLeft(4, '0');
    final m = until.month.toString().padLeft(2, '0');
    final d = until.day.toString().padLeft(2, '0');
    parts.add(l10n.recurringUntil('$y-$m-$d'));
  }
  return parts.join(' · ');
}

class _RecurringSkeleton extends StatelessWidget {
  const _RecurringSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s12),
          const SkeletonCard(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 14, radius: 4),
                      SizedBox(height: AppSpacing.s6),
                      SkeletonBox(width: 100, height: 12, radius: 4),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.s12),
                SkeletonBox(width: 72, height: 16, radius: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
