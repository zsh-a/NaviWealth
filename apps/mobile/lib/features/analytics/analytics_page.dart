import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'domain/equity_classification.dart';
import 'ui/benchmark/benchmark_comparison_card.dart';
import 'ui/equity_allocation_section.dart';
import 'ui/risk_alert_panel.dart';

export 'ui/dimension_segment.dart' show DimensionSegment;
export 'ui/equity_allocation_section.dart' show EquityAllocationContent;
export 'ui/equity_bucket_sheet.dart'
    show EquityBucketHoldingsSheet, localizeBucketLabel;

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
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.analyticsAppBarTitle)),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = !Breakpoints.isMobile(constraints.maxWidth);
            final basePadding = isWide
                ? const EdgeInsets.all(24)
                : const EdgeInsets.all(16);
            return ListView(
              padding: basePadding.copyWith(
                bottom:
                    basePadding.bottom +
                    64 +
                    MediaQuery.paddingOf(context).bottom,
              ),
              children: [
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
      ),
    );
  }
}

class _RiskAndBenchmarkColumn extends StatelessWidget {
  const _RiskAndBenchmarkColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskAlertPanel(),
        SizedBox(height: 24),
        BenchmarkComparisonCard(),
      ],
    );
  }
}
