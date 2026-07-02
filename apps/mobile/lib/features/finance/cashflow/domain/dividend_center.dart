import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'cash_flow_event.dart';

typedef DividendAmountConverter =
    Decimal? Function(Decimal amount, String currency, DateTime date);

@immutable
class DividendCenterEvent {
  const DividendCenterEvent({
    required this.event,
    required this.assetId,
    required this.assetLabel,
    required this.withholdingInBase,
    required this.withholdingOriginal,
    required this.withholdingCurrency,
  });

  final CashFlowEvent event;
  final String assetId;
  final String assetLabel;
  final Decimal withholdingInBase;
  final Decimal withholdingOriginal;
  final String withholdingCurrency;

  Decimal get netInBase => event.signedAmount;
  Decimal get grossInBase => event.signedAmount + withholdingInBase;
}

@immutable
class DividendHoldingRank {
  const DividendHoldingRank({
    required this.assetId,
    required this.assetLabel,
    required this.ttmGrossInBase,
    required this.withholdingInBase,
    required this.portfolioShare,
    required this.yieldOnCost,
  });

  final String assetId;
  final String assetLabel;
  final Decimal ttmGrossInBase;
  final Decimal withholdingInBase;
  final double portfolioShare;
  final double? yieldOnCost;
}

@immutable
class DividendMonthGroup {
  const DividendMonthGroup({
    required this.month,
    required this.events,
    required this.grossInBase,
    required this.withholdingInBase,
  });

  final DateTime month;
  final List<DividendCenterEvent> events;
  final Decimal grossInBase;
  final Decimal withholdingInBase;
}

@immutable
class DividendCenterSnapshot {
  const DividendCenterSnapshot({
    required this.baseCurrency,
    required this.yearToDateGross,
    required this.ttmGross,
    required this.priorYearToDateGross,
    required this.ttmWithholding,
    required this.events,
    required this.ranking,
    required this.months,
  });

  final String baseCurrency;
  final Decimal yearToDateGross;
  final Decimal ttmGross;
  final Decimal priorYearToDateGross;
  final Decimal ttmWithholding;
  final List<DividendCenterEvent> events;
  final List<DividendHoldingRank> ranking;
  final List<DividendMonthGroup> months;

  Decimal get yearOverYearDelta => yearToDateGross - priorYearToDateGross;

  double? get yearOverYearRatio {
    if (priorYearToDateGross == Decimal.zero) return null;
    return (yearOverYearDelta / priorYearToDateGross)
        .toDecimal(scaleOnInfinitePrecision: 8)
        .toDouble();
  }

  bool get isEmpty => events.isEmpty;
}

DividendCenterSnapshot buildDividendCenterSnapshot({
  required Iterable<CashFlowEvent> dividendEvents,
  required Map<String, JournalEntryWithPostings> entriesById,
  required Map<String, Account> accountsById,
  required Map<String, HoldingSnapshot> holdings,
  required String baseCurrency,
  required DateTime now,
  DividendAmountConverter? convertToBaseAmount,
}) {
  final enriched = <DividendCenterEvent>[];
  for (final event in dividendEvents) {
    final source = entriesById[event.journalEntryId];
    final assetId = source == null
        ? null
        : _assetIdFromTags(source.entry.tagIds);
    final withholding = source == null
        ? _Withholding.zero()
        : _withholdingFor(
            source,
            accountsById: accountsById,
            baseCurrency: baseCurrency,
            convertToBaseAmount: convertToBaseAmount,
          );
    final resolvedAssetId = assetId ?? 'unattributed';
    enriched.add(
      DividendCenterEvent(
        event: event,
        assetId: resolvedAssetId,
        assetLabel: _assetLabel(resolvedAssetId),
        withholdingInBase: withholding.inBase,
        withholdingOriginal: withholding.original,
        withholdingCurrency: withholding.currency,
      ),
    );
  }

  enriched.sort((a, b) => b.event.date.compareTo(a.event.date));

  final startOfYear = DateTime.utc(now.year);
  final priorStart = DateTime.utc(now.year - 1);
  final priorEnd = DateTime.utc(now.year - 1, now.month, now.day, 23, 59, 59);
  final ttmStart = DateTime.utc(now.year - 1, now.month, now.day);
  final ttmEvents = enriched.where(
    (e) => !_isBeforeUtc(e.event.date, ttmStart),
  );
  final ytdEvents = enriched.where(
    (e) => !_isBeforeUtc(e.event.date, startOfYear),
  );
  final priorYtdEvents = enriched.where((e) {
    final date = e.event.date.toUtc();
    return !date.isBefore(priorStart) && !date.isAfter(priorEnd);
  });

  final ttmGross = _sum(ttmEvents.map((e) => e.grossInBase));
  final ranking = _buildRanking(
    events: ttmEvents.toList(),
    holdings: holdings,
    ttmGross: ttmGross,
  );

  return DividendCenterSnapshot(
    baseCurrency: baseCurrency,
    yearToDateGross: _sum(ytdEvents.map((e) => e.grossInBase)),
    ttmGross: ttmGross,
    priorYearToDateGross: _sum(priorYtdEvents.map((e) => e.grossInBase)),
    ttmWithholding: _sum(ttmEvents.map((e) => e.withholdingInBase)),
    events: List.unmodifiable(enriched),
    ranking: List.unmodifiable(ranking),
    months: List.unmodifiable(_buildMonths(enriched)),
  );
}

List<DividendHoldingRank> _buildRanking({
  required List<DividendCenterEvent> events,
  required Map<String, HoldingSnapshot> holdings,
  required Decimal ttmGross,
}) {
  final byAsset = <String, _RankAcc>{};
  for (final event in events) {
    final acc = byAsset.putIfAbsent(
      event.assetId,
      () => _RankAcc(assetId: event.assetId, assetLabel: event.assetLabel),
    );
    acc.gross += event.grossInBase;
    acc.withholding += event.withholdingInBase;
  }

  final rows = byAsset.values.map((acc) {
    final costBasis = holdings[acc.assetId]?.costBasisInBase;
    final yieldOnCost = costBasis == null || costBasis <= Decimal.zero
        ? null
        : (acc.gross / costBasis)
              .toDecimal(scaleOnInfinitePrecision: 8)
              .toDouble();
    final share = ttmGross == Decimal.zero
        ? 0.0
        : (acc.gross / ttmGross)
              .toDecimal(scaleOnInfinitePrecision: 8)
              .toDouble();
    return DividendHoldingRank(
      assetId: acc.assetId,
      assetLabel: acc.assetLabel,
      ttmGrossInBase: acc.gross,
      withholdingInBase: acc.withholding,
      portfolioShare: share,
      yieldOnCost: yieldOnCost,
    );
  }).toList()..sort((a, b) => b.ttmGrossInBase.compareTo(a.ttmGrossInBase));
  return rows;
}

List<DividendMonthGroup> _buildMonths(List<DividendCenterEvent> events) {
  final byMonth = <DateTime, List<DividendCenterEvent>>{};
  for (final event in events) {
    final date = event.event.date.toUtc();
    final month = DateTime.utc(date.year, date.month);
    byMonth.putIfAbsent(month, () => <DividendCenterEvent>[]).add(event);
  }
  final months = byMonth.entries.map((entry) {
    final rows = entry.value
      ..sort((a, b) => b.event.date.compareTo(a.event.date));
    return DividendMonthGroup(
      month: entry.key,
      events: List.unmodifiable(rows),
      grossInBase: _sum(rows.map((e) => e.grossInBase)),
      withholdingInBase: _sum(rows.map((e) => e.withholdingInBase)),
    );
  }).toList()..sort((a, b) => b.month.compareTo(a.month));
  return months;
}

_Withholding _withholdingFor(
  JournalEntryWithPostings entry, {
  required Map<String, Account> accountsById,
  required String baseCurrency,
  DividendAmountConverter? convertToBaseAmount,
}) {
  var original = Decimal.zero;
  var inBase = Decimal.zero;
  String? currency;
  for (final posting in entry.postings) {
    final account = accountsById[posting.accountId];
    if (account == null || !_isWithholdingAccount(account)) continue;
    original += posting.units.abs();
    currency ??= posting.unit.trim().toUpperCase();
    final postingCurrency = posting.unit.trim().toUpperCase();
    if (postingCurrency == baseCurrency) {
      inBase += posting.units.abs();
    } else {
      final converted = convertToBaseAmount?.call(
        posting.units.abs(),
        postingCurrency,
        entry.entry.date,
      );
      if (converted != null) inBase += converted;
    }
  }
  return _Withholding(
    original: original,
    inBase: inBase,
    currency: currency ?? baseCurrency,
  );
}

bool _isWithholdingAccount(Account account) {
  if (account.category != AccountSide.expense) return false;
  final token = '${account.id} ${account.name}'.toLowerCase();
  return token.contains('withholding') || token.contains('tax');
}

String? _assetIdFromTags(List<String> tagIds) {
  for (final tag in tagIds) {
    if (tag.startsWith('asset:') && tag.length > 'asset:'.length) {
      return tag.substring('asset:'.length);
    }
  }
  return null;
}

String _assetLabel(String assetId) {
  if (assetId == 'unattributed') return 'Unattributed';
  final colon = assetId.indexOf(':');
  return colon < 0 ? assetId : assetId.substring(colon + 1);
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}

bool _isBeforeUtc(DateTime date, DateTime floor) =>
    date.toUtc().isBefore(floor);

class _RankAcc {
  _RankAcc({required this.assetId, required this.assetLabel});

  final String assetId;
  final String assetLabel;
  Decimal gross = Decimal.zero;
  Decimal withholding = Decimal.zero;
}

class _Withholding {
  const _Withholding({
    required this.original,
    required this.inBase,
    required this.currency,
  });

  _Withholding.zero()
    : original = Decimal.zero,
      inBase = Decimal.zero,
      currency = '';

  final Decimal original;
  final Decimal inBase;
  final String currency;
}
