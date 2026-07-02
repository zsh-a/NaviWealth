import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

/// Outstanding-balance lookup for liabilities at a given historical date.
///
/// The Finance dashboard trend builder calls [balancesOn] once per sample
/// point, sums each returned [LiabilityBalance] after FX conversion to the
/// base currency, and subtracts the total from gross assets.
abstract class LiabilityBalanceSource {
  /// Iterable of liability balances effective at [on]. The "effective"
  /// rule: walk the amortization schedule and pick the entry with the
  /// largest `dueDate <= on`; that entry's `remainingBalance` is the
  /// outstanding principal at [on]. Liabilities that have not yet started
  /// (`startDate > on`) and liabilities whose schedule has been fully paid
  /// down to zero before [on] are omitted.
  Iterable<LiabilityBalance> balancesOn(DateTime on);
}

/// Outstanding principal for a single liability at a snapshot date.
class LiabilityBalance {
  LiabilityBalance({required this.liabilityId, required this.outstanding});

  final String liabilityId;
  final Money outstanding;
}

/// One row of an amortization schedule used by [LiabilitySnapshot].
class AmortizationPoint {
  AmortizationPoint({required DateTime dueDate, required this.remainingBalance})
    : dueDate = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);

  final DateTime dueDate;
  final Decimal remainingBalance;
}

/// Snapshot of a liability and its amortization schedule. The service does
/// not need the full [Liability] domain object — only the fields required
/// to compute outstanding balance over time.
class LiabilitySnapshot {
  LiabilitySnapshot({
    required this.id,
    required this.currency,
    required this.initialPrincipal,
    required this.startDate,
    required Iterable<AmortizationPoint> schedule,
  }) : schedule = schedule.toList()
         ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  final String id;
  final String currency;
  final Decimal initialPrincipal;
  final DateTime startDate;
  final List<AmortizationPoint> schedule;
}

/// In-memory [LiabilityBalanceSource] driven by a list of [LiabilitySnapshot]s.
class AmortizationLiabilitySource implements LiabilityBalanceSource {
  AmortizationLiabilitySource(Iterable<LiabilitySnapshot> snapshots)
    : _snapshots = snapshots.toList();

  final List<LiabilitySnapshot> _snapshots;

  @override
  Iterable<LiabilityBalance> balancesOn(DateTime on) sync* {
    final cutoff = DateTime.utc(on.year, on.month, on.day);
    for (final snap in _snapshots) {
      if (snap.startDate.isAfter(cutoff)) continue;
      final balance = _outstandingAt(snap, cutoff);
      if (balance.sign <= 0) continue;
      yield LiabilityBalance(
        liabilityId: snap.id,
        outstanding: Money(balance, snap.currency),
      );
    }
  }

  static Decimal _outstandingAt(LiabilitySnapshot snap, DateTime cutoff) {
    if (snap.schedule.isEmpty) return snap.initialPrincipal;
    // Largest dueDate <= cutoff.
    var lo = 0;
    var hi = snap.schedule.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!snap.schedule[mid].dueDate.isAfter(cutoff)) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return snap.initialPrincipal;
    return snap.schedule[found].remainingBalance;
  }
}
