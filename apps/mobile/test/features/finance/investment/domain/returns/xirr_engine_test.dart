import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';

XirrCashFlow cf(String iso, double amount) =>
    XirrCashFlow(date: DateTime.parse(iso), amount: amount);

/// Assert two doubles are equal within an absolute tolerance — XIRR rates
/// are decimals like 0.15, so 1e-6 absolute is "agrees to the basis point".
Matcher closeToD(double v, [double eps = 1e-6]) =>
    inInclusiveRange(v - eps, v + eps);

void main() {
  group('XirrEngine — solver convergence', () {
    test('Excel XIRR fixture: classic two-flow case', () {
      // Excel: =XIRR({-10000, 12000}, {2025-01-01, 2026-01-01}) = 0.20.
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -10000),
        cf('2026-01-01T00:00:00Z', 12000),
      ]);
      expect(solution, isA<XirrConverged>());
      expect((solution as XirrConverged).rate, closeToD(0.20));
    });

    test('Excel XIRR fixture: 5-flow textbook example', () {
      // Excel docs example:
      //   {-10000, 2750, 4250, 3250, 2750}
      //   {2008-01-01, 2008-03-01, 2008-10-30, 2009-02-15, 2009-04-01}
      //   = 0.373362535 (Excel 9 dp).
      final solution = const XirrEngine().compute([
        cf('2008-01-01T00:00:00Z', -10000),
        cf('2008-03-01T00:00:00Z', 2750),
        cf('2008-10-30T00:00:00Z', 4250),
        cf('2009-02-15T00:00:00Z', 3250),
        cf('2009-04-01T00:00:00Z', 2750),
      ]);
      expect(solution, isA<XirrConverged>());
      expect((solution as XirrConverged).rate, closeToD(0.37336253));
    });

    test('input order does not change result — engine sorts internally', () {
      const engine = XirrEngine();
      final ordered = engine.compute([
        cf('2025-01-01T00:00:00Z', -10000),
        cf('2025-07-01T00:00:00Z', 5000),
        cf('2026-01-01T00:00:00Z', 7000),
      ]);
      final shuffled = engine.compute([
        cf('2026-01-01T00:00:00Z', 7000),
        cf('2025-01-01T00:00:00Z', -10000),
        cf('2025-07-01T00:00:00Z', 5000),
      ]);
      expect(
        (shuffled as XirrConverged).rate,
        closeToD((ordered as XirrConverged).rate),
      );
    });

    test('half-year double-then-out: (1+r)^0.5 = 2 → r ≈ 3.0', () {
      // Invest 100, get back 200 six months later. Annualized rate solves
      // 100 = 200 / (1+r)^0.5 → r = 3 (since (1+3)^0.5 = 2).
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -100),
        cf('2025-07-02T12:00:00Z', 200), // ~365/2 days later
      ]);
      expect(solution, isA<XirrConverged>());
      // 365/2 = 182.5 days, exact mid-year. Use a slightly looser tolerance
      // because tradeDate granularity is microseconds, not exact half year.
      expect((solution as XirrConverged).rate, closeToD(3.0, 1e-3));
    });

    test('zero-return case: in == out at same value → rate = 0', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -1000),
        cf('2026-01-01T00:00:00Z', 1000),
      ]);
      expect((solution as XirrConverged).rate, closeToD(0.0));
    });

    test('negative XIRR: lost half over a year → r ≈ −0.5', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -1000),
        cf('2026-01-01T00:00:00Z', 500),
      ]);
      expect((solution as XirrConverged).rate, closeToD(-0.5));
    });

    test('hard case: deep negative (loss of 99%) — bisection territory', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -10000),
        cf('2026-01-01T00:00:00Z', 100), // lost 99% of capital
      ]);
      expect(solution, isA<XirrConverged>());
      expect((solution as XirrConverged).rate, closeToD(-0.99, 1e-4));
    });

    test('many small flows: 24 monthly contributions then a payout', () {
      // 24 monthly $100 deposits, then $3000 payout 1y after the last.
      final flows = <XirrCashFlow>[];
      var d = DateTime.utc(2024, 1, 1);
      for (var i = 0; i < 24; i++) {
        flows.add(XirrCashFlow(date: d, amount: -100));
        d = DateTime.utc(d.year, d.month + 1, 1);
      }
      flows.add(cf('2027-01-01T00:00:00Z', 3000));
      final solution = const XirrEngine().compute(flows);
      // Sanity: positive rate (got back $3000 on $2400 in over ~3 years).
      expect(solution, isA<XirrConverged>());
      expect((solution as XirrConverged).rate, greaterThan(0));
      expect(solution.rate, lessThan(1.0));
    });
  });

  group('XirrEngine — fallback behaviour', () {
    test('all-positive input falls back with cumulative absolute return', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', 100),
        cf('2025-06-01T00:00:00Z', 200),
      ]);
      expect(solution, isA<XirrFallbackAbsolute>());
      final fallback = solution as XirrFallbackAbsolute;
      expect(fallback.reason, 'all-positive');
      // No outflow → cumulative return is undefined.
      expect(fallback.absoluteReturn, isNull);
    });

    test('all-negative input falls back with `all-negative` reason', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -100),
        cf('2025-06-01T00:00:00Z', -200),
      ]);
      expect(solution, isA<XirrFallbackAbsolute>());
      expect((solution as XirrFallbackAbsolute).reason, 'all-negative');
    });

    test('single flow falls back with `too-few-flows`', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -100),
      ]);
      expect(solution, isA<XirrFallbackAbsolute>());
      expect((solution as XirrFallbackAbsolute).reason, 'too-few-flows');
    });

    test('empty flow list falls back with `too-few-flows`', () {
      final solution = const XirrEngine().compute(const []);
      expect(solution, isA<XirrFallbackAbsolute>());
      expect((solution as XirrFallbackAbsolute).reason, 'too-few-flows');
    });

    test('mixed signs but degenerate — all flows on same instant', () {
      // Same timestamp ⇒ years-from-t0 is 0 for every flow ⇒ NPV = sum of
      // amounts at any rate. Sum is non-zero (it's −10), so no rate
      // satisfies NPV=0 — solver bisection cannot find a sign change.
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -100),
        cf('2025-01-01T00:00:00Z', 90),
      ]);
      expect(solution, isA<XirrFallbackAbsolute>());
      final fallback = solution as XirrFallbackAbsolute;
      expect(fallback.reason, 'failed-to-converge');
      // Cumulative simple return = (90 − 100) / 100 = −0.1.
      expect(fallback.absoluteReturn, closeToD(-0.1));
    });

    test('absolute return is reported on fallback when outflow > 0', () {
      // Two −500 outflows + one +800 inflow on the same day → degenerate
      // (all instant ⇒ no convergence). Fallback yields cumulative return.
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -500),
        cf('2025-01-01T00:00:00Z', -500),
        cf('2025-01-01T00:00:00Z', 800),
      ]);
      expect(solution, isA<XirrFallbackAbsolute>());
      final fallback = solution as XirrFallbackAbsolute;
      // (800 − 1000) / 1000 = −0.2.
      expect(fallback.absoluteReturn, closeToD(-0.2));
    });
  });

  group('XirrEngine — solver internals', () {
    test('toString surfaces rate / iterations for converged result', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', -100),
        cf('2026-01-01T00:00:00Z', 110),
      ]);
      expect(solution.toString(), contains('XirrConverged'));
      expect((solution as XirrConverged).iterations, greaterThan(0));
    });

    test('toString surfaces reason for fallback result', () {
      final solution = const XirrEngine().compute([
        cf('2025-01-01T00:00:00Z', 100),
      ]);
      expect(solution.toString(), contains('too-few-flows'));
    });

    test('XirrCashFlow.toString includes the date and amount', () {
      final f = XirrCashFlow(date: DateTime.utc(2025, 6, 15), amount: -42.5);
      expect(f.toString(), contains('2025-06-15'));
      expect(f.toString(), contains('-42.5'));
    });

    test('forces bisection by capping Newton iterations to zero', () {
      // With maxNewtonIterations=0 the engine drops straight into bisection,
      // which still converges on a textbook two-flow case.
      const engine = XirrEngine(maxNewtonIterations: 0);
      final solution = engine.compute([
        cf('2025-01-01T00:00:00Z', -10000),
        cf('2026-01-01T00:00:00Z', 12000),
      ]);
      expect(solution, isA<XirrConverged>());
      expect((solution as XirrConverged).rate, closeToD(0.20, 1e-4));
    });

    test(
      'small mid-year buy + large terminal bookend never returns absurd rate',
      () {
        // Regression for the dashboard YTD overflow: a user with no
        // positions on Jan 1, a small mid-year purchase, and a much
        // larger terminal portfolio bookend used to make Newton spiral
        // into a numerically meaningless finite "converged" rate (e.g.
        // 1e150) — which then `* 100` for percent rendering blew the
        // home page hero past the screen by ~1500 px.
        //
        // The engine must either converge to a sane bounded rate **or**
        // fall back to absolute return — never return a finite rate
        // outside a few orders of magnitude of `bisectionHigh`.
        final solution = const XirrEngine().compute([
          cf('2026-04-01T00:00:00Z', -1000), // mid-year buy
          cf('2026-05-15T00:00:00Z', 32336), // terminal bookend
        ]);
        // Either path is acceptable; an absurd converged rate is not.
        switch (solution) {
          case XirrConverged(:final rate):
            expect(
              rate.abs(),
              lessThan(1e7),
              reason:
                  'Converged rate must stay within a few orders of '
                  'magnitude of bisectionHigh — got $rate',
            );
          case XirrFallbackAbsolute():
            // Falling back here is fine; the absoluteReturn is bounded
            // by the input magnitudes.
            break;
        }
      },
    );

    test('bisection gives up after maxBisectionIterations and falls back', () {
      // Newton off + bisection off → no converger; engine must fall back.
      // Use a pathological input that shouldn't even reach bisection (the
      // sign-change guard fires first), so we get the early fallback path.
      const engine = XirrEngine(
        maxNewtonIterations: 0,
        maxBisectionIterations: 0,
      );
      final solution = engine.compute([
        cf('2025-01-01T00:00:00Z', -100),
        cf('2026-01-01T00:00:00Z', 110),
      ]);
      // 0 bisection iters means the loop body never runs — engine drops to
      // the trailing fallback at the end of compute().
      expect(solution, isA<XirrFallbackAbsolute>());
      expect((solution as XirrFallbackAbsolute).reason, 'failed-to-converge');
    });
  });

  group('XirrEngine — performance', () {
    test('200 cash flows solve in well under 50ms', () {
      // Build 200 monthly contributions over ~16y plus a terminal payout.
      final flows = <XirrCashFlow>[];
      var d = DateTime.utc(2010, 1, 1);
      for (var i = 0; i < 199; i++) {
        flows.add(XirrCashFlow(date: d, amount: -250));
        d = DateTime.utc(d.year, d.month + 1, 1);
      }
      // Roughly 5% annualized → 250 * 199 ≈ 49,750 invested; double it.
      flows.add(XirrCashFlow(date: d, amount: 100000));

      final stopwatch = Stopwatch()..start();
      final solution = const XirrEngine().compute(flows);
      stopwatch.stop();

      expect(solution, isA<XirrConverged>());
      expect(
        stopwatch.elapsedMicroseconds,
        lessThan(50000),
        reason:
            'XIRR over 200 flows took ${stopwatch.elapsedMicroseconds}µs '
            '(budget: 50,000µs / 50ms).',
      );
    });
  });
}
