import 'package:decimal/decimal.dart';

import 'leaps_call_position.dart';
import 'wheel_lifecycle.dart';

enum WheelLeapsWarning {
  stackedDownside,
  costNotCovered,
  deltaUnavailable,
  markUnavailable,
  expirationNear,
}

/// Portfolio-level overlay joining one Wheel lifecycle with independently
/// purchased long calls. This is deliberately not a Wheel state machine.
class WheelLeapsOverlay {
  const WheelLeapsOverlay({
    required this.wheel,
    required this.positions,
    required this.openPositions,
    required this.openLeapsCost,
    required this.realizedLeapsPnl,
    required this.deltaEquivalentShares,
    required this.warnings,
  });

  final WheelLifecycle wheel;
  final List<LeapsCallPosition> positions;
  final List<LeapsCallPosition> openPositions;
  final Decimal openLeapsCost;
  final Decimal realizedLeapsPnl;
  final Decimal? deltaEquivalentShares;
  final Set<WheelLeapsWarning> warnings;

  Decimal get combinedRealizedPnl => wheel.cumulativeIncome + realizedLeapsPnl;

  /// Wheel income remaining after comparing it with capital still at risk in
  /// open calls. This is a coverage view, not accounting realized P&L.
  Decimal get wheelIncomeAfterOpenLeapsCost =>
      wheel.cumulativeIncome - openLeapsCost;

  Decimal? get wheelIncomeCoverageRatio => openLeapsCost == Decimal.zero
      ? null
      : (wheel.cumulativeIncome / openLeapsCost).toDecimal(
          scaleOnInfinitePrecision: 8,
        );
}

WheelLeapsOverlay buildWheelLeapsOverlay({
  required WheelLifecycle wheel,
  required Iterable<LeapsCallPosition> positions,
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final ours = positions.where((p) => p.symbol == wheel.symbol).toList()
    ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
  final open = ours.where((p) => p.isOpen).toList(growable: false);
  var cost = Decimal.zero;
  var realized = Decimal.zero;
  var delta = Decimal.zero;
  var hasCompleteDelta = open.isNotEmpty;
  final warnings = <WheelLeapsWarning>{};

  for (final position in open) {
    cost += position.grossEntryCost;
    final positionDelta = position.deltaEquivalentShares;
    if (positionDelta == null) {
      hasCompleteDelta = false;
      warnings.add(WheelLeapsWarning.deltaUnavailable);
    } else {
      delta += positionDelta;
    }
    if (position.currentMark == null) {
      warnings.add(WheelLeapsWarning.markUnavailable);
    }
    if (position.expirationAt.toUtc().difference(clock).inDays <= 180) {
      warnings.add(WheelLeapsWarning.expirationNear);
    }
  }
  for (final position in ours.where((p) => !p.isOpen)) {
    realized += position.realizedPnl ?? Decimal.zero;
  }
  if (open.isNotEmpty && wheel.hasOpenPosition) {
    warnings.add(WheelLeapsWarning.stackedDownside);
  }
  if (cost > wheel.cumulativeIncome) {
    warnings.add(WheelLeapsWarning.costNotCovered);
  }

  return WheelLeapsOverlay(
    wheel: wheel,
    positions: List.unmodifiable(ours),
    openPositions: List.unmodifiable(open),
    openLeapsCost: cost,
    realizedLeapsPnl: realized,
    deltaEquivalentShares: hasCompleteDelta ? delta : null,
    warnings: Set.unmodifiable(warnings),
  );
}
