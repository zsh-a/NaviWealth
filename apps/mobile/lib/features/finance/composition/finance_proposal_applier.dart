/// FinanceOS implementation of [ProposalApplier]
/// (`docs/architecture/lifeos-shell.md` §4, D-1.6b).
///
/// Dispatches a confirmed [ReadyProposalPlan] to the matching Finance
/// repository write, and reverses it again on undo. The chat UI in
/// `features/ai_chat/` only depends on the core `ProposalApplier`
/// interface — this concrete class is registered via
/// [financeProposalApplierProvider] in `bootstrap.dart`.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart'
    show AccountCategory, AssetType;
import 'package:naviwealth/features/finance/expense/domain/expense_category_taxonomy.dart';
import 'package:naviwealth/features/finance/fire/application/fire_proposal_applier.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart'
    show TradeDraft, TradeType;
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/application/options_proposal_applier.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/ai/write/drift_ai_touched_store.dart';
import '../../../core/ai/write/providers.dart';
import '../../../core/auth/current_user.dart';

export 'finance_proposal_kinds.dart' show kFinanceProposalAppliedKinds;

/// Drift table-name prefixes written by FinanceOS proposal appliers.
/// Used by the cross-domain composite to route undo explicitly.
const Set<String> kFinanceProposalAppliedTablePrefixes = {
  'journal_entries',
  'accounts',
  'assets',
  'fire_',
  'options_',
};

class FinanceProposalApplier implements ProposalApplier {
  FinanceProposalApplier({
    required this.tradeEntryService,
    required this.journalEntryRepo,
    required this.priceRepo,
    required this.accountRepo,
    required this.manualAssetRepo,
    required this.liabilityRepo,
    required this.optionsApplier,
    required this.fireApplier,
    required this.currentUserId,
    this.aiTouchedStore,
  });

  final TradeEntryService tradeEntryService;
  final JournalEntryRepository journalEntryRepo;
  final PriceRepository priceRepo;
  final AccountRepository accountRepo;
  final ManualAssetRepository manualAssetRepo;
  final LiabilityRepository liabilityRepo;
  final OptionsProposalApplier optionsApplier;
  final FireProposalApplier fireApplier;

  /// When present, every successful [apply] records an AI-
  /// touch entry keyed by `(entityType, entityId)`. Optional so
  /// existing tests (which inject the applier with hand-rolled stubs)
  /// don't need a Drift DB to compile. Production wiring in
  /// `features/ai_chat/data/providers.dart` always supplies it.
  final DriftAiTouchedStore? aiTouchedStore;

  /// Resolves the current single-user owner id, used to mint stable
  /// `system-account:<userId>:<path>` ids for the seeded
  /// expense / liability tree. Same shape as
  /// [MutationStamper.currentUserId] — production wiring delegates
  /// to that lookup so the applier never disagrees with the repo
  /// about the active user.
  final Future<String> Function() currentUserId;

  /// Run the compensating write encoded in [state]. No-op if [state] isn't
  /// in the `applied` status.
  @override
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
      case 'options_trade_journal':
        await optionsApplier.undoJournalEntry(id);
      default:
        throw ProposalApplyException('unknown undo table: $table');
    }
  }

  /// Persist [plan] via the appropriate repository. Returns a state stamped
  /// `applied` with the produced entity id. Throws [ProposalApplyException]
  /// (after wrapping the underlying error) if the write fails — the caller
  /// surfaces the message to the user instead of swallowing.
  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      final at = DateTime.now().toUtc();
      final state = switch (plan.kind) {
        'trade' => await _applyTrade(plan, at),
        'expense' => await _applyExpense(plan, at),
        'liability_payment' => await _applyLiabilityPayment(plan, at),
        'account_create' => await _applyAccountCreate(plan, at),
        'asset_valuation' => await _applyAssetValuation(plan, at),
        'fire_plan_update' => await fireApplier.applyPlanUpdate(plan, at),
        'fire_bucket_rule' => await fireApplier.applyBucketRule(plan, at),
        'options_profile_update' => await optionsApplier.applyProfileUpdate(
          plan,
        ),
        'options_journal_entry' => await optionsApplier.applyJournalEntry(
          plan,
          at,
        ),
        _ => throw ProposalApplyException(
          'unknown proposal kind: ${plan.kind}',
        ),
      };
      // When an apply succeeds, record the AI touch keyed by
      // (entityType, entityId). Detail pages surface a tiny sparkle
      // prefix for recent touches; the touch survives across restarts
      // because the table is persisted in Drift.
      await _recordTouch(plan, state, at);
      return state;
    } on ProposalApplyException {
      rethrow;
    } catch (e) {
      throw ProposalApplyException(e.toString());
    }
  }

  Future<void> _recordTouch(
    ReadyProposalPlan plan,
    ProposalApplyState state,
    DateTime at,
  ) async {
    final store = aiTouchedStore;
    if (store == null) return;
    if (state.status != ProposalApplyStatus.applied) return;
    final entityId = state.appliedEntityId;
    final entityType = state.appliedTable;
    if (entityId == null || entityType == null) return;
    try {
      await store.recordTouch(
        AiTouchedEntity(
          entityType: entityType,
          entityId: entityId,
          touchedAt: at,
          kindLabel: plan.kind,
        ),
      );
    } catch (_) {
      // Best-effort — failing to record the AI-touch metadata must
      // never break the apply path. The mark is decorative.
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
          shortLabel: 'Recorded ${plan.summaryZh}',
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
          shortLabel: 'Recorded ${plan.summaryZh}',
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
      shortLabel: 'Recorded ${plan.summaryZh}',
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
    if (!isExpenseCategorySlug(categorySlug)) {
      throw ProposalApplyException('Unknown expense category: $categorySlug');
    }
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
      shortLabel: 'Recorded ${plan.summaryZh}',
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
      throw ProposalApplyException('Liability $liabilityId does not exist');
    }
    final liabilityAccountId = liability.accountId;
    if (liabilityAccountId == null) {
      throw ProposalApplyException(
        'Liability ${liability.name} is not linked to an account, so the '
        'payment cannot be recorded',
      );
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
      shortLabel: 'Applied ${plan.summaryZh}',
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
      shortLabel: 'Created ${plan.summaryZh}',
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
      throw ProposalApplyException(
        'Asset $assetId does not exist or is not a manual-valuation type',
      );
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
      shortLabel: 'Updated ${plan.summaryZh}',
    );
  }

  // ─── parsing helpers ─────────────────────────────────────────────────

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
      _ => throw ProposalApplyException('Unsupported trade type: $s'),
    };
  }

  AccountCategory _parseAccountType(String? s) {
    return switch (s) {
      'brokerage' => AccountCategory.broker,
      'bank' => AccountCategory.bank,
      'cryptoWallet' => AccountCategory.crypto,
      'realEstate' => AccountCategory.asset,
      'vehicle' => AccountCategory.asset,
      'liability' => AccountCategory.liability,
      'cash' => AccountCategory.cash,
      'other' => AccountCategory.asset,
      _ => throw ProposalApplyException('Unsupported account type: $s'),
    };
  }

  /// Asset domain model demands a non-null SyncMeta even when we don't
  /// persist the asset. The trade-entry service consults the asset for
  /// pricing / FX backfill but only reads `id`, `symbol`, `currency`,
  /// `type`. The placeholder here is never written to disk; the assets
  /// table row was already created by an earlier sync pull.
  SyncMeta _placeholderSync() => SyncMeta(
    ownerUserId: '',
    updatedAt: DateTime.now().toUtc(),
    updatedByDevice: '',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: ''),
  );
}

/// Finance-domain applier wiring. Resolves all repositories +
/// fire writers once and instantiates [FinanceProposalApplier]. Used by
/// `bootstrap.dart` to override `proposalApplierProvider`.
final financeProposalApplierProvider = FutureProvider<ProposalApplier>((
  ref,
) async {
  final tradeService = await ref.watch(tradeEntryServiceProvider.future);
  final journalEntryRepo = await ref.watch(
    journalEntryRepositoryProvider.future,
  );
  final priceRepo = await ref.watch(priceRepositoryProvider.future);
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final manualAssetRepo = await ref.watch(manualAssetRepositoryProvider.future);
  final liabilityRepo = await ref.watch(liabilityRepositoryProvider.future);
  final optionsProfileRepo = await ref.watch(
    optionsStrategyProfileRepositoryProvider.future,
  );
  final tradeJournalRepo = await ref.watch(
    tradeJournalRepositoryProvider.future,
  );
  final optionsLedgerService = await ref.watch(
    optionsJournalLedgerServiceProvider.future,
  );
  final fireApplier = ref.watch(fireProposalApplierProvider);
  final currentUserId = ref.watch(currentUserIdProvider);
  final touched = ref.watch(aiTouchedStoreProvider);
  return FinanceProposalApplier(
    tradeEntryService: tradeService,
    journalEntryRepo: journalEntryRepo,
    priceRepo: priceRepo,
    accountRepo: accountRepo,
    manualAssetRepo: manualAssetRepo,
    liabilityRepo: liabilityRepo,
    optionsApplier: OptionsProposalApplier(
      profileRepo: optionsProfileRepo,
      tradeJournalRepo: tradeJournalRepo,
      ledgerService: optionsLedgerService,
      currentUserId: currentUserId,
    ),
    fireApplier: fireApplier,
    currentUserId: currentUserId,
    aiTouchedStore: touched,
  );
});
