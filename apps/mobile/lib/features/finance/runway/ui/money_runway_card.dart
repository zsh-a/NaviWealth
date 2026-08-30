import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/money_runway_providers.dart';
import '../domain/money_runway.dart';

class MoneyRunwayCard extends ConsumerWidget {
  const MoneyRunwayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final runway = ref.watch(moneyRunwayProvider);
    return runway.when(
      loading: () => const SoftCard.raised(
        padding: EdgeInsets.all(AppSpacing.s16),
        child: SkeletonBox(height: 112, radius: AppRadius.md),
      ),
      // Keep the card with an em-dash value (the `_ValueDash` precedent)
      // instead of silently dropping the hero metric.
      error: (_, _) => SoftCard.raised(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppMetricHeader(
              icon: FLucideIcons.calendarRange,
              title: l10n.moneyRunwayTitle,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              '—',
              style: TypographyTokens.numericTitleStrong.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      data: (snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final formatter = context.formatters(ref);
        final label = switch (snapshot.status) {
          MoneyRunwayStatus.healthy => l10n.moneyRunwayStatusHealthy,
          MoneyRunwayStatus.watch => l10n.moneyRunwayStatusWatch,
          MoneyRunwayStatus.shortfall => l10n.moneyRunwayStatusShortfall,
        };
        return SoftCard.raised(
          onPress: () {
            ref
                .read(productMetricsProvider.notifier)
                .record(ProductFunnelEvent.moneyRunwayOpened);
            context.push(FinanceRoutes.planRunway);
          },
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppMetricHeader(
                icon: FLucideIcons.calendarRange,
                title: l10n.moneyRunwayTitle,
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                formatter.currency(
                  snapshot.balanceAt(90),
                  code: snapshot.currency,
                ),
                style: TypographyTokens.numericTitleStrong,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '${l10n.moneyRunwayNinetyDayBalance} · $label',
                style: context.captionStyle,
              ),
            ],
          ),
        );
      },
    );
  }
}
