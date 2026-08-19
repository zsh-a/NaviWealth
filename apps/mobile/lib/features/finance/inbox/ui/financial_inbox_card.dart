import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../data/financial_inbox_providers.dart';

class FinancialInboxCard extends ConsumerWidget {
  const FinancialInboxCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(financialInboxProvider);
    final items = inbox.value;
    final status = items != null
        ? Text(
            items.isEmpty
                ? l10n.financialInboxEmptyTitle
                : l10n.financialInboxCount(items.length),
            style: context.captionStyle,
          )
        : inbox.hasError
        ? Text(
            l10n.commonLoadFailed,
            style: context.captionStyle.copyWith(
              color: context.theme.colors.destructive,
            ),
          )
        : const SkeletonBox(
            key: ValueKey<String>('financial-inbox.loading'),
            width: 112,
            height: 14,
            radius: AppRadius.sm,
          );
    return SoftCard.raised(
      onPress: () {
        ref
            .read(productMetricsProvider.notifier)
            .record(ProductFunnelEvent.financialInboxOpened);
        context.push(FinanceRoutes.activityInbox);
      },
      padding: AppPageRhythm.cardPadding,
      child: Row(
        children: [
          Icon(FLucideIcons.inbox, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.financialInboxTitle, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s4),
                status,
              ],
            ),
          ),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}
