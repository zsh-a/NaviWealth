import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../data/finance_activation_providers.dart';
import '../domain/finance_activation.dart';

class FinanceActivationCard extends ConsumerStatefulWidget {
  const FinanceActivationCard({super.key});

  @override
  ConsumerState<FinanceActivationCard> createState() =>
      _FinanceActivationCardState();
}

class _FinanceActivationCardState extends ConsumerState<FinanceActivationCard> {
  bool _completionRecorded = false;

  void _recordCompletion(FinanceActivationSnapshot? snapshot) {
    if (_completionRecorded || snapshot?.isComplete != true) return;
    _completionRecorded = true;
    unawaited(
      ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.firstUsefulResultCompleted, success: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      financeActivationProvider,
      (_, next) => _recordCompletion(next.value),
    );
    final activation = ref.watch(financeActivationProvider);
    final snapshot = activation.value;
    _recordCompletion(snapshot);
    if (snapshot == null || snapshot.isComplete) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final (title, body, action, route) = switch (snapshot.stage) {
      FinanceActivationStage.importData => (
        l10n.financeActivationImportTitle,
        l10n.financeActivationImportBody,
        l10n.financeActivationImportAction,
        FinanceRoutes.activityIngest,
      ),
      FinanceActivationStage.reviewImport => (
        l10n.financeActivationReviewTitle,
        l10n.financeActivationReviewBody(snapshot.pendingReviewCount),
        l10n.financeActivationReviewAction,
        FinanceRoutes.activityIngest,
      ),
      FinanceActivationStage.reviewRunway => (
        l10n.financeActivationRunwayTitle,
        l10n.financeActivationRunwayBody,
        l10n.financeActivationRunwayAction,
        FinanceRoutes.planRunway,
      ),
      FinanceActivationStage.complete => throw StateError('unreachable'),
    };
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(FLucideIcons.route, color: context.theme.colors.primary),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  l10n.financeActivationTitle,
                  style: context.rowTitleStyle,
                ),
              ),
              AppBadge(
                label: l10n.financeActivationProgress(
                  snapshot.completedSteps,
                  FinanceActivationSnapshot.totalSteps,
                ),
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(title, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(body, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            onPress: () {
              ref
                  .read(productMetricsProvider.notifier)
                  .record(ProductFunnelEvent.activationStarted);
              context.push(route);
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
