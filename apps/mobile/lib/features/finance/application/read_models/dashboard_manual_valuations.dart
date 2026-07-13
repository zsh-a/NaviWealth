part of 'dashboard_providers.dart';

final dashboardPriceRowsProvider = StreamProvider.autoDispose<List<PriceRow>>((
  ref,
) async* {
  if (!ref.mounted) return;
  final db = await ref.watch(appDatabaseProvider.future);
  if (!ref.mounted) return;
  final query = db.select(db.prices)..where((t) => t.deletedAt.isNull());
  yield* query.watch();
});

/// Historical cash-account balances derived from the postings ledger.
///
/// Keyed by `accountId`, each value is a chronologically ordered list of
/// [ManualAssetValuePoint]s representing the running balance after every
/// posting date.  The dashboard snapshot uses the last point per account;
/// the trend builder walks the full series via [ManualAssetValuation.valueAt].
final _cashPostingHistoryProvider =
    StreamProvider.autoDispose<Map<String, List<ManualAssetValuePoint>>>((
      ref,
    ) async* {
      // This generator chains `await ref.watch(...future)` calls. When an
      // upstream autoDispose stream (e.g. manualAssetsStreamProvider)
      // emits, this provider is invalidated mid-flight; the suspended
      // build then resumes and would touch a disposed Ref. Riverpod 3's
      // `ref.mounted` is safe to read post-dispose — bail before every
      // Ref use that follows an async gap. Returning just ends the
      // stream for the dead build; the fresh build supersedes it.
      if (!ref.mounted) return;
      // Collect account IDs from cash assets' metadata. The link between a
      // cash asset and its postings is through CashMetadata.accountId stored
      // in assets.metadata_json — not through assets.id.
      final cashAccountCurrencies = <String, String>{};
      final assets = await ref.watch(manualAssetsStreamProvider.future);
      if (!ref.mounted) return;
      for (final a in assets) {
        if (a.type == AssetType.cash) {
          final meta = ManualAssetMetadata.decode(a.metadataJson);
          if (meta?.accountId case final id?) {
            cashAccountCurrencies[id] = a.currency;
          }
        }
      }
      final cashAccountIds = cashAccountCurrencies.keys.toSet();
      if (cashAccountIds.isEmpty) {
        yield const {};
        return;
      }
      final cashCurrencies = cashAccountCurrencies.values.toSet();

      final db = await ref.watch(appDatabaseProvider.future);
      if (!ref.mounted) return;
      final je = db.journalEntries;
      final p = db.postings;
      final query =
          db.select(p).join([innerJoin(je, je.id.equalsExp(p.journalEntryId))])
            ..where(p.deletedAt.isNull())
            ..where(je.deletedAt.isNull())
            ..where(p.accountId.isIn(cashAccountIds))
            ..where(p.unit.isIn(cashCurrencies))
            ..addColumns([je.date])
            ..orderBy([
              OrderingTerm.asc(p.accountId),
              OrderingTerm.asc(je.date),
            ]);
      yield* query.watch().map((rows) {
        final raw = <String, List<(DateTime, Decimal)>>{};
        for (final row in rows) {
          final posting = row.readTable(p);
          if (posting.unit != cashAccountCurrencies[posting.accountId]) {
            continue;
          }
          final date = row.read(je.date)!;
          raw.putIfAbsent(posting.accountId, () => []).add((
            date,
            posting.units,
          ));
        }
        return {
          for (final entry in raw.entries)
            entry.key: _runningBalance(entry.value),
        };
      });
    });

List<ManualAssetValuePoint> _runningBalance(
  List<(DateTime date, Decimal delta)> rows,
) {
  final out = <ManualAssetValuePoint>[];
  var cumulative = Decimal.zero;
  for (final (date, delta) in rows) {
    cumulative += delta;
    out.add(
      ManualAssetValuePoint(observedOn: _floorToDay(date), value: cumulative),
    );
  }
  return out;
}

final dashboardManualAssetValuationsProvider =
    Provider<AsyncValue<List<ManualAssetValuation>>>((ref) {
      final manual = ref.watch(manualAssetsStreamProvider);
      if (manual.isLoading) return const AsyncValue.loading();
      if (manual.hasError) {
        return AsyncValue.error(
          manual.error!,
          manual.stackTrace ?? StackTrace.current,
        );
      }
      final manualList = manual.value ?? const <Asset>[];
      if (manualList.isEmpty) {
        return const AsyncValue.data(<ManualAssetValuation>[]);
      }

      final cashHistory = ref.watch(_cashPostingHistoryProvider);
      final prices = ref.watch(dashboardPriceRowsProvider);
      if (cashHistory.isLoading || prices.isLoading) {
        return const AsyncValue.loading();
      }
      if (cashHistory.hasError) {
        return AsyncValue.error(
          cashHistory.error!,
          cashHistory.stackTrace ?? StackTrace.current,
        );
      }
      if (prices.hasError) {
        return AsyncValue.error(
          prices.error!,
          prices.stackTrace ?? StackTrace.current,
        );
      }
      return AsyncValue.data(
        _buildManualAssetValuations(
          manualAssets: manualList,
          priceRows: prices.value ?? const <PriceRow>[],
          cashHistory: cashHistory.value ?? const {},
        ),
      );
    });

/// Floor a timestamp to the start of its UTC day. Trend sample dates are
/// all at midnight UTC; observations with an intra-day time component
/// (e.g. `12:25:33`) would fall *after* the sample date and be invisible
/// to [ManualAssetValuation.valueAt].
DateTime _floorToDay(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

List<ManualAssetValuation> _buildManualAssetValuations({
  required List<Asset> manualAssets,
  required List<PriceRow> priceRows,
  required Map<String, List<ManualAssetValuePoint>> cashHistory,
}) {
  if (manualAssets.isEmpty) return const [];
  final pricesByUnit = <String, List<PriceRow>>{};
  for (final row in priceRows) {
    pricesByUnit.putIfAbsent(row.unit, () => <PriceRow>[]).add(row);
  }

  final out = <ManualAssetValuation>[];
  final seenCashAccounts = <String>{};
  for (final asset in manualAssets) {
    if (asset.type == AssetType.cash) {
      final meta = ManualAssetMetadata.decode(asset.metadataJson);
      final accountId = meta?.accountId;
      // Each ledger account has at most one cash asset (double-entry
      // invariant enforced by the create flow). Skip duplicates keyed by
      // accountId to avoid double-counting. When accountId is null the
      // metadata is missing — fall through to the price-row lookup.
      if (accountId != null && !seenCashAccounts.add(accountId)) continue;

      // 1. Prefer posting-derived running balance (most accurate).
      if (accountId != null) {
        final historyObs = cashHistory[accountId];
        if (historyObs != null && historyObs.isNotEmpty) {
          out.add(ManualAssetValuation(asset: asset, observations: historyObs));
          continue;
        }
      }

      // 2. Fall back to price-row observations (created by
      //    _recordValuation when the cash asset was first set up).
      final assetPriceRows =
          (pricesByUnit[asset.id] ?? const <PriceRow>[])
              .where((row) => row.quoteCurrency == asset.currency)
              .toList(growable: false)
            ..sort((a, b) => a.observedOn.compareTo(b.observedOn));
      if (assetPriceRows.isNotEmpty) {
        out.add(
          ManualAssetValuation(
            asset: asset,
            observations: [
              for (final row in assetPriceRows)
                ManualAssetValuePoint(
                  observedOn: _floorToDay(row.observedOn),
                  value: row.perUnit,
                ),
            ],
          ),
        );
        continue;
      }

      // 3. No posting/valuation yet. Keep the asset in the trend input so
      //    lifecycle quality can classify it as unheld instead of inventing
      //    a zero-valued observation.
      out.add(ManualAssetValuation(asset: asset, observations: const []));
      continue;
    }
    // Non-cash manual assets: use price-row observations.
    final rows =
        (pricesByUnit[asset.id] ?? const <PriceRow>[])
            .where((row) => row.quoteCurrency == asset.currency)
            .toList(growable: false)
          ..sort((a, b) => a.observedOn.compareTo(b.observedOn));
    if (rows.isNotEmpty) {
      out.add(
        ManualAssetValuation(
          asset: asset,
          observations: [
            for (final row in rows)
              ManualAssetValuePoint(
                observedOn: _floorToDay(row.observedOn),
                value: row.perUnit,
              ),
          ],
        ),
      );
    } else {
      out.add(ManualAssetValuation(asset: asset, observations: const []));
    }
  }
  return List.unmodifiable(out);
}

Future<List<ManualAssetValuation>> _manualAssetValuationsForHeader(
  Ref ref,
) async {
  final async = ref.watch(dashboardManualAssetValuationsProvider);
  if (async.hasValue) {
    return async.value ?? const <ManualAssetValuation>[];
  }
  if (async.hasError) {
    Error.throwWithStackTrace(
      async.error!,
      async.stackTrace ?? StackTrace.current,
    );
  }

  final manualAssets = await ref.watch(manualAssetsStreamProvider.future);
  if (manualAssets.isEmpty) return const <ManualAssetValuation>[];
  if (!ref.mounted) return const <ManualAssetValuation>[];
  final cashHistory = await ref.watch(_cashPostingHistoryProvider.future);
  if (!ref.mounted) return const <ManualAssetValuation>[];
  final priceRows = await ref.watch(dashboardPriceRowsProvider.future);
  return _buildManualAssetValuations(
    manualAssets: manualAssets,
    priceRows: priceRows,
    cashHistory: cashHistory,
  );
}
