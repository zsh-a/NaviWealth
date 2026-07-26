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
import 'liability_payment_sheet.dart';

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
          AppHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            semanticsLabel: l10n.liabilityEditAction,
            onPress: () => context.push(
              FinanceRoutes.wealthLiabilityEdit(summary.liability.id),
            ),
          ),
      ],
      childPad: false,
      child: summaryAsync.when(
        loading: () => const AssetDetailSkeleton(),
        error: (error, stackTrace) => kDefaultError(
          context,
          error,
          stackTrace,
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
          error: (error, stackTrace) => kDefaultError(
            context,
            error,
            stackTrace,
            onRetry: () => ref.invalidate(
              amortizationScheduleStreamProvider(liability.id),
            ),
          ),
          data: (schedule) {
            if (schedule.isEmpty) {
              return SoftCard.raised(
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
    return SoftCard.raised(
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
    return SoftCard.raised(
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
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: context.bodyCaptionStyle),
          ),
          const SizedBox(width: AppSpacing.s12),
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(value, style: context.theme.typography.body.sm),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmortizationTable extends ConsumerStatefulWidget {
  const _AmortizationTable({required this.liability, required this.schedule});

  final Liability liability;
  final List<AmortizationEntry> schedule;

  @override
  ConsumerState<_AmortizationTable> createState() => _AmortizationTableState();
}

class _AmortizationTableState extends ConsumerState<_AmortizationTable> {
  static const _compactPreviewCount = 6;

  bool _showAll = false;
  int? _pendingPeriod;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          Breakpoints.isMobile(constraints.maxWidth)
          ? _buildCompact(context)
          : _buildTable(context, constraints.maxWidth),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final visibleSchedule = _showAll
        ? widget.schedule
        : widget.schedule.take(_compactPreviewCount).toList(growable: false);
    final hiddenCount = widget.schedule.length - visibleSchedule.length;
    return Column(
      children: [
        SoftCard.raised(
          key: const Key('liability-schedule-compact'),
          child: Column(
            children: [
              for (var i = 0; i < visibleSchedule.length; i++) ...[
                _CompactAmortizationRow(
                  row: visibleSchedule[i],
                  currency: widget.liability.currency,
                  formatters: formatters,
                  l10n: l10n,
                  busy: _pendingPeriod == visibleSchedule[i].periodIndex,
                  onMarkPaid: _pendingPeriod == null
                      ? () => _confirmMarkPaid(visibleSchedule[i])
                      : null,
                  onUndo:
                      _pendingPeriod == null &&
                          visibleSchedule[i].paidAt != null
                      ? () => _confirmUndoPayment(visibleSchedule[i])
                      : null,
                ),
                if (i != visibleSchedule.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
        if (widget.schedule.length > _compactPreviewCount) ...[
          const SizedBox(height: AppSpacing.s8),
          AppRevealControl(
            expanded: _showAll,
            collapsedLabel: l10n.commonRevealMore(hiddenCount),
            expandedLabel: l10n.commonRevealLess,
            onToggle: () => setState(() => _showAll = !_showAll),
          ),
        ],
      ],
    );
  }

  Widget _buildTable(BuildContext context, double availableWidth) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final tableWidth = availableWidth < 720 ? 720.0 : availableWidth;
    final tableHeight = (widget.schedule.length * 44 + 49)
        .clamp(137, 489)
        .toDouble();
    return SoftCard.raised(
      key: const Key('liability-schedule-table'),
      child: SizedBox(
        height: tableHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _AmortizationHeaderRow(l10n: l10n),
                const FDivider(),
                Expanded(
                  child: ListView.builder(
                    itemExtent: 44,
                    itemCount: widget.schedule.length,
                    itemBuilder: (context, i) {
                      final row = widget.schedule[i];
                      return _AmortizationDataRow(
                        row: row,
                        currency: widget.liability.currency,
                        formatters: formatters,
                        l10n: l10n,
                        busy: _pendingPeriod == row.periodIndex,
                        onMarkPaid: _pendingPeriod == null
                            ? () => _confirmMarkPaid(row)
                            : null,
                        onUndo: _pendingPeriod == null && row.paidAt != null
                            ? () => _confirmUndoPayment(row)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmMarkPaid(AmortizationEntry row) async {
    final l10n = AppLocalizations.of(context);
    final liability = widget.liability;
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
    final paymentDate = await LiabilityPaymentSheet.show(
      context,
      periodIndex: row.periodIndex,
      amount: amount,
    );
    if (paymentDate == null || !context.mounted) return;
    setState(() => _pendingPeriod = row.periodIndex);
    try {
      final repo = await ref.read(liabilityRepositoryProvider.future);
      await repo.registerPayment(
        liabilityId: liability.id,
        periodIndex: row.periodIndex,
        paidAt: paymentDate,
      );
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.success, l10n.commonSaved);
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, error, stackTrace: stackTrace),
      );
    } finally {
      if (mounted) setState(() => _pendingPeriod = null);
    }
  }

  Future<void> _confirmUndoPayment(AmortizationEntry row) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.liabilityScheduleUndoConfirmTitle(row.periodIndex)),
      body: Text(l10n.liabilityScheduleUndoConfirmBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonUndo,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _pendingPeriod = row.periodIndex);
    try {
      final repo = await ref.read(liabilityRepositoryProvider.future);
      await repo.undoPayment(
        liabilityId: widget.liability.id,
        periodIndex: row.periodIndex,
      );
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.success, l10n.commonUndoSucceeded);
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, error, stackTrace: stackTrace),
      );
    } finally {
      if (mounted) setState(() => _pendingPeriod = null);
    }
  }
}

class _CompactAmortizationRow extends StatelessWidget {
  const _CompactAmortizationRow({
    required this.row,
    required this.currency,
    required this.formatters,
    required this.l10n,
    required this.busy,
    required this.onMarkPaid,
    required this.onUndo,
  });

  final AmortizationEntry row;
  final String currency;
  final AppFormatters formatters;
  final AppLocalizations l10n;
  final bool busy;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${row.periodIndex} · ${formatters.date(row.dueDate)}',
                  style: context.theme.typography.body.sm,
                ),
              ),
              if (row.paidAt != null)
                FBadge(child: Text(l10n.liabilityScheduleStatusPaid)),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: [
              Expanded(
                child: _CompactScheduleMetric(
                  label: l10n.liabilityScheduleColPrincipal,
                  value: formatters.currency(
                    row.principalPayment,
                    code: currency,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: _CompactScheduleMetric(
                  label: l10n.liabilityScheduleColInterest,
                  value: formatters.currency(
                    row.interestPayment,
                    code: currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          _SummaryRow(
            label: l10n.liabilityScheduleColRemaining,
            value: formatters.currency(row.remainingBalance, code: currency),
          ),
          if (row.paidAt == null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppQuietButton(
              label: l10n.liabilityScheduleMarkPaid,
              busy: busy,
              expanded: true,
              onPress: onMarkPaid,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.s8),
            AppQuietButton(
              label: l10n.commonUndo,
              busy: busy,
              expanded: true,
              tone: AppQuietButtonTone.danger,
              onPress: onUndo,
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactScheduleMetric extends StatelessWidget {
  const _CompactScheduleMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.bodyCaptionStyle),
        const SizedBox(height: AppSpacing.s2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: context.theme.typography.body.sm),
        ),
      ],
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
    required this.busy,
    required this.onMarkPaid,
    required this.onUndo,
  });

  final AmortizationEntry row;
  final String currency;
  final AppFormatters formatters;
  final AppLocalizations l10n;
  final bool busy;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onUndo;

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
                ? Row(
                    children: [
                      FBadge(child: Text(l10n.liabilityScheduleStatusPaid)),
                      const SizedBox(width: AppSpacing.s4),
                      Expanded(
                        child: AppQuietButton(
                          label: l10n.commonUndo,
                          busy: busy,
                          tone: AppQuietButtonTone.danger,
                          onPress: onUndo,
                        ),
                      ),
                    ],
                  )
                : AppBusyButton(
                    label: l10n.liabilityScheduleMarkPaid,
                    busy: busy,
                    variant: FButtonVariant.ghost,
                    onPress: onMarkPaid,
                  ),
          ),
        ],
      ),
    );
  }
}
