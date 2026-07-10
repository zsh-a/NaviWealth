import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/dividend_center_providers.dart';
import '../data/dividend_forecast_providers.dart';
import '../domain/dividend_center.dart';
import 'dividend_event_actions.dart';

part 'dividend_center_common.dart';
part 'dividend_center_forecast.dart';
part 'dividend_center_kpis.dart';
part 'dividend_center_ranking.dart';
part 'dividend_center_timeline.dart';

class DividendCenterPage extends ConsumerWidget {
  const DividendCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(dividendCenterSnapshotProvider);
    return AppPageScaffold(
      title: l10n.dividendCenterTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.creditCard),
          onPress: () => context.push(FinanceRoutes.wealthCorporateAction),
        ),
      ],
      childPad: false,
      child: PageSkeletonShell<DividendCenterSnapshot>(
        skeleton: const DividendCenterSkeleton(),
        isLoading: snapshot.isLoading,
        child: snapshot.when(
          loading: () => const DividendCenterSkeleton(),
          error: (error, stackTrace) => AppEmptyState.error(
            title: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load dividend center',
            ),
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () => ref.invalidate(dividendCenterSnapshotProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (data) => _DividendCenterBody(snapshot: data),
        ),
      ),
    );
  }
}

class _DividendCenterBody extends StatelessWidget {
  const _DividendCenterBody({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
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
            if (snapshot.isEmpty)
              const _EmptyDividendState()
            else ...[
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              _RankingSection(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              const _ForecastCard(),
              const SizedBox(height: AppSpacing.s16),
              _TimelineSection(snapshot: snapshot),
            ],
          ],
        ),
      ),
    );
  }
}
