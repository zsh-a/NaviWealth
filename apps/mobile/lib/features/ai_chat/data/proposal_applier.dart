/// Dispatch a confirmed [ReadyProposalPlan] to the matching repository
/// write, and reverse it again on undo. One central place so the propose
/// card UI doesn't have to know about TradeEntryService / ExpenseRepository
/// / etc. — it only deals in [ProposalApplyState] handles.
///
/// Each `apply` returns a state stamped with `applied`, the entity id, and
/// (for asset_valuation, where the row already exists) the previous value
/// the undo path needs to restore. `undo` reads that state and runs the
/// compensating write.
library;

import 'package:decimal/decimal.dart';

import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart' show AccountType, AssetType;
import '../../../data/domain/hlc.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/journal_entry_builders.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../data/repositories/manual_asset_repository.dart';
import '../../../data/repositories/price_repository.dart';
import '../../investment/domain/models/lot.dart';
import '../../investment/domain/trade_entry/trade_draft.dart' show TradeDraft, TradeType;
import '../../investment/domain/trade_entry/trade_entry_service.dart';
import '../../liabilities/data/liability_repository.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';

class ProposalApplyException implements Exception {
  ProposalApplyException(this.message);
  final String message;

  @override
  String toString() => 'ProposalApplyException: $message';
}

class ProposalApplier {
  ProposalApplier({
    required this.tradeEntryService,
    required this.journalEntryRepo,
    required this.priceRepo,
    required this.accountRepo,
    required this.manualAssetRepo,
    required this.liabilityRepo,
    required this.currentUserId,
  });

  final TradeEntryService tradeEntryService;
  final JournalEntryRepository journalEntryRepo;
  final PriceRepository priceRepo;
  final AccountRepository accountRepo;
  final ManualAssetRepository manualAssetRepo;
  final LiabilityRepository liabilityRepo;

  /// Resolves the current single-user owner id, used to mint stable
  /// `system-account:<userId>:<path>` ids for the FIR-133 seeded
  /// expense / liability tree. Same shape as
  /// [MutationStamper.currentUserId] — production wiring delegates
  /// to that lookup so the applier never disagrees with the repo
  /// about the active user.
  final Future<String> Function() currentUserId;

  /// Run the compensating write encoded in [state]. No-op if [state] isn't
  /// in the `applied` status.
  Future<void> undo(ProposalApplyState state) async {
    if (state.status != ProposalApplyStatus.applied) return;
    final id = state.appliedEntityId;
    final table = state.appliedTable;
    if (id == null || table == null) return;
    switch (table) {
      case 'journal_entries':
        await journalEntryRepo.softDelete(id);
      case 'accounts':
        await accountRepo.softDelete(id);
      case 'assets':
        await manualAssetRepo.softDelete(id, reason: 'undo');
      default:
        throw ProposalApplyException('unknown undo table: $table');
    }
  }

  /// Persist [plan] via the appropriate repository. Returns a state stamped
  /// `applied` with the produced entity id. Throws [ProposalApplyException]
  /// (after wrapping the underlying error) if the write fails — the caller
  /// surfaces the message to the user instead of swallowing.
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      final at = DateTime.now().toUtc();
      switch (plan.kind) {
        case ProposalKind.trade:
          return await _applyTrade(plan, at);
        case ProposalKind.expense:
          return await _applyExpense(plan, at);
        case ProposalKind.liabilityPayment:
          return await _applyLiabilityPayment(plan, at);
        case ProposalKind.accountCreate:
          return await _applyAccountCreate(plan, at);
        case ProposalKind.assetValuation:
          return await _applyAssetValuation(plan, at);
        case ProposalKind.unknown:
          throw ProposalApplyException('unknown proposal kind');
      }
    } on ProposalApplyException {
      rethrow;
    } catch (e) {
      throw ProposalApplyException(e.toString());
    }
  }

  Future<ProposalApplyState> _applyTrade(
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
    final tradePlan = await tradeEntryService.buildPlan(
      draft,
      openLots: const <Lot>[],
    );
    final tx = tradePlan.trade;

    if (type == TradeType.buy || type == TradeType.sell) {
      final uid = await currentUserId();
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
          shortLabel: '已记录${plan.summaryZh}',
        );
      } else {
        // Sell — cost basis from resolved lots.
        final capGainsAccountId = AccountRepository.systemAccountIdForPath(
          'income:capitalGains',
          ownerUserId: uid,
        );
        final pnl = tradePlan.realizedPnL;
        Decimal costPerUnit;
        String costCurrency;
        String? sellLotId;
        DateTime? sellAcquiredOn;
        if (pnl.isNotEmpty) {
          final first = pnl.first;
          costPerUnit = first.quantity.sign != 0
              ? (first.costBasis / first.quantity).toDecimal(
                  scaleOnInfinitePrecision: 16,
                )
              : tx.price;
          costCurrency = first.currency;
          sellLotId = first.lotId;
          sellAcquiredOn = first.lotOpenedAt;
        } else {
          costPerUnit = tx.price;
          costCurrency = currency;
        }
        final build = JournalEntryBuilders.sell(
          date: tx.tradeDate,
          accountId: accountId,
          cashAccountId: cashAccountId,
          capitalGainsAccountId: capGainsAccountId,
          assetUnit: tx.assetId,
          qty: tx.quantity,
          price: tx.price,
          quoteCurrency: currency,
          costPerUnit: costPerUnit,
          costCurrency: costCurrency,
          lotId: sellLotId,
          acquiredOn: sellAcquiredOn,
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
          shortLabel: '已记录${plan.summaryZh}',
        );
      }
    }

    final uid = await currentUserId();
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
      shortLabel: '已记录${plan.summaryZh}',
    );
  }

  Future<ProposalApplyState> _applyExpense(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final fromAccountId = _requireString(plan, 'account_id');
    final amount = _requireDecimal(plan, 'amount');
    final currency = plan.get('currency') ?? 'CNY';
    final tradeDate = _parseDate(plan.get('date')) ?? DateTime.now();
    final note = plan.get('note');
    final categorySlug = plan.get('category') ?? 'other';
    final ownerUserId = await currentUserId();
    final expenseAccountId = AccountRepository.systemAccountIdForPath(
      'expense:$categorySlug',
      ownerUserId: ownerUserId,
    );

    final build = JournalEntryBuilders.expense(
      date: tradeDate,
      expenseAccountId: expenseAccountId,
      fromAccountId: fromAccountId,
      amount: amount,
      currency: currency,
      narration: note ?? plan.summaryZh,
    );
    final stored = await journalEntryRepo.create(
      entry: build.entry,
      postings: build.postings,
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: stored.entry.id,
      appliedTable: 'journal_entries',
      appliedAt: at,
      shortLabel: '已记录${plan.summaryZh}',
    );
  }

  Future<ProposalApplyState> _applyLiabilityPayment(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final liabilityId = _requireString(plan, 'liability_id');
    final fromAccountId = _requireString(plan, 'from_account_id');
    final amount = _requireDecimal(plan, 'amount');
    final currency = plan.get('currency') ?? 'CNY';
    final date = _parseDate(plan.get('date')) ?? DateTime.now();
    final note = plan.get('note');

    final liability = await liabilityRepo.findById(liabilityId);
    if (liability == null) {
      throw ProposalApplyException('负债 $liabilityId 不存在');
    }
    final liabilityAccountId = liability.accountId;
    if (liabilityAccountId == null) {
      throw ProposalApplyException('负债 ${liability.name} 未关联账户，无法记录还款');
    }

    final uid = await currentUserId();
    // Interest leg is unused (interest = 0) but the builder requires a
    // valid account id.  expense:trading:interest is the closest match.
    final interestExpenseAccountId = AccountRepository.systemAccountIdForPath(
      'expense:trading:interest',
      ownerUserId: uid,
    );

    final build = JournalEntryBuilders.liabilityPayment(
      date: date,
      liabilityAccountId: liabilityAccountId,
      fromAccountId: fromAccountId,
      interestExpenseAccountId: interestExpenseAccountId,
      principal: amount,
      interest: Decimal.zero,
      currency: currency,
      narration: note ?? 'Liability ${liability.name} payment',
    );
    final stored = await journalEntryRepo.create(
      entry: build.entry,
      postings: build.postings,
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: stored.entry.id,
      appliedTable: 'journal_entries',
      appliedAt: at,
      shortLabel: '已${plan.summaryZh}',
    );
  }

  Future<ProposalApplyState> _applyAccountCreate(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final name = _requireString(plan, 'name');
    final type = _parseAccountType(plan.get('type'));
    final currency = plan.get('currency') ?? 'CNY';
    final institution = plan.get('institution');
    final note = plan.get('note');

    final stored = await accountRepo.create(
      type: type,
      name: name,
      currency: currency,
      institution: institution,
      note: note,
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: stored.id,
      appliedTable: 'accounts',
      appliedAt: at,
      shortLabel: '已${plan.summaryZh}',
    );
  }

  Future<ProposalApplyState> _applyAssetValuation(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final assetId = _requireString(plan, 'asset_id');
    final newValue = _requireDecimal(plan, 'new_value');
    final existing = await manualAssetRepo.findById(assetId);
    if (existing == null) {
      throw ProposalApplyException('asset $assetId 不存在或不是手工估值类型');
    }
    await manualAssetRepo.recordValuationAdjust(
      assetId: assetId,
      newValuation: newValue,
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: assetId,
      appliedTable: 'assets',
      appliedAt: at,
      shortLabel: '已${plan.summaryZh}',
    );
  }

  // ─── parsing helpers ─────────────────────────────────────────────────

  String _requireString(ReadyProposalPlan plan, String key) {
    final v = plan.get(key);
    if (v == null || v.isEmpty) {
      throw ProposalApplyException('缺少字段 $key');
    }
    return v;
  }

  Decimal _requireDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) {
      throw ProposalApplyException('缺少字段 $key');
    }
    final s = raw is String ? raw : raw.toString();
    final d = Decimal.tryParse(s);
    if (d == null) {
      throw ProposalApplyException('字段 $key 不是合法数字: $s');
    }
    return d;
  }

  Decimal? _optionalDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) return null;
    final s = raw is String ? raw : raw.toString();
    if (s.isEmpty) return null;
    final d = Decimal.tryParse(s);
    // Normalise zero to null so JE builders' _normalizeOptionalAmount
    // doesn't reject a backend-supplied "0" as an invalid positive amount.
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
      _ => throw ProposalApplyException('不支持的交易类型: $s'),
    };
  }

  AccountType _parseAccountType(String? s) {
    return switch (s) {
      'brokerage' => AccountType.brokerage,
      'bank' => AccountType.bank,
      'cryptoWallet' => AccountType.cryptoWallet,
      'realEstate' => AccountType.realEstate,
      'vehicle' => AccountType.vehicle,
      'liability' => AccountType.liability,
      'cash' => AccountType.cash,
      'other' => AccountType.other,
      _ => throw ProposalApplyException('不支持的账户类型: $s'),
    };
  }

  /// Asset domain model demands a non-null SyncMeta even when we don't
  /// persist the asset. The trade-entry service consults the asset for
  /// pricing / FX backfill but only reads `id`, `symbol`, `currency`,
  /// `type`. The placeholder here is never written to disk; the assets
  /// table row was already created by an earlier sync pull.
  SyncMeta _placeholderSync() => SyncMeta(
    ownerUserId: 'local-user',
    updatedAt: DateTime.now().toUtc(),
    updatedByDevice: '',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: ''),
  );
}
