import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/liability.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.liabilitiesAppBarTitle)),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
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
      padding: Spacing.pageMobile,
      children: [
        _LiabilityHeaderCard(summary: summary),
        const SizedBox(height: Spacing.s12),
        _LiabilitySummaryCard(summary: summary),
        const SizedBox(height: Spacing.s16),
        Text(
          l10n.liabilityScheduleHeading,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Spacing.s8),
        scheduleAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.s24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(Spacing.s16),
            child: Text('$e'),
          ),
          data: (schedule) {
            if (schedule.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.s16),
                  child: Text(l10n.liabilityRevolvingNoSchedule),
                ),
              );
            }
            return _AmortizationTable(
              liability: liability,
              schedule: schedule,
            );
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final l = summary.liability;
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.s4),
            Text(
              '${liabilityTypeLabel(l10n, l.type)} · '
              '${repaymentMethodLabel(l10n, l.paymentMethod)} · '
              '${rateTypeLabel(l10n, l.rateType)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s12),
            Text(
              formatters.currency(l.principal, code: l.currency),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              formatters.percent(l.interestRate.toDouble()),
              style: theme.textTheme.bodyMedium,
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final l = summary.liability;
    return Card(
      child: Padding(
        padding: Spacing.card,
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
              value: formatters.percent(
                summary.interestRatio.toDouble(),
              ),
            ),
            const SizedBox(height: Spacing.s8),
            if (summary.totalPeriods > 0) ...[
              LinearProgressIndicator(value: summary.progressFraction),
              const SizedBox(height: Spacing.s4),
              Text(
                l10n.liabilitySummaryProgress(
                  summary.paidPeriods,
                  summary.totalPeriods,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.titleSmall),
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columnSpacing: Spacing.s24,
          columns: [
            DataColumn(label: Text(l10n.liabilityScheduleColPeriod)),
            DataColumn(label: Text(l10n.liabilityScheduleColDue)),
            DataColumn(
              label: Text(l10n.liabilityScheduleColPrincipal),
              numeric: true,
            ),
            DataColumn(
              label: Text(l10n.liabilityScheduleColInterest),
              numeric: true,
            ),
            DataColumn(
              label: Text(l10n.liabilityScheduleColRemaining),
              numeric: true,
            ),
            DataColumn(label: Text(l10n.liabilityScheduleColStatus)),
          ],
          rows: [
            for (final row in schedule)
              DataRow(
                cells: [
                  DataCell(Text('${row.periodIndex}')),
                  DataCell(Text(formatters.date(row.dueDate))),
                  DataCell(
                    Text(
                      formatters.currency(
                        row.principalPayment,
                        code: liability.currency,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      formatters.currency(
                        row.interestPayment,
                        code: liability.currency,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      formatters.currency(
                        row.remainingBalance,
                        code: liability.currency,
                      ),
                    ),
                  ),
                  DataCell(
                    row.paidAt != null
                        ? Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(l10n.liabilityScheduleStatusPaid),
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                          )
                        : TextButton(
                            onPressed: () => _confirmMarkPaid(
                              context,
                              ref,
                              row,
                              liability,
                            ),
                            child: Text(l10n.liabilityScheduleMarkPaid),
                          ),
                  ),
                ],
              ),
          ],
        ),
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
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.liabilityScheduleMarkPaidNoAccount),
        ),
      );
      return;
    }
    final formatters = context.formatters(ref);
    final amount = formatters.currency(
      row.principalPayment + row.interestPayment,
      code: liability.currency,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l10n.liabilityScheduleMarkPaidConfirmTitle(row.periodIndex),
          ),
          content: Text(
            l10n.liabilityScheduleMarkPaidConfirmBody(amount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final repo = await ref.read(liabilityRepositoryProvider.future);
    await repo.registerPayment(
      liabilityId: liability.id,
      periodIndex: row.periodIndex,
    );
  }
}
