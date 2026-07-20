import 'package:decimal/decimal.dart';

import 'dividend_center.dart';

/// How severely cash dividends have deteriorated for one held asset.
enum DividendDeteriorationSeverity { warning, critical }

/// One held asset whose trailing dividends fell past user-facing thresholds.
class DividendDeterioration {
  const DividendDeterioration({
    required this.assetId,
    required this.assetLabel,
    required this.ttmGrossInBase,
    required this.priorTtmGrossInBase,
    required this.dropRatio,
    required this.severity,
  });

  final String assetId;
  final String assetLabel;
  final Decimal ttmGrossInBase;
  final Decimal priorTtmGrossInBase;

  /// Fraction of prior TTM lost: `1 - ttm/prior`. `1.0` means fully cancelled
  /// relative to the prior window.
  final double dropRatio;
  final DividendDeteriorationSeverity severity;
}

/// Deterministic recorded-dividend-income guardrail over
/// [DividendCenterEvent] history.
///
/// Compares trailing twelve months (TTM) cash dividends to the previous TTM
/// window for each asset. Only currently held assets (when [heldAssetIds] is
/// provided) are evaluated, so sold names do not keep firing inbox signals.
///
/// Because the ledger amount can also change with position size and FX, this
/// is intentionally an income-deterioration signal rather than a claim that
/// the issuer changed its per-share dividend policy. The resilience report
/// performs the evidence-bounded attribution when enough source data exists.
class DividendPolicyMonitor {
  const DividendPolicyMonitor({
    this.warningDropRatio = 0.20,
    this.criticalDropRatio = 0.50,
  });

  /// Drop of at least this fraction of prior TTM → warning (default 20%).
  final double warningDropRatio;

  /// Drop of at least this fraction → critical (default 50%), including full
  /// cancellation when current TTM is zero after a non-zero prior TTM.
  final double criticalDropRatio;

  List<DividendDeterioration> detect({
    required Iterable<DividendCenterEvent> events,
    required DateTime now,
    Set<String>? heldAssetIds,
  }) {
    final nowUtc = now.toUtc();
    final ttmStart = _sameCalendarDay(nowUtc, nowUtc.year - 1);
    final priorTtmStart = _sameCalendarDay(nowUtc, nowUtc.year - 2);

    final byAsset = <String, _AssetWindows>{};
    for (final event in events) {
      if (event.assetId == 'unattributed') continue;
      if (heldAssetIds != null && !heldAssetIds.contains(event.assetId)) {
        continue;
      }
      final date = event.event.date.toUtc();
      final acc = byAsset.putIfAbsent(
        event.assetId,
        () =>
            _AssetWindows(assetId: event.assetId, assetLabel: event.assetLabel),
      );
      // Prefer the latest known label.
      acc.assetLabel = event.assetLabel;
      if (!date.isBefore(ttmStart) && !date.isAfter(nowUtc)) {
        acc.ttm += event.grossInBase;
      } else if (!date.isBefore(priorTtmStart) && date.isBefore(ttmStart)) {
        acc.priorTtm += event.grossInBase;
      }
    }

    final results = <DividendDeterioration>[];
    for (final acc in byAsset.values) {
      if (acc.priorTtm <= Decimal.zero) continue;
      final prior = acc.priorTtm.toDouble();
      final current = acc.ttm.toDouble();
      final dropRatio = prior <= 0
          ? 0.0
          : (1.0 - (current / prior)).clamp(0.0, 1.0);
      if (dropRatio < warningDropRatio) continue;

      final severity = dropRatio >= criticalDropRatio
          ? DividendDeteriorationSeverity.critical
          : DividendDeteriorationSeverity.warning;
      results.add(
        DividendDeterioration(
          assetId: acc.assetId,
          assetLabel: acc.assetLabel,
          ttmGrossInBase: acc.ttm,
          priorTtmGrossInBase: acc.priorTtm,
          dropRatio: dropRatio,
          severity: severity,
        ),
      );
    }

    results.sort((a, b) {
      final sev = b.severity.index.compareTo(a.severity.index);
      if (sev != 0) return sev;
      return b.dropRatio.compareTo(a.dropRatio);
    });
    return List.unmodifiable(results);
  }
}

DateTime _sameCalendarDay(DateTime value, int year) {
  final lastDay = DateTime.utc(year, value.month + 1, 0).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return DateTime.utc(year, value.month, day);
}

class _AssetWindows {
  _AssetWindows({required this.assetId, required this.assetLabel});

  final String assetId;
  String assetLabel;
  Decimal ttm = Decimal.zero;
  Decimal priorTtm = Decimal.zero;
}
