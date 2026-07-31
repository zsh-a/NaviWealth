import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart'
    show AssetType;
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart'
    show TradeDraft, TradeType;
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';

class FinanceTradeProposalApplier {
  FinanceTradeProposalApplier({
    required this.tradeEntryService,
    required this.journalEntryRepo,
    required this.priceRepo,
    required this.currentUserId,
    this.openLotsReader,
  });

  final TradeEntryService tradeEntryService;
  final JournalEntryRepository journalEntryRepo;
  final PriceRepository priceRepo;
  final Future<String> Function() currentUserId;
  final Future<List<Lot>> Function(
    String ownerUserId,
    String accountId,
    String assetId,
    DateTime asOf,
  )?
  openLotsReader;

  Future<ProposalApplyState> applyTrade(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final assetId = _requireString(plan, 'asset_id');
    final accountId = _requireString(plan, 'account_id');
    final qty = _requireDecimal(plan, 'quantity');
    final currency = plan.get('currency') ?? 'USD';
    final price = _optionalDecimal(plan, 'price');
    final fee = _optionalDecimal(plan, 'fee');
    final tax = _optionalDecimal(plan, 'tax');
    final tradeDate = _parseDate(plan.get('trade_date')) ?? DateTime.now();
    final note = plan.get('note');
    final type = _parseTradeType(plan.get('type'));
    final uid = await currentUserId();

    final asset = Asset(
      id: assetId,
      type: AssetType.stock,
      symbol: plan.get('asset_symbol') ?? assetId,
      currency: plan.get('asset_currency') ?? currency,
      name: plan.get('asset_name'),
      sync: _placeholderSync(),
    );
    final draft = TradeDraft(
      type: type,
      asset: asset,
      accountId: accountId,
      quantity: qty,
      price: price,
      fee: fee,
      tax: tax,
      currency: currency,
      tradeDate: tradeDate,
      note: note,
    );
    final openLots = type == TradeType.sell
        ? await (openLotsReader?.call(
                uid,
                accountId,
                assetId,
                tradeDate.toUtc(),
              ) ??
              Future.value(const <Lot>[]))
        : const <Lot>[];
    final tradePlan = await tradeEntryService.buildPlan(
      draft,
      openLots: openLots,
    );
    final tx = tradePlan.trade;

    if (type == TradeType.buy || type == TradeType.sell) {
      final cashAccountId = plan.get('counter_account_id') ?? accountId;
      final feeAccountId = AccountRepository.systemAccountIdForPath(
        'expense:trading:fee',
        ownerUserId: uid,
      );
      final taxAccountId = AccountRepository.systemAccountIdForPath(
        'expense:trading:tax',
        ownerUserId: uid,
      );

      if (type == TradeType.buy) {
        final build = JournalEntryBuilders.buy(
          date: tx.tradeDate,
          accountId: accountId,
          cashAccountId: cashAccountId,
          assetUnit: tx.assetId,
          qty: tx.quantity,
          price: tx.price,
          quoteCurrency: currency,
          lotId: tradePlan.createdLot?.id,
          acquiredOn: tradePlan.createdLot?.openedAt,
          feeAmount: tx.fee,
          feeAccountId: tx.fee != null ? feeAccountId : null,
          feeCurrency: tx.fee != null ? currency : null,
          taxAmount: tx.tax,
          taxAccountId: tx.tax != null ? taxAccountId : null,
          taxCurrency: tx.tax != null ? currency : null,
          narration: note,
        );
        final stored = await journalEntryRepo.create(
          entry: build.entry,
          postings: build.postings,
        );
        await priceRepo.record(
          unit: tx.assetId,
          quoteCurrency: currency,
          observedOn: tx.tradeDate,
          perUnit: tx.price,
          source: 'trade',
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: stored.entry.id,
          appliedTable: 'journal_entries',
          appliedAt: at,
          shortLabel: 'Recorded ${plan.summaryZh}',
        );
      } else {
        final capGainsAccountId = AccountRepository.systemAccountIdForPath(
          'income:capitalGains',
          ownerUserId: uid,
        );
        final build = JournalEntryBuilders.sellLots(
          date: tx.tradeDate,
          accountId: accountId,
          cashAccountId: cashAccountId,
          capitalGainsAccountId: capGainsAccountId,
          assetUnit: tx.assetId,
          allocations: [
            for (final pnl in tradePlan.realizedPnL)
              SellLotAllocation(
                quantity: pnl.quantity,
                costPerUnit: (pnl.costBasisInCostCurrency / pnl.quantity)
                    .toDecimal(scaleOnInfinitePrecision: 16),
                costCurrency: pnl.costCurrency,
                costToQuoteRate: pnl.costToQuoteRate,
                lotId: pnl.lotId,
                acquiredOn: pnl.lotOpenedAt,
              ),
          ],
          price: tx.price,
          quoteCurrency: currency,
          feeAmount: tx.fee,
          feeAccountId: tx.fee != null ? feeAccountId : null,
          feeCurrency: tx.fee != null ? currency : null,
          taxAmount: tx.tax,
          taxAccountId: tx.tax != null ? taxAccountId : null,
          taxCurrency: tx.tax != null ? currency : null,
          narration: note,
        );
        final stored = await journalEntryRepo.create(
          entry: build.entry,
          postings: build.postings,
        );
        await priceRepo.record(
          unit: tx.assetId,
          quoteCurrency: currency,
          observedOn: tx.tradeDate,
          perUnit: tx.price,
          source: 'trade',
        );
        return ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: stored.entry.id,
          appliedTable: 'journal_entries',
          appliedAt: at,
          shortLabel: 'Recorded ${plan.summaryZh}',
        );
      }
    }

    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: uid,
    );
    final build = JournalEntryBuilders.valuationAdjust(
      date: tx.tradeDate,
      accountId: accountId,
      equityAccountId: equityAccountId,
      assetUnit: tx.assetId,
      quantity: tx.quantity,
      newValuation: tx.price,
      currency: currency,
      narration: note,
    );
    final stored = await journalEntryRepo.create(
      entry: build.entry,
      postings: build.postings,
    );
    await priceRepo.record(
      unit: tx.assetId,
      quoteCurrency: currency,
      observedOn: tx.tradeDate,
      perUnit: tx.price,
      source: 'manual',
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: stored.entry.id,
      appliedTable: 'journal_entries',
      appliedAt: at,
      shortLabel: 'Recorded ${plan.summaryZh}',
    );
  }

  String _requireString(ReadyProposalPlan plan, String key) {
    final v = plan.get(key);
    if (v == null || v.isEmpty) {
      throw ProposalApplyException('Missing field $key');
    }
    return v;
  }

  Decimal _requireDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) {
      throw ProposalApplyException('Missing field $key');
    }
    final s = raw is String ? raw : raw.toString();
    final d = Decimal.tryParse(s);
    if (d == null) {
      throw ProposalApplyException('Field $key is not a valid number: $s');
    }
    return d;
  }

  Decimal? _optionalDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) return null;
    final s = raw is String ? raw : raw.toString();
    if (s.isEmpty) return null;
    final d = Decimal.tryParse(s);
    if (d == null || d == Decimal.zero) return null;
    return d;
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    return parsed?.toLocal();
  }

  TradeType _parseTradeType(String? s) {
    return switch (s) {
      'buy' => TradeType.buy,
      'sell' => TradeType.sell,
      'valuationAdjust' => TradeType.valuationAdjust,
      _ => throw ProposalApplyException('Unsupported trade type: $s'),
    };
  }

  SyncMeta _placeholderSync() => SyncMeta(
    ownerUserId: '',
    updatedAt: DateTime.now().toUtc(),
    updatedByDevice: '',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: ''),
  );
}
