import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';

/// User's stance on options income strategies.
///
/// Maps to the `options_strategy_profile` synced Drift table (one row per
/// `ownerUserId`). The profile drives every hard filter and soft score in
/// the scanner — see `docs/options-income.md` §7. The `mode` field acts as
/// a preset that pre-fills the delta / DTE / yield ranges; advanced users
/// can later override individual fields without changing the mode label.
class OptionsStrategyProfile {
  const OptionsStrategyProfile({
    required this.mode,
    required this.allowedStrategies,
    required this.minDte,
    required this.maxDte,
    required this.deltaPutMin,
    required this.deltaPutMax,
    required this.deltaCallMin,
    required this.deltaCallMax,
    required this.maxCapitalPerTradePct,
    required this.maxUnderlyingExposurePct,
    required this.minAnnualizedYield,
    required this.minOpenInterest,
    required this.minVolume,
    required this.maxBidAskSpreadPct,
    required this.avoidEarnings,
    required this.avoidMacroEvents,
    required this.onlyOnApprovedUnderlyings,
    required this.riskDisclosureAckAt,
    required this.sync,
  });

  final OptionsStrategyMode mode;
  final Set<OptionsStrategyKind> allowedStrategies;

  // Inclusive DTE range. Days-to-expiration outside this window is a hard
  // reject.
  final int minDte;
  final int maxDte;

  // Delta bounds for cash-secured puts. Values are negative because put
  // deltas are negative. `min` is the more-negative end (further OTM is
  // closer to 0, ATM is closer to -0.5), `max` is the closer-to-zero end.
  final Decimal deltaPutMin;
  final Decimal deltaPutMax;

  // Delta bounds for covered calls. Positive values.
  final Decimal deltaCallMin;
  final Decimal deltaCallMax;

  /// Max share of `availableCashForOptions` a single sell-put can occupy.
  /// Stored as a 0..1 decimal (e.g. `0.10` = 10%).
  final Decimal maxCapitalPerTradePct;

  /// Max share of total net worth a single underlying can occupy post-
  /// assignment. 0..1 decimal.
  final Decimal maxUnderlyingExposurePct;

  /// Annualized return floor (0..1 decimal, e.g. `0.08` = 8%).
  final Decimal minAnnualizedYield;

  final int minOpenInterest;
  final int minVolume;

  /// Max bid/ask spread as fraction of mid (0..1).
  final Decimal maxBidAskSpreadPct;

  final bool avoidEarnings;
  final bool avoidMacroEvents;
  final bool onlyOnApprovedUnderlyings;

  /// OCC ODD acknowledgement timestamp. `null` until the user reads and
  /// confirms the disclosure — gate-keeps the scanner UI.
  final DateTime? riskDisclosureAckAt;

  final SyncMeta sync;

  bool get hasAcknowledgedRiskDisclosure => riskDisclosureAckAt != null;

  OptionsStrategyProfile copyWith({
    OptionsStrategyMode? mode,
    Set<OptionsStrategyKind>? allowedStrategies,
    int? minDte,
    int? maxDte,
    Decimal? deltaPutMin,
    Decimal? deltaPutMax,
    Decimal? deltaCallMin,
    Decimal? deltaCallMax,
    Decimal? maxCapitalPerTradePct,
    Decimal? maxUnderlyingExposurePct,
    Decimal? minAnnualizedYield,
    int? minOpenInterest,
    int? minVolume,
    Decimal? maxBidAskSpreadPct,
    bool? avoidEarnings,
    bool? avoidMacroEvents,
    bool? onlyOnApprovedUnderlyings,
    DateTime? riskDisclosureAckAt,
    SyncMeta? sync,
  }) {
    return OptionsStrategyProfile(
      mode: mode ?? this.mode,
      allowedStrategies: allowedStrategies ?? this.allowedStrategies,
      minDte: minDte ?? this.minDte,
      maxDte: maxDte ?? this.maxDte,
      deltaPutMin: deltaPutMin ?? this.deltaPutMin,
      deltaPutMax: deltaPutMax ?? this.deltaPutMax,
      deltaCallMin: deltaCallMin ?? this.deltaCallMin,
      deltaCallMax: deltaCallMax ?? this.deltaCallMax,
      maxCapitalPerTradePct:
          maxCapitalPerTradePct ?? this.maxCapitalPerTradePct,
      maxUnderlyingExposurePct:
          maxUnderlyingExposurePct ?? this.maxUnderlyingExposurePct,
      minAnnualizedYield: minAnnualizedYield ?? this.minAnnualizedYield,
      minOpenInterest: minOpenInterest ?? this.minOpenInterest,
      minVolume: minVolume ?? this.minVolume,
      maxBidAskSpreadPct: maxBidAskSpreadPct ?? this.maxBidAskSpreadPct,
      avoidEarnings: avoidEarnings ?? this.avoidEarnings,
      avoidMacroEvents: avoidMacroEvents ?? this.avoidMacroEvents,
      onlyOnApprovedUnderlyings:
          onlyOnApprovedUnderlyings ?? this.onlyOnApprovedUnderlyings,
      riskDisclosureAckAt: riskDisclosureAckAt ?? this.riskDisclosureAckAt,
      sync: sync ?? this.sync,
    );
  }
}

/// Preset stance. Picking a mode pre-fills the delta / DTE / yield ranges;
/// users on Custom keep whatever they edited.
enum OptionsStrategyMode { conservative, balanced, aggressive, custom }

extension OptionsStrategyModeWire on OptionsStrategyMode {
  String get wire => name;
}

OptionsStrategyMode parseOptionsStrategyMode(String? wire) {
  switch (wire) {
    case 'conservative':
      return OptionsStrategyMode.conservative;
    case 'balanced':
      return OptionsStrategyMode.balanced;
    case 'aggressive':
      return OptionsStrategyMode.aggressive;
    case 'custom':
      return OptionsStrategyMode.custom;
    default:
      return OptionsStrategyMode.balanced;
  }
}

/// Which Income Planner strategy a candidate belongs to. Used both on the
/// profile (which strategies the user enables) and on individual scan
/// results.
enum OptionsStrategyKind { cashSecuredPut, coveredCall }

extension OptionsStrategyKindWire on OptionsStrategyKind {
  String get wire => switch (this) {
    OptionsStrategyKind.cashSecuredPut => 'cash_secured_put',
    OptionsStrategyKind.coveredCall => 'covered_call',
  };
}

OptionsStrategyKind? parseOptionsStrategyKind(String wire) {
  switch (wire) {
    case 'cash_secured_put':
      return OptionsStrategyKind.cashSecuredPut;
    case 'covered_call':
      return OptionsStrategyKind.coveredCall;
  }
  return null;
}

/// Placeholder sync metadata for draft profiles that have not yet been
/// persisted. The repository's `upsert` re-stamps sync on every write, so
/// this never reaches the database — it just satisfies the constructor's
/// `required` contract.
SyncMeta _draftSyncMeta() => SyncMeta(
  ownerUserId: '',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedByDevice: '',
  hlc: Hlc.zero(''),
);

/// Preset values for each mode. Mirrors the design doc §5.1 ranges. Custom
/// mode reuses the balanced preset as a starting point — the user edits
/// from there.
///
/// The returned profile carries a placeholder [SyncMeta]; the repository
/// stamps the real metadata when it persists.
OptionsStrategyProfile defaultProfileForMode(OptionsStrategyMode mode) {
  final sync = _draftSyncMeta();
  switch (mode) {
    case OptionsStrategyMode.conservative:
      return OptionsStrategyProfile(
        mode: mode,
        allowedStrategies: const {
          OptionsStrategyKind.cashSecuredPut,
          OptionsStrategyKind.coveredCall,
        },
        minDte: 21,
        maxDte: 45,
        deltaPutMin: Decimal.parse('-0.20'),
        deltaPutMax: Decimal.parse('-0.10'),
        deltaCallMin: Decimal.parse('0.10'),
        deltaCallMax: Decimal.parse('0.20'),
        maxCapitalPerTradePct: Decimal.parse('0.10'),
        maxUnderlyingExposurePct: Decimal.parse('0.15'),
        minAnnualizedYield: Decimal.parse('0.08'),
        minOpenInterest: 200,
        minVolume: 25,
        maxBidAskSpreadPct: Decimal.parse('0.08'),
        avoidEarnings: true,
        avoidMacroEvents: true,
        onlyOnApprovedUnderlyings: true,
        riskDisclosureAckAt: null,
        sync: sync,
      );
    case OptionsStrategyMode.balanced:
    case OptionsStrategyMode.custom:
      return OptionsStrategyProfile(
        mode: mode,
        allowedStrategies: const {
          OptionsStrategyKind.cashSecuredPut,
          OptionsStrategyKind.coveredCall,
        },
        minDte: 21,
        maxDte: 45,
        deltaPutMin: Decimal.parse('-0.30'),
        deltaPutMax: Decimal.parse('-0.15'),
        deltaCallMin: Decimal.parse('0.15'),
        deltaCallMax: Decimal.parse('0.30'),
        maxCapitalPerTradePct: Decimal.parse('0.15'),
        maxUnderlyingExposurePct: Decimal.parse('0.20'),
        minAnnualizedYield: Decimal.parse('0.12'),
        minOpenInterest: 100,
        minVolume: 10,
        maxBidAskSpreadPct: Decimal.parse('0.12'),
        avoidEarnings: true,
        avoidMacroEvents: true,
        onlyOnApprovedUnderlyings: true,
        riskDisclosureAckAt: null,
        sync: sync,
      );
    case OptionsStrategyMode.aggressive:
      return OptionsStrategyProfile(
        mode: mode,
        allowedStrategies: const {
          OptionsStrategyKind.cashSecuredPut,
          OptionsStrategyKind.coveredCall,
        },
        minDte: 7,
        maxDte: 45,
        deltaPutMin: Decimal.parse('-0.40'),
        deltaPutMax: Decimal.parse('-0.20'),
        deltaCallMin: Decimal.parse('0.20'),
        deltaCallMax: Decimal.parse('0.40'),
        maxCapitalPerTradePct: Decimal.parse('0.20'),
        maxUnderlyingExposurePct: Decimal.parse('0.25'),
        minAnnualizedYield: Decimal.parse('0.18'),
        minOpenInterest: 50,
        minVolume: 5,
        maxBidAskSpreadPct: Decimal.parse('0.15'),
        avoidEarnings: false,
        avoidMacroEvents: false,
        onlyOnApprovedUnderlyings: true,
        riskDisclosureAckAt: null,
        sync: sync,
      );
  }
}
