part of 'yfinance_options_provider.dart';

mixin YFinanceOptionsProjectionMixin {
  List<int> _pickExpirations({
    required List<int> expirations,
    required int minDte,
    required int maxDte,
    required DateTime asOf,
  }) {
    final today = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final candidates = <({int epoch, int dte})>[];
    for (final epoch in expirations) {
      final exp = DateTime.fromMillisecondsSinceEpoch(
        epoch * 1000,
        isUtc: true,
      );
      final dte = DateTime.utc(
        exp.year,
        exp.month,
        exp.day,
      ).difference(today).inDays;
      if (dte < minDte || dte > maxDte) continue;
      candidates.add((epoch: epoch, dte: dte));
    }
    final preferredDte = ((minDte + maxDte) / 2).round();
    candidates.sort((a, b) {
      final aDistance = (a.dte - preferredDte).abs();
      final bDistance = (b.dte - preferredDte).abs();
      if (aDistance != bDistance) return aDistance.compareTo(bDistance);
      return a.dte.compareTo(b.dte);
    });
    final picked =
        candidates.take(YFinanceOptionsProvider._maxExpirationSlices).toList()
          ..sort((a, b) => a.dte.compareTo(b.dte));
    return [for (final c in picked) c.epoch];
  }

  OptionsChainSnapshot _projection(
    _CachedChainPayload payload,
    OptionsChainRequest request,
  ) {
    final filtered = payload.contracts
        .where((c) => c.dte >= request.minDte && c.dte <= request.maxDte)
        .toList(growable: false);
    return OptionsChainSnapshot(
      underlying: request.underlying.toUpperCase(),
      underlyingPriceRaw: payload.underlyingPriceRaw,
      currency: payload.currency,
      contracts: filtered,
      fetchedAt: payload.fetchedAt,
    );
  }
}
