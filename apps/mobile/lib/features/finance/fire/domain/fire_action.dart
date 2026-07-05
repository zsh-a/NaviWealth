import 'package:flutter/foundation.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

/// What the user should do next. Each `kind` is a stable, l10n-ready code —
/// the UI/AI render localised copy from the kind + structured params.
/// Keeping these as data (not strings) means the same suggestion can flow
/// through the AI tool catalog without leaking display text into the LLM.
enum FireActionKind {
  /// No FIRE plan yet — invite the user to set one.
  configurePlan,

  /// State is healthy; coast.
  holdSteady,

  /// Cash bucket below target — top it up by [FireAction.amount].
  topUpCashBucket,

  /// Withdrawal rate above SWR — reduce spending by [FireAction.amount]/mo
  /// (when present) or by [FireAction.pct].
  reduceSpending,

  /// Hold off on big discretionary spend (travel, upgrades) for now.
  delayDiscretionary,

  /// Allocation drift — rebalance toward the target weights.
  rebalance,

  /// The risk bucket is light — earmark more for medical / family / dream
  /// reserves.
  buildRiskReserve,

  /// Open the latest periodic review.
  runReview,

  /// FX rates are missing for some assets — capture them so totals are
  /// honest.
  fixCurrencyGap,
}

enum FireActionSeverity { info, warning, critical }

/// A single recommendation surfaced by the FIRE state engine.
///
/// Data only — no strings: the UI and AI both render the kind via the
/// localisation map. Carry the numbers the user needs to act on (amount in
/// base currency, months, percentages) as separate optional fields.
@immutable
class FireAction {
  const FireAction({
    required this.kind,
    required this.severity,
    this.amount,
    this.months,
    this.pct,
    this.note,
  });

  final FireActionKind kind;
  final FireActionSeverity severity;

  /// Optional monetary nudge (e.g. cash-bucket shortfall, monthly spend
  /// to trim). Currency matches the plan's base currency.
  final Money? amount;

  /// Optional duration in months (e.g. "you need 12 months of cash").
  final int? months;

  /// Optional fractional magnitude (e.g. drift percentage, surplus delta).
  final double? pct;

  /// Free-form annotation surfaced to the UI / AI. Optional — most actions
  /// rely on [kind] + structured params alone.
  final String? note;

  /// JSON shape used by AI tools and the diagnostics pane. Strings only;
  /// downstream consumers render localised copy from [kind].
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'severity': severity.name,
    if (amount != null) ...{
      'amount': amount!.amount.toString(),
      'currency': amount!.currency,
    },
    if (months != null) 'months': months,
    if (pct != null) 'pct': pct,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is FireAction &&
      other.kind == kind &&
      other.severity == severity &&
      other.amount == amount &&
      other.months == months &&
      other.pct == pct &&
      other.note == note;

  @override
  int get hashCode => Object.hash(kind, severity, amount, months, pct, note);
}
