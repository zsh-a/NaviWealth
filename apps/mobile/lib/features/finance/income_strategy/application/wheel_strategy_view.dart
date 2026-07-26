import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

import 'leaps_income_sleeve_adapter.dart';
import 'wheel_income_sleeve_adapter.dart';

/// Wheel drill-down projected from the generic income strategy snapshot.
///
/// This keeps the Wheel UI convenient without establishing a second
/// composition engine or a special Wheel+LEAPS source of truth.
class WheelStrategyView {
  const WheelStrategyView({
    required this.underlying,
    required this.wheel,
    required this.positions,
  });

  final UnderlyingIncomeStrategySnapshot underlying;
  final WheelLifecycle wheel;
  final List<LeapsCallPosition> positions;

  List<LeapsCallPosition> get openPositions =>
      positions.where((position) => position.isOpen).toList(growable: false);

  IncomeStrategySleeveSnapshot? get leaps =>
      underlying.sleeves[IncomeStrategySleeveKind.leapsCall];

  Decimal get openLeapsCost =>
      leaps?.capitalAtRisk.value.amount ?? Decimal.zero;
  Decimal get realizedLeapsPnl =>
      leaps?.realizedResult.value.amount ?? Decimal.zero;
  Decimal get underlyingRealizedResult =>
      underlying.realizedResult.value.amount;
  Decimal? get deltaEquivalentShares => leaps?.deltaEquivalentShares;
  List<IncomeStrategyRisk> get risks => underlying.risks;

  Decimal? get wheelIncomeCoverageRatio => openLeapsCost == Decimal.zero
      ? null
      : (wheel.cumulativeIncome / openLeapsCost).toDecimal(
          scaleOnInfinitePrecision: 8,
        );
}

List<WheelStrategyView> buildWheelStrategyViews(
  PortfolioIncomeStrategySnapshot portfolio,
) {
  final views = <WheelStrategyView>[];
  for (final underlying in portfolio.underlyings) {
    final wheelSnapshot = underlying.sleeves[IncomeStrategySleeveKind.wheel];
    final leapsSnapshot =
        underlying.sleeves[IncomeStrategySleeveKind.leapsCall];
    if (wheelSnapshot == null && leapsSnapshot == null) continue;
    final wheelDetails = wheelSnapshot?.details;
    final leapsDetails = leapsSnapshot?.details;
    views.add(
      WheelStrategyView(
        underlying: underlying,
        wheel: wheelDetails is WheelIncomeSleeveDetails
            ? wheelDetails.lifecycle
            : WheelLifecycle.empty(
                symbol: underlying.asset.symbol,
                currency: underlying.asset.currency,
              ),
        positions: leapsDetails is LeapsIncomeSleeveDetails
            ? leapsDetails.positions
            : const <LeapsCallPosition>[],
      ),
    );
  }
  views.sort((a, b) {
    final aOpen = a.wheel.hasOpenPosition || a.openPositions.isNotEmpty;
    final bOpen = b.wheel.hasOpenPosition || b.openPositions.isNotEmpty;
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    return a.underlying.asset.symbol.compareTo(b.underlying.asset.symbol);
  });
  return List.unmodifiable(views);
}
