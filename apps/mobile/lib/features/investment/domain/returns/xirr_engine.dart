import 'dart:math' as math;

/// One dated, signed cash flow consumed by [XirrEngine].
///
/// Sign convention follows Excel `XIRR`: from the investor's perspective,
/// money paid out to acquire the position is **negative** (an outflow), money
/// received back is **positive** (an inflow). Bookend valuations follow the
/// same rule — the position value at the start of the window is added as a
/// negative bookend (we "begin invested"), the value at the end as a positive
/// bookend (we "could realize" that much by selling).
///
/// `amount` is a `double` because the numerical solver runs in floating
/// point — Decimal cash flows must be down-converted at the read-model
/// boundary. The 15-significant-digit precision of `double` is well
/// beyond the precision needed for an annualized rate
/// (which is, in the end, a percentage with maybe 4 significant figures).
class XirrCashFlow {
  const XirrCashFlow({required this.date, required this.amount});

  final DateTime date;
  final double amount;

  @override
  String toString() =>
      'XirrCashFlow(${date.toIso8601String().substring(0, 10)}, $amount)';
}

/// Outcome of an XIRR computation. Sealed so callers must explicitly handle
/// the success / fallback / undefined branches rather than papering over the
/// "no solution exists" case with a sentinel rate.
sealed class XirrSolution {
  const XirrSolution();
}

/// Solver converged to an annualized rate. [rate] is decimal (0.15 = 15%).
class XirrConverged extends XirrSolution {
  const XirrConverged({required this.rate, required this.iterations});

  final double rate;

  /// Number of solver iterations consumed (Newton + bisection combined). For
  /// observability — lets perf tests assert the solver is actually fast.
  final int iterations;

  @override
  String toString() => 'XirrConverged(rate=$rate, iter=$iterations)';
}

/// XIRR is undefined for the input (e.g. all flows have the same sign — no
/// rate satisfies NPV=0). [absoluteReturn] is the cumulative simple return
/// `Σ inflows / Σ |outflows|` so the UI can still show *something*.
///
/// `reason` is a machine-readable code (`'all-positive'`, `'all-negative'`,
/// `'too-few-flows'`, `'failed-to-converge'`) suitable for telemetry; pair it
/// with a localized string in the UI rather than rendering it directly.
class XirrFallbackAbsolute extends XirrSolution {
  const XirrFallbackAbsolute({
    required this.absoluteReturn,
    required this.reason,
  });

  /// Cumulative simple return. `null` when even the simple return is
  /// undefined (zero outflows).
  final double? absoluteReturn;
  final String reason;

  @override
  String toString() =>
      'XirrFallbackAbsolute(absReturn=$absoluteReturn, reason=$reason)';
}

/// Pure XIRR solver: Newton-Raphson with a bisection fallback that guarantees
/// convergence whenever a solution exists in `(-1, ∞)`.
///
/// The engine holds no state — call [compute] from any thread. Tunables
/// ([guess], [tolerance], [maxNewtonIterations], [bisectionLow],
/// [bisectionHigh], [maxBisectionIterations]) are exposed so tests can dial
/// up precision or reproduce a stuck-Newton case deterministically.
///
/// Day-counting follows Excel: an actual/365 calendar — `years = (date − t0).inMicroseconds /
/// (365 × 86400 × 1e6)`. This matches the textbook XIRR fixtures the unit
/// tests pin against.
class XirrEngine {
  const XirrEngine({
    this.guess = 0.1,
    this.tolerance = 1e-9,
    this.maxNewtonIterations = 100,
    this.bisectionLow = -0.999999,
    this.bisectionHigh = 1e6,
    this.maxBisectionIterations = 200,
  });

  /// Initial Newton seed. 10% is a reasonable default; callers with a strong
  /// prior (e.g. previous period's XIRR) can pass it in for faster convergence.
  final double guess;

  /// `|f(rate)| < tolerance` → converged.
  final double tolerance;

  final int maxNewtonIterations;

  /// Bisection search bounds. Lower is just above `-1` (NPV blows up at -1);
  /// upper is `1e6` so even a "10x in a day" position has a bracket. The
  /// solver only resorts to bisection when Newton has stalled, so the
  /// somewhat extravagant range is essentially free.
  final double bisectionLow;
  final double bisectionHigh;
  final int maxBisectionIterations;

  /// Compute the annualized internal rate of return for [flows].
  ///
  /// Returns:
  /// - [XirrConverged] on success.
  /// - [XirrFallbackAbsolute] when the input has fewer than two flows, all
  ///   flows share a sign, or both Newton and bisection fail to find a root.
  ///
  /// Input order does not matter — the engine sorts internally.
  XirrSolution compute(List<XirrCashFlow> flows) {
    if (flows.length < 2) {
      return XirrFallbackAbsolute(
        absoluteReturn: _absoluteReturn(flows),
        reason: 'too-few-flows',
      );
    }

    final sorted = [...flows]..sort((a, b) => a.date.compareTo(b.date));

    var hasInflow = false;
    var hasOutflow = false;
    for (final f in sorted) {
      if (f.amount > 0) hasInflow = true;
      if (f.amount < 0) hasOutflow = true;
    }
    if (!hasInflow || !hasOutflow) {
      return XirrFallbackAbsolute(
        absoluteReturn: _absoluteReturn(sorted),
        reason: hasInflow ? 'all-positive' : 'all-negative',
      );
    }

    final t0 = sorted.first.date;
    final years = List<double>.generate(
      sorted.length,
      (i) => _yearsBetween(t0, sorted[i].date),
      growable: false,
    );

    var iterations = 0;

    // ---- Newton-Raphson ----
    var rate = guess;
    for (var i = 0; i < maxNewtonIterations; i++) {
      iterations++;
      final f = _npv(sorted, years, rate);
      if (f.isNaN || f.isInfinite) break;
      if (f.abs() < tolerance) {
        return XirrConverged(rate: rate, iterations: iterations);
      }
      final fp = _dnpv(sorted, years, rate);
      if (fp == 0 || fp.isNaN || fp.isInfinite) break;
      var next = rate - f / fp;
      // Pin to (-1, ∞); rates ≤ -1 send (1+r)^t to a singular / complex
      // result and the iteration explodes.
      if (next <= -1) next = -0.999999;
      if ((next - rate).abs() < tolerance) {
        return XirrConverged(rate: next, iterations: iterations);
      }
      rate = next;
    }

    // ---- Bisection fallback ----
    var lo = bisectionLow;
    var hi = bisectionHigh;
    var npvLo = _npv(sorted, years, lo);
    var npvHi = _npv(sorted, years, hi);
    if (npvLo.isNaN || npvHi.isNaN || npvLo.sign == npvHi.sign) {
      return XirrFallbackAbsolute(
        absoluteReturn: _absoluteReturn(sorted),
        reason: 'failed-to-converge',
      );
    }

    for (var i = 0; i < maxBisectionIterations; i++) {
      iterations++;
      final mid = (lo + hi) / 2;
      final npvMid = _npv(sorted, years, mid);
      if (npvMid.isNaN) break;
      if (npvMid.abs() < tolerance || (hi - lo).abs() < tolerance) {
        return XirrConverged(rate: mid, iterations: iterations);
      }
      if (npvLo.sign != npvMid.sign) {
        hi = mid;
        npvHi = npvMid;
      } else {
        lo = mid;
        npvLo = npvMid;
      }
    }

    return XirrFallbackAbsolute(
      absoluteReturn: _absoluteReturn(sorted),
      reason: 'failed-to-converge',
    );
  }

  static double _npv(
    List<XirrCashFlow> flows,
    List<double> years,
    double rate,
  ) {
    final base = 1 + rate;
    var sum = 0.0;
    for (var i = 0; i < flows.length; i++) {
      sum += flows[i].amount / math.pow(base, years[i]);
    }
    return sum;
  }

  static double _dnpv(
    List<XirrCashFlow> flows,
    List<double> years,
    double rate,
  ) {
    final base = 1 + rate;
    var sum = 0.0;
    for (var i = 0; i < flows.length; i++) {
      sum += -years[i] * flows[i].amount / math.pow(base, years[i] + 1);
    }
    return sum;
  }

  /// Cumulative simple return: net P&L over absolute outflow paid in.
  /// Returns null when total outflow is zero (return is mathematically
  /// undefined — and the UI must render "—" rather than ∞).
  static double? _absoluteReturn(Iterable<XirrCashFlow> flows) {
    var inflow = 0.0;
    var outflow = 0.0;
    for (final f in flows) {
      if (f.amount > 0) inflow += f.amount;
      if (f.amount < 0) outflow += -f.amount;
    }
    if (outflow == 0) return null;
    return (inflow - outflow) / outflow;
  }

  /// Excel-compatible day count: actual days / 365.
  static double _yearsBetween(DateTime a, DateTime b) {
    const microsecondsPerYear = 365.0 * 86400.0 * 1e6;
    return b.difference(a).inMicroseconds / microsecondsPerYear;
  }
}
