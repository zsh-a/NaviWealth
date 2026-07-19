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
    final count = ref.watch(financialInboxProvider).length;
    return SoftCard.raised(
      borderless: true,
      onPress: () {
        ref
            .read(productMetricsProvider.notifier)
            .record(ProductFunnelEvent.financialInboxOpened);
        context.push(FinanceRoutes.activityInbox);
      },
      padding: const EdgeInsets.all(AppSpacing.s14),
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
                Text(
                  count == 0
                      ? l10n.financialInboxEmptyTitle
                      : l10n.financialInboxCount(count),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
        ],
      ),
    );
  }
}
