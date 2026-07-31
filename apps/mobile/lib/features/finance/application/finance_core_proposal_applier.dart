import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart'
    show AccountCategory;
import 'package:naviwealth/features/finance/expense/data/expense_category_repository.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_taxonomy.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';

class FinanceCoreProposalApplier {
  FinanceCoreProposalApplier({
    required this.journalEntryRepo,
    required this.accountRepo,
    required this.manualAssetRepo,
    required this.liabilityRepo,
    required this.expenseCategoryRepo,
    required this.currentUserId,
  });

  final JournalEntryRepository journalEntryRepo;
  final AccountRepository accountRepo;
  final ManualAssetRepository manualAssetRepo;
  final LiabilityRepository liabilityRepo;
  final ExpenseCategoryRepository expenseCategoryRepo;
  final Future<String> Function() currentUserId;

  Future<ProposalApplyState> applyExpense(
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
    final category = await expenseCategoryRepo.findById(
      ownerUserId,
      ExpenseCategoryRepository.systemCategoryId(ownerUserId, categorySlug),
    );
    if (category == null || category.archived || category.isMerged) {
      throw ProposalApplyException(
        'Expense category is unavailable: $categorySlug',
      );
    }

    final build = JournalEntryBuilders.expense(
      date: tradeDate,
      expenseAccountId: category.ledgerAccountId,
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

  Future<ProposalApplyState> applyIncome(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final toAccountId = _requireString(plan, 'account_id');
    final amount = _requireDecimal(plan, 'amount');
    final currency = plan.get('currency') ?? 'CNY';
    final date = _parseDate(plan.get('date')) ?? DateTime.now();
    final note = plan.get('note');
    final category = plan.get('category') ?? 'other';
    if (!const {'salary', 'dividend', 'interest', 'other'}.contains(category)) {
      throw ProposalApplyException('Unknown income category: $category');
    }
    final ownerUserId = await currentUserId();
    final incomeAccountId = AccountRepository.systemAccountIdForPath(
      'income:$category',
      ownerUserId: ownerUserId,
    );
    final build = JournalEntryBuilders.income(
      date: date,
      toAccountId: toAccountId,
      incomeAccountId: incomeAccountId,
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

  Future<ProposalApplyState> applyTransfer(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final fromAccountId = _requireString(plan, 'from_account_id');
    final toAccountId = _requireString(plan, 'to_account_id');
    if (fromAccountId == toAccountId) {
      throw ProposalApplyException(
        'Transfer source and destination accounts must differ',
      );
    }
    final from = await accountRepo.findById(fromAccountId);
    final to = await accountRepo.findById(toAccountId);
    if (from == null || from.archived || from.sync.deletedAt != null) {
      throw ProposalApplyException('Source account is unavailable');
    }
    if (to == null || to.archived || to.sync.deletedAt != null) {
      throw ProposalApplyException('Destination account is unavailable');
    }
    final amount = _requireDecimal(plan, 'amount');
    if (amount <= Decimal.zero) {
      throw ProposalApplyException('Transfer amount must be positive');
    }
    final crossCurrency =
        from.currency.toUpperCase() != to.currency.toUpperCase();
    final toAmount = crossCurrency ? _requireDecimal(plan, 'to_amount') : null;
    if (toAmount != null && toAmount <= Decimal.zero) {
      throw ProposalApplyException(
        'Cross-currency destination amount must be positive',
      );
    }
    final date = _parseDate(plan.get('date')) ?? DateTime.now();
    final build = JournalEntryBuilders.transfer(
      date: date,
      fromAccountId: from.id,
      toAccountId: to.id,
      amount: amount,
      currency: from.currency,
      toAmount: toAmount,
      toCurrency: crossCurrency ? to.currency : null,
      narration: plan.get('note') ?? plan.summaryZh,
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

  Future<ProposalApplyState> applyLiabilityPayment(
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

  Future<ProposalApplyState> applyAccountCreate(
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

  Future<ProposalApplyState> applyAssetValuation(
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
    final beforeValue = await manualAssetRepo.latestValuation(assetId);
    await manualAssetRepo.recordValuationAdjust(
      assetId: assetId,
      newValuation: newValue,
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: assetId,
      appliedTable: 'assets',
      appliedAt: beforeValue == null ? null : at,
      undoData: beforeValue == null
          ? null
          : <String, Object?>{'before_value': beforeValue.toString()},
      shortLabel: 'Updated ${plan.summaryZh}',
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

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    return parsed?.toLocal();
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
}
