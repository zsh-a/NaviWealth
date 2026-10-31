import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../activity/ui/activity_action_panel.dart';
import '../../composition/finance_route_paths.dart';
import '../data/finance_activation_providers.dart';
import '../data/finance_activation_store.dart';
import '../domain/finance_activation.dart';

class FinanceActivationCard extends ConsumerWidget {
  const FinanceActivationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activation = ref.watch(financeActivationProvider);
    final dismissed = ref.watch(financeActivationDismissedProvider);
    final snapshot = activation.value;
    if (dismissed || snapshot == null || snapshot.isComplete) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final (title, body, action, route) = switch (snapshot.stage) {
      FinanceActivationStage.addData => (
        l10n.financeActivationDataTitle,
        l10n.financeActivationDataBody,
        l10n.financeActivationDataAction,
        FinanceRoutes.activity,
      ),
      FinanceActivationStage.reviewData => (
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
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(FLucideIcons.route, color: context.theme.colors.primary),
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: Text(title, style: context.rowTitleStyle)),
              AppBadge(
                label: l10n.financeActivationProgress(
                  snapshot.completedSteps,
                  FinanceActivationSnapshot.totalSteps,
                ),
                size: AppBadgeSize.compact,
              ),
              AppIconButton(
                icon: FLucideIcons.x,
                tooltip: l10n.financeActivationDismiss,
                onPress: () => ref
                    .read(financeActivationDismissedProvider.notifier)
                    .dismiss(),
                size: 44,
                iconSize: AppIconSizes.xs,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(body, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            onPress: () {
              if (snapshot.stage == FinanceActivationStage.addData) {
                unawaited(showActivityActionPanel(context));
              } else {
                context.push(route);
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
