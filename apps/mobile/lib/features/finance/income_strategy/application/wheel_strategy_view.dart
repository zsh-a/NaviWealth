import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

import 'leaps_income_sleeve_adapter.dart';
import 'wheel_income_sleeve_adapter.dart';

/// One Wheel leg inside a strategy group: the member underlying plus its
/// lifecycle state machine.
class WheelCycleLeg {
  const WheelCycleLeg({required this.underlying, required this.lifecycle});

  final UnderlyingIncomeStrategySnapshot underlying;
  final WheelLifecycle lifecycle;
}

/// Wheel drill-down projected from the generic income strategy snapshot,
/// one view per strategy group.
///
/// An implicit singleton group reproduces the old per-underlying pairing;
/// an explicit group may pair legs across underlyings (wheel on TQQQ
/// funding a LEAPS call on QQQ). This stays a projection — no second
/// composition engine and no special Wheel+LEAPS source of truth.
class WheelStrategyView {
  const WheelStrategyView({
    required this.group,
    required this.wheels,
    required this.positions,
  });

  final IncomeStrategyGroupSnapshot group;

  /// Wheel legs in group order. Never empty: a LEAPS-only group carries a
  /// synthesized empty lifecycle so the UI keeps one stable shape.
  final List<WheelCycleLeg> wheels;

  /// LEAPS positions across every group member.
  final List<LeapsCallPosition> positions;

  String get label => group.label;

  /// Primary wheel leg. Views are sorted so the leg with open positions
  /// leads; single-underlying groups have exactly one leg.
  WheelLifecycle get wheel => wheels.first.lifecycle;

  List<LeapsCallPosition> get openPositions =>
      positions.where((position) => position.isOpen).toList(growable: false);

  Iterable<IncomeStrategySleeveSnapshot> get _leapsSleeves sync* {
    for (final member in group.members) {
      final sleeve = member.sleeves[IncomeStrategySleeveKind.leapsCall];
      if (sleeve != null) yield sleeve;
    }
  }

  Decimal get openLeapsCost {
    var total = Decimal.zero;
    for (final sleeve in _leapsSleeves) {
      total += sleeve.capitalAtRisk.value.amount;
    }
    return total;
  }

  Decimal get realizedLeapsPnl {
    var total = Decimal.zero;
    for (final sleeve in _leapsSleeves) {
      total += sleeve.realizedResult.value.amount;
    }
    return total;
  }

  /// Combined realized result across the whole group (base currency).
  Decimal get realizedResult => group.realizedResult.value.amount;

  /// Delta-equivalent shares only merge within one underlying — a QQQ
  /// delta is not a TQQQ share count, so cross-asset groups report null
  /// and the UI shows per-leg values instead.
  Decimal? get deltaEquivalentShares {
    final sleeves = _leapsSleeves.toList(growable: false);
    if (sleeves.length != 1) return null;
    return sleeves.single.deltaEquivalentShares;
  }

  /// Group-scope findings plus every member's own findings.
  List<IncomeStrategyRisk> get risks => List.unmodifiable([
    ...group.risks,
    for (final member in group.members) ...member.risks,
  ]);

  /// Wheel income (all legs, native currency) over open LEAPS cost.
  /// Null when legs disagree on currency — no silent FX guessing.
  Decimal? get wheelIncomeCoverageRatio {
    final cost = openLeapsCost;
    if (cost == Decimal.zero) return null;
    final currencies = wheels.map((leg) => leg.lifecycle.currency).toSet();
    if (currencies.length != 1) return null;
    var income = Decimal.zero;
    for (final leg in wheels) {
      income += leg.lifecycle.cumulativeIncome;
    }
    return (income / cost).toDecimal(scaleOnInfinitePrecision: 8);
  }
}

List<WheelStrategyView> buildWheelStrategyViews(
  PortfolioIncomeStrategySnapshot portfolio,
) {
  final views = <WheelStrategyView>[];
  for (final group in portfolio.groups) {
    final wheels = <WheelCycleLeg>[];
    final positions = <LeapsCallPosition>[];
    var hasAnySleeve = false;
    for (final member in group.members) {
      final wheelSnapshot = member.sleeves[IncomeStrategySleeveKind.wheel];
      final leapsSnapshot = member.sleeves[IncomeStrategySleeveKind.leapsCall];
      if (wheelSnapshot != null || leapsSnapshot != null) hasAnySleeve = true;
      final wheelDetails = wheelSnapshot?.details;
      if (wheelDetails is WheelIncomeSleeveDetails) {
        wheels.add(
          WheelCycleLeg(underlying: member, lifecycle: wheelDetails.lifecycle),
        );
      }
      final leapsDetails = leapsSnapshot?.details;
      if (leapsDetails is LeapsIncomeSleeveDetails) {
        positions.addAll(leapsDetails.positions);
      }
    }
    if (!hasAnySleeve) continue;
    if (wheels.isEmpty) {
      final anchor = group.members.first;
      wheels.add(
        WheelCycleLeg(
          underlying: anchor,
          lifecycle: WheelLifecycle.empty(
            symbol: anchor.asset.symbol,
            currency: anchor.asset.currency,
          ),
        ),
      );
    }
    wheels.sort((a, b) {
      if (a.lifecycle.hasOpenPosition != b.lifecycle.hasOpenPosition) {
        return a.lifecycle.hasOpenPosition ? -1 : 1;
      }
      return a.lifecycle.symbol.compareTo(b.lifecycle.symbol);
    });
    views.add(
      WheelStrategyView(
        group: group,
        wheels: List.unmodifiable(wheels),
        positions: List.unmodifiable(positions),
      ),
    );
  }
  views.sort((a, b) {
    final aOpen =
        a.wheels.any((leg) => leg.lifecycle.hasOpenPosition) ||
        a.openPositions.isNotEmpty;
    final bOpen =
        b.wheels.any((leg) => leg.lifecycle.hasOpenPosition) ||
        b.openPositions.isNotEmpty;
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    return a.label.compareTo(b.label);
  });
  return List.unmodifiable(views);
}
