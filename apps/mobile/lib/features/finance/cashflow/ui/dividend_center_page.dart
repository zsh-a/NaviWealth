import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart'
    show holdingsSnapshotProvider;
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/dividend_center_providers.dart';
import '../data/dividend_forecast_providers.dart';
import '../domain/dividend_center.dart';
import '../domain/dividend_policy_monitor.dart';
import '../domain/dividend_resilience.dart';
import 'dividend_event_actions.dart';

part 'dividend_center_common.dart';
part 'dividend_center_forecast.dart';
part 'dividend_center_kpis.dart';
part 'dividend_center_ranking.dart';
part 'dividend_center_resilience.dart';
part 'dividend_center_timeline.dart';

const _dividendIncomeMonitor = DividendPolicyMonitor();

class DividendCenterPage extends ConsumerWidget {
  const DividendCenterPage({super.key, this.focusAssetId});

  final String? focusAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(dividendCashProjection90dProvider, (_, next) {
      final projections = next.asData?.value;
      final center = ref.read(dividendCenterSnapshotProvider).asData?.value;
      final forecast = ref.read(dividendForecast12mProvider).asData?.value;
      if (projections == null || center == null || forecast == null) return;
      unawaited(() async {
        final repository = await ref.read(
          dividendForecastRepositoryProvider.future,
        );
        await repository.recordAndEvaluate(
          asOf: ref.read(dividendCenterNowProvider),
          currency: center.baseCurrency,
          projections: projections,
          actualEvents: center.events,
          strategy: forecast.strategy,
          confidence: forecast.confidence,
        );
      }());
    });
    final snapshot = ref.watch(dividendCenterSnapshotProvider);
    return AppPageScaffold(
      title: l10n.dividendCenterTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.dividendCenterRecordAction,
          onPress: () => context.push(FinanceRoutes.wealthCorporateAction),
        ),
      ],
      childPad: false,
      child: PageSkeletonShell<DividendCenterSnapshot>(
        skeleton: const DividendCenterSkeleton(),
        isLoading: snapshot.isLoading,
        child: snapshot.when(
          loading: () => const DividendCenterSkeleton(),
          error: (error, stackTrace) => kDefaultError(
            context,
            error,
            stackTrace,
            onRetry: () => ref.invalidate(dividendCenterSnapshotProvider),
          ),
          data: (data) =>
              _DividendCenterBody(snapshot: data, focusAssetId: focusAssetId),
        ),
      ),
    );
  }
}

class _DividendCenterBody extends ConsumerWidget {
  const _DividendCenterBody({required this.snapshot, this.focusAssetId});

  final DividendCenterSnapshot snapshot;
  final String? focusAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final holdingsAsync = ref.watch(holdingsSnapshotProvider);
    final heldIds = holdingsAsync.asData?.value.keys.toSet();
    final deteriorations = heldIds == null
        ? const <DividendDeterioration>[]
        : _dividendIncomeMonitor.detect(
            events: snapshot.events,
            now: ref.watch(dividendCenterNowProvider),
            heldAssetIds: heldIds,
          );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.dashboard,
        padding: EdgeInsets.zero,
        primary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot.fxExclusions.isNotEmpty) ...[
              AppStatusBanner(
                kind: AppStatusKind.warning,
                message: l10n.dividendCenterFxIncomplete(
                  snapshot.fxExclusions.length,
                  snapshot.missingFxCurrencies.join(', '),
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (deteriorations.isNotEmpty) ...[
              _DividendPolicySection(
                rows: deteriorations,
                focusAssetId: focusAssetId,
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (snapshot.isEmpty) ...[
              const _ForecastCard(),
              const SizedBox(height: AppSpacing.s16),
              const _EmptyDividendState(),
            ] else ...[
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              _DividendResilienceAsyncSection(
                currency: snapshot.baseCurrency,
                focusAssetId: focusAssetId,
              ),
              const SizedBox(height: AppSpacing.s16),
              const _ForecastCard(),
              const SizedBox(height: AppSpacing.s16),
              _RankingSection(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              _TimelineSection(snapshot: snapshot),
            ],
          ],
        ),
      ),
    );
  }
}

/// Keeps the isolate-backed result scoped to this section. Completing the
/// analysis should not rebuild the KPI, forecast, ranking, and timeline trees
/// around it, and empty dividend centers never mount this consumer at all.
class _DividendResilienceAsyncSection extends ConsumerWidget {
  const _DividendResilienceAsyncSection({
    required this.currency,
    required this.focusAssetId,
  });

  final String currency;
  final String? focusAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(dividendResilienceProvider)
        .whenOrLoading(
          context: context,
          loading: () => const _DividendResilienceSkeleton(),
          error: (_, _) => AppStatusBanner(
            kind: AppStatusKind.warning,
            message: l10n.commonLoadFailed,
          ),
          data: (resilience) => _DividendResilienceSection(
            report: resilience,
            currency: currency,
            focusAssetId: focusAssetId,
          ),
        );
  }
}

class _DividendResilienceSkeleton extends StatelessWidget {
  const _DividendResilienceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 160, height: 16, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(height: AppChartHeights.compact, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.s12),
          SkeletonBox(width: 220, height: 14, radius: AppRadius.sm),
        ],
      ),
    );
  }
}
