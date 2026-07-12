import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/liability_summary.dart';
import 'liability_l10n.dart';

class LiabilityDetailPage extends ConsumerWidget {
  const LiabilityDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaryAsync = ref.watch(liabilitySummaryProvider(id));

    return AppPageScaffold(
      title: summaryAsync.value?.liability.name ?? l10n.liabilitiesAppBarTitle,
      actions: [
        if (summaryAsync.value case final summary?)
          FHeaderAction(
            icon: FTooltip(
              tipBuilder: (_, _) => Text(l10n.liabilityEditAction),
              child: const Icon(FLucideIcons.pencil),
            ),
            semanticsLabel: l10n.liabilityEditAction,
            onPress: () => context.push(
              FinanceRoutes.wealthLiabilityEdit(summary.liability.id),
            ),
          ),
      ],
      childPad: false,
      child: summaryAsync.when(
        loading: () => const AssetDetailSkeleton(),
        error: (error, stackTrace) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error, stackTrace: stackTrace),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(liabilitySummaryProvider(id)),
        ),
        data: (summary) {
          if (summary == null) {
            return Center(child: Text(l10n.liabilityNotFound));
          }
          return _LiabilityDetailBody(summary: summary);
        },
      ),
    );
  }
}

class _LiabilityDetailBody extends ConsumerWidget {
  const _LiabilityDetailBody({required this.summary});

  final LiabilitySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final liability = summary.liability;
    final scheduleAsync = ref.watch(
      amortizationScheduleStreamProvider(liability.id),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        _LiabilityHeaderCard(summary: summary),
        const SizedBox(height: AppSpacing.s12),
        _LiabilitySummaryCard(summary: summary),
        const SizedBox(height: AppSpacing.s16),
        Text(
          l10n.liabilityScheduleHeading,
          style: context.theme.typography.body.md,
        ),
        const SizedBox(height: AppSpacing.s8),
        scheduleAsync.when(
          loading: () => const SkeletonCard(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: Column(
              children: [
                SkeletonBox(height: 18),
                SizedBox(height: AppSpacing.s8),
                SkeletonBox(height: 18),
                SizedBox(height: AppSpacing.s8),
                SkeletonBox(height: 18),
              ],
            ),
          ),
          error: (error, stackTrace) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
            ),
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(
              amortizationScheduleStreamProvider(liability.id),
            ),
          ),
          data: (schedule) {
            if (schedule.isEmpty) {
              return SoftCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Text(l10n.liabilityRevolvingNoSchedule),
                ),
              );
            }
            return _AmortizationTable(liability: liability, schedule: schedule);
          },
        ),
      ],
    );
  }
}

class _LiabilityHeaderCard extends ConsumerWidget {
  const _LiabilityHeaderCard({required this.summary});

  final LiabilitySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final l = summary.liability;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.name, style: context.theme.typography.body.lg),
            const SizedBox(height: AppSpacing.s8),
            Text(
              '${liabilityTypeLabel(l10n, l.type)} · '
              '${repaymentMethodLabel(l10n, l.paymentMethod)} · '
              '${rateTypeLabel(l10n, l.rateType)}',
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              formatters.currency(l.principal, code: l.currency),
              style: context.theme.typography.body.xl,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              formatters.percent(l.interestRate.toDouble()),
              style: context.theme.typography.body.sm,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiabilitySummaryCard extends ConsumerWidget {
  const _LiabilitySummaryCard({required this.summary});

  final LiabilitySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final l = summary.liability;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(
              label: l10n.liabilitySummaryRemaining,
              value: formatters.currency(
                summary.remainingPrincipal,
                code: l.currency,
              ),
            ),
            _SummaryRow(
              label: l10n.liabilitySummaryInterestPaid,
              value: formatters.currency(
                summary.interestPaid,
                code: l.currency,
              ),
            ),
            _SummaryRow(
              label: l10n.liabilitySummaryInterestTotal,
              value: formatters.currency(
                summary.totalScheduledInterest,
                code: l.currency,
              ),
            ),
            _SummaryRow(
              label: l10n.liabilitySummaryInterestRatio,
              value: formatters.percent(summary.interestRatio.toDouble()),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (summary.totalPeriods > 0) ...[
              FDeterminateProgress(
                value: summary.progressFraction.clamp(0.0, 1.0),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.liabilitySummaryProgress(
                  summary.paidPeriods,
                  summary.totalPeriods,
                ),
                style: context.captionStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.bodyCaptionStyle),
          Text(value, style: context.theme.typography.body.sm),
        ],
      ),
    );
  }
}

class _AmortizationTable extends ConsumerWidget {
  const _AmortizationTable({required this.liability, required this.schedule});

  final Liability liability;
  final List<AmortizationEntry> schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    return SoftCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _AmortizationHeaderRow(l10n: l10n),
          ),
          const FDivider(),
          // Lazy body — only visible rows are built.
          Flexible(
            child: ListView.builder(
              itemExtent: 44,
              itemCount: schedule.length,
              itemBuilder: (context, i) {
                final row = schedule[i];
                return _AmortizationDataRow(
                  row: row,
                  currency: liability.currency,
                  formatters: formatters,
                  l10n: l10n,
                  onMarkPaid: () =>
                      _confirmMarkPaid(context, ref, row, liability),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmMarkPaid(
    BuildContext context,
    WidgetRef ref,
    AmortizationEntry row,
    Liability liability,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (liability.accountId == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.liabilityScheduleMarkPaidNoAccount,
      );
      return;
    }
    final formatters = context.formatters(ref);
    final amount = formatters.currency(
      row.principalPayment + row.interestPayment,
      code: liability.currency,
    );
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.liabilityScheduleMarkPaidConfirmTitle(row.periodIndex)),
      body: Text(l10n.liabilityScheduleMarkPaidConfirmBody(amount)),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonConfirm,
    );
    if (confirmed != true || !context.mounted) return;
    final repo = await ref.read(liabilityRepositoryProvider.future);
    await repo.registerPayment(
      liabilityId: liability.id,
      periodIndex: row.periodIndex,
    );
  }
}

class _AmortizationHeaderRow extends StatelessWidget {
  const _AmortizationHeaderRow({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final style = context.theme.typography.body.xs2;
    const actionColumnWidth = AppSpacing.s40 * 3;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppControlWidths.scheduleIndex,
            child: Text(l10n.liabilityScheduleColPeriod, style: style),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(l10n.liabilityScheduleColDue, style: style),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              l10n.liabilityScheduleColPrincipal,
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              l10n.liabilityScheduleColInterest,
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              l10n.liabilityScheduleColRemaining,
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: actionColumnWidth),
        ],
      ),
    );
  }
}

class _AmortizationDataRow extends StatelessWidget {
  const _AmortizationDataRow({
    required this.row,
    required this.currency,
    required this.formatters,
    required this.l10n,
    required this.onMarkPaid,
  });

  final AmortizationEntry row;
  final String currency;
  final AppFormatters formatters;
  final AppLocalizations l10n;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final textStyle = context.theme.typography.body.xs;
    const actionColumnWidth = AppSpacing.s40 * 3;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppControlWidths.scheduleIndex,
            child: Text('${row.periodIndex}', style: textStyle),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(formatters.date(row.dueDate), style: textStyle),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              formatters.currency(row.principalPayment, code: currency),
              style: textStyle,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              formatters.currency(row.interestPayment, code: currency),
              style: textStyle,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: AppControlWidths.scheduleValue,
            child: Text(
              formatters.currency(row.remainingBalance, code: currency),
              style: textStyle,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: actionColumnWidth,
            child: row.paidAt != null
                ? FBadge(child: Text(l10n.liabilityScheduleStatusPaid))
                : FButton(
                    variant: FButtonVariant.ghost,
                    onPress: onMarkPaid,
                    child: Text(l10n.liabilityScheduleMarkPaid),
                  ),
          ),
        ],
      ),
    );
  }
}
