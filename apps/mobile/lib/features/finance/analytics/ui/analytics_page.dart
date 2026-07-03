import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/home_cash_flow_metrics.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/equity_classification.dart';
import 'benchmark/benchmark_comparison_card.dart';
import 'equity_allocation_section.dart';
import 'risk_alert_panel.dart';

export 'dimension_segment.dart' show DimensionSegment;
export 'equity_allocation_section.dart' show EquityAllocationContent;
export 'equity_bucket_sheet.dart'
    show EquityBucketHoldingsSheet, localizeBucketLabel;

part 'analytics/cash_flow_trend.dart';
part 'analytics/fire_progress.dart';
part 'analytics/overview_grid.dart';
part 'analytics/shared_widgets.dart';

/// Planning analytics surface. The page owns layout and active dimension
/// selection; heavy equity, risk, and benchmark sections live in `ui/`.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  EquityAllocationDimension _dimension = EquityAllocationDimension.sector;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.analyticsAppBarTitle,
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !Breakpoints.isMobile(constraints.maxWidth);
          final basePadding = isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16);
          return ListView(
            padding: basePadding.copyWith(
              bottom:
                  basePadding.bottom +
                  64 +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _AnalyticsOverviewGrid(isWide: isWide),
              const SizedBox(height: AppSpacing.s24),
              const ResponsiveTwoColumn(
                left: _CashFlowTrendCard(),
                right: _FireProgressCard(),
              ),
              const SizedBox(height: AppSpacing.s24),
              ResponsiveTwoColumn(
                left: AnalyticsEquityColumn(
                  dimension: _dimension,
                  onDimensionChanged: (d) => setState(() => _dimension = d),
                ),
                right: const _RiskAndBenchmarkColumn(),
              ),
            ],
          );
        },
      ),
    );
  }
}
