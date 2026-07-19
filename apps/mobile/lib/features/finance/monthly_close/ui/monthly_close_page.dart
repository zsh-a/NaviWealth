import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../data/monthly_close_providers.dart';
import '../domain/monthly_close.dart';

class MonthlyClosePage extends ConsumerWidget {
  const MonthlyClosePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(currentClosePeriodProvider);
    final closeAsync = ref.watch(currentMonthlyCloseProvider);
    return AppPageScaffold(
      title: l10n.monthlyCloseTitle,
      childPad: false,
      child: closeAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: '$error',
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(currentMonthlyCloseProvider),
        ),
        data: (close) => ListView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          children: [
            Text(l10n.monthlyClosePeriod(period), style: context.rowTitleStyle),
            const SizedBox(height: AppSpacing.s4),
            Text(l10n.monthlyCloseIntro, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s16),
            for (final step in MonthlyCloseStep.values) ...[
              _CloseStepRow(
                step: step,
                completed: close?.completedSteps.contains(step) ?? false,
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            const SizedBox(height: AppSpacing.s12),
            FButton(
              onPress: close?.isComplete == true && close?.closedAt == null
                  ? () async {
                      final repository = await ref.read(
                        monthlyCloseRepositoryProvider.future,
                      );
                      await repository.close(
                        periodMonth: period,
                        now: DateTime.now(),
                      );
                      await ref
                          .read(productMetricsProvider.notifier)
                          .record(
                            ProductFunnelEvent.monthlyCloseCompleted,
                            success: true,
                          );
                    }
                  : null,
              child: Text(
                close?.closedAt == null
                    ? l10n.monthlyCloseComplete
                    : l10n.monthlyCloseCompleted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseStepRow extends ConsumerWidget {
  const _CloseStepRow({required this.step, required this.completed});

  final MonthlyCloseStep step;
  final bool completed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (label, route) = switch (step) {
      MonthlyCloseStep.importReview => (
        l10n.monthlyCloseImport,
        FinanceRoutes.activityIngest,
      ),
      MonthlyCloseStep.inboxClear => (
        l10n.monthlyCloseInbox,
        FinanceRoutes.activityInbox,
      ),
      MonthlyCloseStep.accountReconcile => (
        l10n.monthlyCloseAccounts,
        FinanceRoutes.wealthAccounts,
      ),
      MonthlyCloseStep.runwayReview => (
        l10n.monthlyCloseRunway,
        FinanceRoutes.planRunway,
      ),
      MonthlyCloseStep.actionReview => (
        l10n.monthlyCloseActions,
        ref.watch(lifeActionReviewRouteProvider) ?? FinanceRoutes.home,
      ),
    };
    return SoftCard.raised(
      borderless: true,
      onPress: () => context.push(route),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          Icon(
            completed ? FLucideIcons.circleCheckBig : FLucideIcons.circle,
            color: completed
                ? SemanticColors.of(context).success
                : context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(child: Text(label, style: context.labelStyle)),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () async {
              final repository = await ref.read(
                monthlyCloseRepositoryProvider.future,
              );
              await repository.toggleStep(
                periodMonth: ref.read(currentClosePeriodProvider),
                step: step,
                now: DateTime.now(),
              );
            },
            child: Text(
              completed ? l10n.monthlyCloseUndo : l10n.monthlyCloseMarkDone,
            ),
          ),
        ],
      ),
    );
  }
}
