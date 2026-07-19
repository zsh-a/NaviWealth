import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/recurring_transaction_providers.dart';
import '../data/recurring_transaction_repository.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';
import 'recurring_transaction_form.dart';

/// Manage recurring income / expense rules. The data layer (repository,
/// recurrence engine, materialisation) already exists; this is the
/// missing UI for it. Reachable from the cash-flow page header and the
/// command palette.
enum _RecurringFilter { active, paused }

class RecurringTransactionsPage extends ConsumerStatefulWidget {
  const RecurringTransactionsPage({super.key});

  @override
  ConsumerState<RecurringTransactionsPage> createState() =>
      _RecurringTransactionsPageState();
}

class _RecurringTransactionsPageState
    extends ConsumerState<RecurringTransactionsPage> {
  _RecurringFilter _filter = _RecurringFilter.active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rulesAsync = ref.watch(recurringTransactionsProvider);
    return AppPageScaffold(
      title: l10n.recurringListTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.recurringEmptyCta,
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
          error: (error, stackTrace) => AppEmptyState.error(
            title: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load recurring transactions',
            ),
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(recurringTransactionsProvider),
          ),
          data: (rules) {
            final visible = rules
                .where(
                  (rule) => switch (_filter) {
                    _RecurringFilter.active => rule.enabled,
                    _RecurringFilter.paused => !rule.enabled,
                  },
                )
                .toList(growable: false);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s12,
                    AppSpacing.s16,
                    AppSpacing.s4,
                  ),
                  child: SegmentedRow<_RecurringFilter>(
                    options: _RecurringFilter.values,
                    value: _filter,
                    minSegmentWidth: 80,
                    labelOf: (filter) => switch (filter) {
                      _RecurringFilter.active => l10n.recurringFilterActive,
                      _RecurringFilter.paused => l10n.recurringFilterPaused,
                    },
                    onChanged: (filter) => setState(() => _filter = filter),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? AppEmptyState(
                          icon: FLucideIcons.calendarClock,
                          iconSize: 56,
                          title: _filter == _RecurringFilter.active
                              ? l10n.recurringEmptyTitle
                              : l10n.recurringPausedEmptyTitle,
                          message: _filter == _RecurringFilter.active
                              ? l10n.recurringEmptyBody
                              : l10n.recurringPausedEmptyBody,
                          action: _filter == _RecurringFilter.active
                              ? FButton(
                                  onPress: () => showRecurringTransactionForm(
                                    context,
                                    ref,
                                  ),
                                  child: Text(l10n.recurringEmptyCta),
                                )
                              : null,
                        )
                      : _RecurringList(rules: visible),
                ),
              ],
            );
          },
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
    final completed = _isCompleted(rule);

    String title;
    Decimal? signedAmount;
    String amountUnit = '';
    try {
      final template = JournalBuildTemplateCodec.decode(
        rule.templateJournalBuildJson,
      );
      final cash = template.postings.isNotEmpty
          ? template.postings.first
          : null;
      title = template.entry.narration.trim().isEmpty
          ? l10n.recurringDefaultNarration
          : template.entry.narration;
      signedAmount = cash?.units;
      amountUnit = cash?.unit ?? '';
    } catch (_) {
      title = l10n.recurringTemplateCorrupt;
    }

    return SoftCard.raised(
      onPress: () => showRecurringTransactionForm(context, ref, existing: rule),
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: context.labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!rule.enabled) ...[
                      const SizedBox(width: AppSpacing.s8),
                      AppBadge(
                        label: completed
                            ? l10n.recurringCompletedBadge
                            : l10n.recurringPausedBadge,
                        size: AppBadgeSize.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  [
                    _describeRecurrence(l10n, rule.rrule),
                    if (rule.enabled)
                      l10n.recurringNextDue(formatters.date(rule.nextDueAt)),
                  ].join(' · '),
                  style: context.captionStyle.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          if (signedAmount != null)
            SignedMoneyText(
              amount: signedAmount,
              unit: amountUnit,
              formatters: formatters,
              style: context.strongLabelStyle,
            ),
          const SizedBox(width: AppSpacing.s8),
          AppAdaptiveActionMenu(
            title: l10n.recurringRowActionsTitle,
            actions: <AppAdaptiveAction>[
              AppAdaptiveAction(
                icon: FLucideIcons.pencil,
                title: l10n.recurringActionEdit,
                subtitle: l10n.recurringActionEditHint,
                onPress: () {
                  if (context.mounted) {
                    return showRecurringTransactionForm(
                      context,
                      ref,
                      existing: rule,
                    );
                  }
                },
              ),
              if (rule.enabled)
                AppAdaptiveAction(
                  icon: FLucideIcons.circlePause,
                  title: l10n.recurringActionDisable,
                  subtitle: l10n.recurringActionDisableHint,
                  onPress: () {
                    if (context.mounted) {
                      return _disableRule(context, ref, rule);
                    }
                  },
                )
              else if (!completed)
                AppAdaptiveAction(
                  icon: FLucideIcons.play,
                  title: l10n.recurringActionEnable,
                  subtitle: l10n.recurringActionEnableHint,
                  onPress: () {
                    if (context.mounted) {
                      return _enableRule(context, ref, rule);
                    }
                  },
                ),
              AppAdaptiveAction(
                icon: FLucideIcons.trash2,
                title: l10n.commonDelete,
                subtitle: l10n.recurringActionDeleteHint,
                destructive: true,
                onPress: () {
                  if (context.mounted) return _deleteRule(context, ref, rule);
                },
              ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => Focus(
              focusNode: focusNode,
              child: Semantics(
                button: true,
                label: l10n.recurringRowActionsTitle,
                child: FTappable(
                  onPress: openMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s8),
                    child: Icon(
                      FLucideIcons.ellipsisVertical,
                      size: AppIconSizes.md,
                      color: muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _disableRule(
  BuildContext context,
  WidgetRef ref,
  RecurringTransaction rule,
) async {
  final l10n = AppLocalizations.of(context);
  final feedbackContext = Navigator.of(context).context;
  try {
    final repo = await ref.read(recurringTransactionRepositoryProvider.future);
    await repo.update(rule.id, enabled: false);
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.recurringDisabled,
        duration: const Duration(seconds: 6),
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(
          _restoreRuleEnabled(
            feedbackContext,
            repo,
            rule.id,
            l10n,
            enabled: true,
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.recurringActionFailed);
    }
  }
}

Future<void> _restoreRuleEnabled(
  BuildContext context,
  RecurringTransactionRepository repo,
  String id,
  AppLocalizations l10n, {
  required bool enabled,
}) async {
  try {
    await repo.update(id, enabled: enabled);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.commonUndoSucceeded);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonUndoFailed);
    }
  }
}

Future<void> _enableRule(
  BuildContext context,
  WidgetRef ref,
  RecurringTransaction rule,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(recurringTransactionRepositoryProvider.future);
    const engine = RecurrenceEngine();
    final recurrence = engine.parse(rule.rrule);
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final nextDueAt = engine.advanceToOnOrAfter(
      recurrence,
      rule.nextDueAt,
      today,
    );
    await repo.update(rule.id, enabled: true, nextDueAt: nextDueAt);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.recurringEnabled);
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
  final feedbackContext = Navigator.of(context).context;
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
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.recurringDeleted,
        duration: const Duration(seconds: 6),
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(
          _restoreDeletedRule(feedbackContext, repo, rule.id, l10n),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.recurringActionFailed);
    }
  }
}

Future<void> _restoreDeletedRule(
  BuildContext context,
  RecurringTransactionRepository repo,
  String id,
  AppLocalizations l10n,
) async {
  try {
    await repo.restore(id);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.commonUndoSucceeded);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonUndoFailed);
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

bool _isCompleted(RecurringTransaction rule) {
  try {
    final until = const RecurrenceEngine().parse(rule.rrule).until;
    if (until == null) return false;
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return rule.nextDueAt.isAfter(until) || until.isBefore(today);
  } catch (_) {
    return false;
  }
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
