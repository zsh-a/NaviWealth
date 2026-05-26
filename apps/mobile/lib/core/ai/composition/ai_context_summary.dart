/// Cross-domain seam for the AI chat page header summary chip
/// (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// The header chip on the AI chat page shows a compact rolling pulse
/// of the user's life signals — today net-worth direction, expense
/// anomalies, deposit maturities for Finance; analogous health signals
/// for HealthOS once D-2 lands. Each domain provides its own summary
/// composer via a Riverpod provider; bootstrap registers the active
/// build's contributor.
///
/// **Relationship to memory layer**: this is intentionally a display-
/// only summary (no AI context input). The ContextPack pipeline used
/// for chat turns is `chat_trace_prep.dart`. The two surfaces share
/// the same upstream providers but project them differently.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AiContextSummary {
  const AiContextSummary({
    required this.baseCurrency,
    required this.monthlyChangePct,
    required this.todaysChange,
    required this.unusualExpensesCount,
    required this.upcomingMaturitiesCount,
    required this.upcomingMaturitiesDays,
  });

  /// Shell-only default — used when no domain has registered a
  /// summary. Renders as `isEmpty == true`, so the chip collapses.
  static const AiContextSummary empty = AiContextSummary(
    baseCurrency: 'USD',
    monthlyChangePct: null,
    todaysChange: 0,
    unusualExpensesCount: 0,
    upcomingMaturitiesCount: 0,
    upcomingMaturitiesDays: 0,
  );

  final String baseCurrency;

  /// Month-to-date net-worth change as a fraction (e.g. 0.034 = +3.4%).
  /// `null` when no metrics are available yet (cold-start, no data).
  final double? monthlyChangePct;

  /// Today's net-worth change in base currency. May be zero.
  final double todaysChange;

  /// Number of expense anomalies detected this period (0 if none).
  final int unusualExpensesCount;

  /// Number of deposit maturities upcoming inside [upcomingMaturitiesDays]
  /// days. Both fields are zero when no maturities are imminent.
  final int upcomingMaturitiesCount;
  final int upcomingMaturitiesDays;

  bool get isEmpty =>
      monthlyChangePct == null &&
      todaysChange == 0 &&
      unusualExpensesCount == 0 &&
      upcomingMaturitiesCount == 0;
}

/// Active summary for the current build. Default is the empty
/// summary; bootstrap overrides with the active domain's composer.
final aiContextSummaryProvider = Provider<AiContextSummary>(
  (ref) => AiContextSummary.empty,
);
