import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../state/ai_context_summary_provider.dart';

/// Compact "this month" pulse strip rendered above the AI chat surface.
///
/// Communicates the four numbers the assistant is grounded on so the
/// user can immediately judge whether the chat replies match reality:
///   • Net worth Δ MTD
///   • Today's net-worth move
///   • Unusual expenses this period
///   • Upcoming deposit maturities
class AiContextSummaryHeader extends ConsumerWidget {
  const AiContextSummaryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(aiContextSummaryProvider);
    if (summary.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiContextSummaryThisMonth,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCell(
                      label: l10n.aiContextSummaryNetWorthDelta,
                      child: summary.monthlyChangePct == null
                          ? const Text('—')
                          : DeltaChip(
                              value: summary.monthlyChangePct! * 100,
                              fractionDigits: 2,
                            ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: context.theme.colors.border,
                  ),
                  Expanded(
                    child: _SummaryCell(
                      label: l10n.aiContextSummaryTodayDelta,
                      child: DeltaText(
                        value: summary.todaysChange,
                        format: DeltaFormat.currency,
                        currencyCode: summary.baseCurrency,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: context.theme.colors.border,
                  ),
                  Expanded(
                    child: _SummaryCell(
                      label: l10n.aiContextSummaryUnusualExpenses,
                      child: Text(
                        '${summary.unusualExpensesCount}',
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: context.theme.colors.border,
                  ),
                  Expanded(
                    child: _SummaryCell(
                      label: l10n.aiContextSummaryUpcoming,
                      child: Text(
                        '${summary.upcomingMaturitiesCount}',
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.theme.typography.xs2.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            style: context.theme.typography.sm,
            child: child,
          ),
        ],
      ),
    );
  }
}
