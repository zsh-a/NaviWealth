import 'package:decimal/decimal.dart';

import '../../ai_tools/expense_to_transaction_input.dart';
import '../../ai_tools/local_skills/transaction_input.dart';
import '../../data/repositories/journal_entry_repository.dart';
import '../domain/ingest_models.dart';
import '../domain/ingest_source_reference.dart';
import '../domain/minor_unit_amount.dart';
import 'ingest_dedup.dart';
import 'ingest_dedup_candidate.dart';
import 'ingest_draft_store.dart';

/// One owner-scoped source of evidence for import, edits and final commit.
class IngestDedupService {
  const IngestDedupService({required this.store, required this.repository});

  final IngestDraftStore store;
  final JournalEntryRepository repository;

  String get _owner => store.ownerUserId ?? '';

  /// Resolve comparison evidence only when a user opens a duplicate. Targets
  /// may be another local draft or a journal entry and are always owner-scoped.
  Future<({ParsedTransaction parsed, bool isDraft})?> findMatch(
    String targetId, {
    ParsedTransaction? against,
  }) async {
    final staged = await store.readReviewItem(targetId);
    if (staged != null) return (parsed: staged.draft.parsed, isDraft: true);
    final ledger = await readLedger();
    final candidates = ledger.where((entry) => entry.id == targetId).toList();
    // One journal entry may have opposite transfer legs or trade fees. Prefer
    // the same kind/currency/direction instead of displaying an unrelated leg.
    final matched =
        candidates
            .where(
              (entry) =>
                  against == null ||
                  (entry.currency.toUpperCase() ==
                          against.currency.toUpperCase() &&
                      parseAmountMinor(entry.amountMinor).isNegative ==
                          against.amountMinor.isNegative &&
                      (entry is! IngestDedupCandidate ||
                          entry.kind == against.kind)),
            )
            .firstOrNull ??
        candidates.firstOrNull;
    if (matched == null) return null;
    final candidate = matched is IngestDedupCandidate ? matched : null;
    return (
      parsed: ParsedTransaction(
        description: matched.description,
        amountMinor: parseAmountMinor(matched.amountMinor),
        currency: matched.currency,
        occurredAt: matched.occurredAt,
        kind: candidate?.kind ?? IngestTransactionKind.expense,
        dateHasTime: candidate?.dateHasTime ?? true,
      ),
      isDraft: false,
    );
  }

  Future<List<TransactionInput>> readLedger() async {
    final expenses = await repository.watchExpenses(_owner).first;
    final entries = await repository.watchAllWithPostings().first;
    final ownedEntries = entries
        .where((item) => item.entry.sync.ownerUserId == _owner)
        .toList();
    final byId = {for (final item in ownedEntries) item.entry.id: item};
    final ledger = <TransactionInput>[];
    final expenseEntryIds = <String>{};
    for (final expense in expenses) {
      if (expense.sync.ownerUserId != _owner) continue;
      final entry = byId[expense.id];
      if (entry == null) continue;
      expenseEntryIds.add(expense.id);
      final input = expenseToTransactionInput(expense);
      // A trade's fee is still an expense, but must not inherit the principal
      // source identity; the broker parser stages those as separate row kinds.
      final tags = _isTrade(entry)
          ? expense.tags
                .where(
                  (tag) =>
                      !tag.startsWith(ingestIdentityTagPrefix) &&
                      !tag.startsWith(ingestScopeTagPrefix),
                )
                .toList()
          : expense.tags;
      ledger.add(_candidate(input, IngestTransactionKind.expense, tags));
    }
    for (final item in ownedEntries) {
      final tags = item.entry.tagIds;
      final trade = _isTrade(item);
      final incomes = item.postings.where(
        (posting) =>
            posting.accountId.toLowerCase().contains(':income:') &&
            posting.units < Decimal.zero,
      );
      if (!trade && incomes.isNotEmpty) {
        for (final posting in incomes) {
          final minor = parseMinorUnitAmount((-posting.units).toString());
          if (minor == null || minor == 0) continue;
          final destination = item.postings
              .where((p) => p.units > Decimal.zero && p.unit == posting.unit)
              .firstOrNull;
          ledger.add(
            _candidate(
              TransactionInput(
                id: item.entry.id,
                description: item.entry.payee ?? item.entry.narration,
                amountMinor: minor.toString(),
                currency: posting.unit,
                occurredAt: item.entry.date,
                accountId: destination?.accountId,
              ),
              IngestTransactionKind.income,
              tags,
            ),
          );
        }
        continue;
      }
      if (!trade && expenseEntryIds.contains(item.entry.id)) continue;
      // Transfer/trade cash legs retain account and direction. System/equity
      // adjustments are not imported bank activity.
      if (!trade &&
          item.postings.any(
            (p) =>
                RegExp(r':(?:income|expense|equity):')
                    .hasMatch(p.accountId.toLowerCase()),
          )) {
        continue;
      }
      if (item.postings.length < 2) continue;
      for (final posting in item.postings) {
        if (posting.sync.ownerUserId != _owner ||
            posting.cost != null ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(posting.unit) ||
            RegExp(r':(?:income|expense|equity):')
                .hasMatch(posting.accountId.toLowerCase())) {
          continue;
        }
        final minor = parseMinorUnitAmount(posting.units.toString());
        if (minor == null || minor == 0) continue;
        ledger.add(
          _candidate(
            TransactionInput(
              id: item.entry.id,
              description: item.entry.payee ?? item.entry.narration,
              amountMinor: minor.toString(),
              currency: posting.unit,
              occurredAt: item.entry.date,
              accountId: posting.accountId,
            ),
            trade
                ? IngestTransactionKind.trade
                : IngestTransactionKind.transfer,
            tags,
          ),
        );
      }
    }
    return ledger;
  }

  Future<List<TransactionInput>> snapshot() async {
    // Read all review rows first so a confirmation settling during the ledger
    // read cannot disappear from both snapshots.
    final pending = await store.listPendingReviewItems(limit: null);
    final ledger = await readLedger();
    final index = _index(ledger);
    final evidence = [...ledger];
    for (final item in pending) {
      final draft = item.draft;
      if (!item.isOrdinaryPending ||
          index.match(draft.parsed).verdict == DedupVerdict.newTxn) {
        final candidate = IngestDedupCandidate.fromDraft(draft);
        index.add(candidate, draft.draftId);
        evidence.add(candidate);
      }
    }
    return evidence;
  }

  Future<void> refreshPending() => store.runBatch(() async {
    final pending = await store.listPendingReviewItems(limit: null);
    final index = _index(await readLedger());
    for (final item in pending) {
      final draft = item.draft;
      if (!item.isOrdinaryPending) {
        index.add(IngestDedupCandidate.fromDraft(draft), draft.draftId);
        continue;
      }
      final result = index.match(draft.parsed);
      await store.updateDedup(
        draft,
        verdict: result.verdict,
        targetId: result.target,
      );
      if (result.verdict == DedupVerdict.newTxn) {
        index.add(IngestDedupCandidate.fromDraft(draft), draft.draftId);
      }
    }
  });

  Future<DedupResult> checkForConfirm(
    IngestDraft draft, {
    String? accountId,
  }) async {
    final pending = await store.listPendingReviewItems(limit: null);
    final index = _index(await readLedger());
    for (final item in pending) {
      if (item.draft.draftId == draft.draftId) break;
      final candidate = item.draft;
      if (!item.isOrdinaryPending ||
          index.match(candidate.parsed).verdict == DedupVerdict.newTxn) {
        index.add(IngestDedupCandidate.fromDraft(candidate), candidate.draftId);
      }
    }
    final result = index.match(draft.parsed, accountId: accountId);
    return DedupResult(verdict: result.verdict, targetEntryId: result.target);
  }

  IngestDedupIndex<String> _index(List<TransactionInput> ledger) {
    final index = IngestDedupIndex<String>();
    for (final entry in ledger) {
      index.add(entry, entry.id);
    }
    return index;
  }
}

bool _isTrade(JournalEntryWithPostings item) =>
    ingestTagValue(item.entry.tagIds, ingestKindTagPrefix) == 'trade' ||
    item.postings.any((posting) => posting.cost != null);

IngestDedupCandidate _candidate(
  TransactionInput input,
  IngestTransactionKind kind,
  List<String> tags,
) {
  final local = input.occurredAt.toLocal();
  return IngestDedupCandidate(
    id: input.id,
    description: input.description,
    amountMinor: input.amountMinor,
    currency: input.currency,
    occurredAt: input.occurredAt,
    accountId: input.accountId,
    categoryId: input.categoryId,
    kind: kind,
    sourceIdentity: ingestTagValue(tags, ingestIdentityTagPrefix),
    sourceScope: ingestTagValue(tags, ingestScopeTagPrefix),
    allowDateDrift: ingestTagValue(tags, ingestKindTagPrefix) == null,
    dateHasTime:
        local.hour != 0 ||
        local.minute != 0 ||
        local.second != 0 ||
        local.millisecond != 0 ||
        local.microsecond != 0,
  );
}
