import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../data/financial_inbox_providers.dart';
import '../domain/financial_inbox.dart';

class FinancialInboxPage extends ConsumerWidget {
  const FinancialInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(financialInboxScanProvider);
    return AppPageScaffold(
      title: l10n.financialInboxTitle,
      childPad: false,
      child: items.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(
            context,
            error,
            operation: 'load financial inbox',
          ),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(financialInboxScanProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return AppEmptyState(
              icon: FLucideIcons.circleCheckBig,
              title: l10n.financialInboxEmptyTitle,
              message: l10n.financialInboxEmptyBody,
            );
          }
          final important = rows
              .where(
                (item) => item.priority == FinancialInboxPriority.important,
              )
              .toList(growable: false);
          final attention = rows
              .where(
                (item) => item.priority == FinancialInboxPriority.attention,
              )
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              if (important.isNotEmpty)
                _InboxGroup(
                  label: l10n.financialInboxPriorityImportant,
                  items: important,
                ),
              if (important.isNotEmpty && attention.isNotEmpty)
                const SizedBox(height: AppPageRhythm.section),
              if (attention.isNotEmpty)
                _InboxGroup(
                  label: l10n.financialInboxPriorityAttention,
                  items: attention,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InboxGroup extends StatelessWidget {
  const _InboxGroup({required this.label, required this.items});

  final String label;
  final List<FinancialInboxItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s4,
            bottom: AppSpacing.s8,
          ),
          child: Text(label, style: context.mutedLabelStyle),
        ),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _InboxRow(item: items[index]),
                if (index < items.length - 1)
                  const AppGroupedDivider(indent: AppSpacing.s48),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({required this.item});

  final FinancialInboxItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, body) = switch (item.kind) {
      FinancialInboxKind.importReview => (
        FLucideIcons.fileCheck,
        l10n.financialInboxImportTitle(item.count),
        l10n.financialInboxImportBody,
      ),
      FinancialInboxKind.runwayRisk => (
        FLucideIcons.calendarClock,
        l10n.financialInboxRunwayTitle,
        l10n.financialInboxRunwayBody,
      ),
      FinancialInboxKind.missingExchangeRate => (
        FLucideIcons.badgeDollarSign,
        l10n.financialInboxFxTitle(item.count),
        l10n.financialInboxFxBody,
      ),
      FinancialInboxKind.balanceMismatch => (
        FLucideIcons.scale,
        l10n.financialInboxBalanceTitle(item.count),
        l10n.financialInboxBalanceBody,
      ),
      FinancialInboxKind.expenseAnomaly => (
        FLucideIcons.chartNoAxesCombined,
        l10n.financialInboxAnomalyTitle,
        l10n.financialInboxAnomalyBody,
      ),
      FinancialInboxKind.subscriptionChange => (
        FLucideIcons.refreshCcwDot,
        l10n.financialInboxSubscriptionTitle(item.count),
        l10n.financialInboxSubscriptionBody,
      ),
      FinancialInboxKind.staleValuation => (
        FLucideIcons.clockAlert,
        l10n.financialInboxValuationTitle(item.count),
        l10n.financialInboxValuationBody,
      ),
      FinancialInboxKind.decisionReview => (
        FLucideIcons.clipboardCheck,
        l10n.financialInboxDecisionTitle,
        l10n.financialInboxDecisionBody,
      ),
      FinancialInboxKind.concentrationRisk => (
        FLucideIcons.chartPie,
        l10n.financialInboxConcentrationTitle(item.count),
        l10n.financialInboxConcentrationBody,
      ),
      FinancialInboxKind.rebalanceDrift => (
        FLucideIcons.slidersHorizontal,
        l10n.financialInboxRebalanceTitle(item.count),
        l10n.financialInboxRebalanceBody,
      ),
      FinancialInboxKind.dividendDeterioration => (
        FLucideIcons.trendingDown,
        l10n.financialInboxDividendTitle(item.count),
        l10n.financialInboxDividendBody,
      ),
    };
    final important = item.priority == FinancialInboxPriority.important;
    return SoftCard.flat(
      tinted: false,
      borderless: true,
      onPress: () => _showInboxDetail(
        context,
        item: item,
        icon: icon,
        title: title,
        body: body,
      ),
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: icon,
            color: important
                ? SemanticColors.of(context).warning
                : context.theme.colors.primary,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(body, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s8),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppBadge(
                      label: important
                          ? l10n.financialInboxPriorityImportant
                          : l10n.financialInboxPriorityAttention,
                      tone: important
                          ? AppBadgeTone.warning
                          : AppBadgeTone.info,
                      size: AppBadgeSize.compact,
                    ),
                    Text(
                      l10n.financialInboxLastCheckedCompact(
                        _dateTime(item.lastDetectedAt),
                      ),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}

Future<void> _showInboxDetail(
  BuildContext context, {
  required FinancialInboxItem item,
  required IconData icon,
  required String title,
  required String body,
}) {
  return showAppSheet<void>(
    context: context,
    title: title,
    builder: (_) =>
        _InboxDetail(item: item, icon: icon, title: title, body: body),
  );
}

class _InboxDetail extends ConsumerWidget {
  const _InboxDetail({
    required this.item,
    required this.icon,
    required this.title,
    required this.body,
  });

  final FinancialInboxItem item;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actionState = item.actionId == null
        ? const AsyncValue<LifeActionState?>.data(null)
        : ref.watch(lifeActionStateProvider(item.actionId!));
    final canCreateAction =
        item.actionId == null || actionState.value == LifeActionState.dropped;
    final anomalyExpenses = item.kind == FinancialInboxKind.expenseAnomaly
        ? _anomalyExpenses(item.evidence['expenses'])
        : const <_AnomalyExpense>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(icon: icon, color: context.theme.colors.primary),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.rowTitleStyle),
                  const SizedBox(height: AppSpacing.s4),
                  Text(body, style: context.captionStyle),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetSectionLabel(l10n.financialInboxEvidenceTitle),
        _EvidenceRow(
          label: l10n.financialInboxFirstDetected,
          value: _dateTime(item.firstDetectedAt),
        ),
        _EvidenceRow(
          label: l10n.financialInboxLastChecked,
          value: _dateTime(item.lastDetectedAt),
        ),
        for (final evidence in item.evidence.entries.where(
          (entry) => entry.key != 'expenses',
        ))
          _EvidenceRow(
            label: _evidenceLabel(l10n, evidence.key),
            value: _evidenceValue(evidence.value),
          ),
        if (anomalyExpenses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          AppSheetSectionLabel(l10n.financialInboxExpenseDetailsTitle),
          for (final expense in anomalyExpenses) ...[
            SoftCard.raised(
              borderless: true,
              onPress: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(FinanceRoutes.expense(expense.id));
              },
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.note ?? l10n.financialInboxExpenseUntitled,
                          style: context.labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(expense.date, style: context.captionStyle),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Text(
                    '${expense.currency} ${expense.amount}',
                    style: context.labelStyle,
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
        ],
        if (item.actionId != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _EvidenceRow(
            label: l10n.financialInboxLinkedAction,
            value: _actionStateLabel(l10n, actionState.value),
          ),
        ],
        if (item.revalidationStatus != null) ...[
          _EvidenceRow(
            label: l10n.financialInboxRevalidation,
            value: _revalidationLabel(l10n, item.revalidationStatus!),
          ),
          if (item.revalidatedAt != null)
            _EvidenceRow(
              label: l10n.financialInboxRevalidatedAt,
              value: _dateTime(item.revalidatedAt!),
            ),
        ],
        const SizedBox(height: AppSpacing.s20),
        FButton(
          onPress: () {
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.push(item.route);
          },
          child: Text(l10n.financialInboxFixSource),
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.secondary,
          onPress: canCreateAction
              ? () => _createAction(context, ref, l10n)
              : () {
                  final route = ref.read(lifeActionReviewRouteProvider);
                  if (route == null) return;
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push(route);
                },
          child: Text(
            canCreateAction
                ? l10n.financialInboxCreateAction
                : l10n.financialInboxViewAction,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
            AppAdaptiveAction(
              icon: FLucideIcons.clock3,
              title: l10n.financialInboxSnooze,
              onPress: () => _snooze(context, ref),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.circleCheckBig,
              title: l10n.financialInboxResolve,
              onPress: () => _resolve(context, ref),
            ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => FButton(
            variant: FButtonVariant.outline,
            focusNode: focusNode,
            onPress: openMenu,
            prefix: const Icon(FLucideIcons.ellipsis, size: AppIconSizes.sm),
            child: Text(l10n.shellMoreActions),
          ),
        ),
      ],
    );
  }

  Future<void> _createAction(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final actionId = await ref.read(lifeActionDispatcherProvider)(
      LifeActionDraft(
        title: title,
        note: jsonEncode(<String, Object?>{
          'signal_kind': item.kind.name,
          'evidence': item.evidence,
          'last_checked_at': item.lastDetectedAt.toUtc().toIso8601String(),
        }),
        sourceDomain: 'finance',
        sourceRowFamily: 'fin:financial_signals',
        sourceRowId: item.id,
        priority: item.priority == FinancialInboxPriority.important
            ? 'high'
            : 'normal',
      ),
    );
    if (actionId == null || !context.mounted) {
      if (context.mounted) {
        AppMessenger.show(
          context,
          ToastKind.warning,
          l10n.financialInboxActionUnavailable,
        );
      }
      return;
    }
    final repository = await ref.read(financialSignalRepositoryProvider.future);
    await repository.linkAction(
      item.id,
      actionId: actionId,
      now: DateTime.now(),
    );
    await ref
        .read(productMetricsProvider.notifier)
        .record(ProductFunnelEvent.executionActionCreated, success: true);
    _refresh(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final repository = await ref.read(financialSignalRepositoryProvider.future);
    await repository.resolve(item.id, now: DateTime.now());
    final remaining = await repository.listVisible(now: DateTime.now());
    if (remaining.isEmpty) {
      await ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.financialInboxCleared, success: true);
    }
    _refresh(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final repository = await ref.read(financialSignalRepositoryProvider.future);
    await repository.snooze(
      item.id,
      until: now.add(const Duration(days: 7)),
      now: now,
    );
    _refresh(ref);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: context.captionStyle)),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.labelStyle,
          ),
        ),
      ],
    ),
  );
}

void _refresh(WidgetRef ref) {
  ref.invalidate(financialInboxScanProvider);
  ref.invalidate(financialInboxProvider);
}

String _dateTime(DateTime value) =>
    value.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;

String _evidenceValue(Object? value) => switch (value) {
  null => '—',
  Iterable<Object?> values => values.map(_evidenceValue).join(', '),
  double number => number.toStringAsFixed(2),
  _ => '$value',
};

String _evidenceLabel(AppLocalizations l10n, String key) => switch (key) {
  'period' => l10n.financialInboxEvidencePeriod,
  'mismatch_count' => l10n.financialInboxEvidenceMismatchCount,
  'delta_ratio' || 'max_delta_ratio' => l10n.financialInboxEvidenceChangeRatio,
  'expense_count' => l10n.financialInboxEvidenceExpenseCount,
  'change_count' => l10n.financialInboxEvidenceChangeCount,
  'stale_count' => l10n.financialInboxEvidenceStaleCount,
  'review_date' => l10n.financialInboxEvidenceReviewDate,
  'currencies' => l10n.financialInboxEvidenceCurrencies,
  'data_completeness' => l10n.financialInboxEvidenceCompleteness,
  'dimension' => l10n.financialInboxEvidenceDimension,
  'label' => l10n.financialInboxEvidenceLabel,
  'weight' => l10n.financialInboxEvidenceWeight,
  'threshold' => l10n.financialInboxEvidenceThreshold,
  'severity' => l10n.financialInboxEvidenceSeverity,
  'breach_count' => l10n.financialInboxEvidenceBreachCount,
  'max_abs_deviation' => l10n.financialInboxEvidenceMaxDeviation,
  'drop_ratio' => l10n.financialInboxEvidenceDropRatio,
  'ttm_gross' => l10n.financialInboxEvidenceTtmGross,
  'prior_ttm_gross' => l10n.financialInboxEvidencePriorTtmGross,
  'asset_id' => l10n.financialInboxEvidenceAssetId,
  'primary_driver' => l10n.financialInboxEvidencePrimaryDriver,
  'unit_dividend_evidence' => l10n.financialInboxEvidenceUnitDividend,
  _ => key.replaceAll('_', ' '),
};

final class _AnomalyExpense {
  const _AnomalyExpense({
    required this.id,
    required this.date,
    required this.amount,
    required this.currency,
    this.note,
  });

  final String id;
  final String date;
  final String amount;
  final String currency;
  final String? note;
}

List<_AnomalyExpense> _anomalyExpenses(Object? value) {
  if (value is! List) return const <_AnomalyExpense>[];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((raw) {
        final id = raw['id'];
        final date = raw['date'];
        final amount = raw['amount'];
        final currency = raw['currency'];
        if (id is! String ||
            date is! String ||
            amount is! String ||
            currency is! String) {
          return null;
        }
        final parsedDate = DateTime.tryParse(date);
        return _AnomalyExpense(
          id: id,
          date: parsedDate == null ? date : _dateTime(parsedDate),
          amount: amount,
          currency: currency,
          note: raw['note'] is String ? raw['note'] as String : null,
        );
      })
      .whereType<_AnomalyExpense>()
      .toList(growable: false);
}

String _actionStateLabel(AppLocalizations l10n, LifeActionState? state) =>
    switch (state) {
      LifeActionState.todo => l10n.financialInboxActionTodo,
      LifeActionState.doing => l10n.financialInboxActionDoing,
      LifeActionState.blocked => l10n.financialInboxActionBlocked,
      LifeActionState.done => l10n.financialInboxActionDone,
      LifeActionState.dropped => l10n.financialInboxActionDropped,
      null => l10n.financialInboxActionUnknown,
    };

String _revalidationLabel(
  AppLocalizations l10n,
  FinancialSignalRevalidationStatus status,
) => switch (status) {
  FinancialSignalRevalidationStatus.cleared =>
    l10n.financialInboxRevalidationCleared,
  FinancialSignalRevalidationStatus.stillDetected =>
    l10n.financialInboxRevalidationStillDetected,
  FinancialSignalRevalidationStatus.inconclusive =>
    l10n.financialInboxRevalidationInconclusive,
  FinancialSignalRevalidationStatus.actionDropped =>
    l10n.financialInboxRevalidationActionDropped,
};
