import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics/haptics.dart';
import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/hlc.dart';
import '../../data/domain/posting.dart';
import '../../data/domain/sync_meta.dart';
import '../../data/repositories/journal_entry_builders.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/journal_entry_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../shared/account_tree_picker.dart';
import '../shared/forms/forms.dart';
import '../shared/postings_preview.dart';

/// FIR-131 wave 3a — first user-facing form built on the
/// [JournalEntryRepository] / [JournalEntryBuilders] stack.
///
/// Records a same-currency transfer between two of the user's
/// asset / liability accounts. Cross-currency transfers (with an
/// inline FX rate input) ship in wave 3b once the broader
/// `propose_card.dart` rewrite forces us to shape the FX widget.
///
/// The page intentionally bypasses the legacy
/// `TransactionRepository.recordTransfer` path: every keystroke
/// rebuilds the live `(JournalEntryDraft, [PostingDraft])` via
/// [JournalEntryBuilders.transfer], the [PostingsPreview] panel
/// renders it inline, and the submit button dispatches the same
/// shape to [JournalEntryRepository.create].
class TransferFormPage extends ConsumerStatefulWidget {
  const TransferFormPage({super.key});

  @override
  ConsumerState<TransferFormPage> createState() => _TransferFormPageState();
}

/// Throw-away sync metadata for live preview postings. Never persisted
/// — the values exist only so [Posting]'s constructor accepts the
/// preview rows for rendering.
final SyncMeta _previewSync = SyncMeta(
  ownerUserId: 'preview',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedByDevice: 'preview',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'preview'),
);

class _TransferFormPageState extends ConsumerState<TransferFormPage>
    with OptimisticFormSubmit<TransferFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();

  String? _fromAccountId;
  String? _toAccountId;
  String _currency = 'CNY';
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: const GlassAppBar(title: Text('New transfer')),
      body: accountsAsync.when(
        data: (accounts) => _buildForm(context, accounts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load accounts: $e')),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Account> accounts) {
    // The picker filters by category internally; we pre-compute the
    // asset+liability subset once so the live preview can resolve
    // account names without re-walking the full list per keystroke.
    final transferable = <Account>[
      for (final a in accounts)
        if (a.category == AccountCategory.asset ||
            a.category == AccountCategory.liability)
          a,
    ];
    final accountsById = <String, Account>{
      for (final a in accounts) a.id: a,
    };

    final fromAccount = _fromAccountId == null
        ? null
        : accountsById[_fromAccountId!];
    final toAccount = _toAccountId == null
        ? null
        : accountsById[_toAccountId!];

    final amount = readAmount(_amountController);
    final preview = _buildPreview(
      fromId: _fromAccountId,
      toId: _toAccountId,
      amount: amount,
      currency: _currency,
    );

    final canSubmit =
        !_busy &&
        _fromAccountId != null &&
        _toAccountId != null &&
        _fromAccountId != _toAccountId &&
        amount != null &&
        amount > Decimal.zero;

    return SingleChildScrollView(
      padding: Spacing.pageMobile,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountTreePicker(
              accounts: transferable,
              value: _fromAccountId,
              onChanged: (v) => setState(() {
                _fromAccountId = v;
                _maybeAdoptCurrency(accountsById, v);
              }),
              category: null,
              label: 'From account',
              allowSystemAccounts: false,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Spacing.s12),
            AccountTreePicker(
              accounts: transferable,
              value: _toAccountId,
              onChanged: (v) => setState(() {
                _toAccountId = v;
                _maybeAdoptCurrency(accountsById, v);
              }),
              category: null,
              label: 'To account',
              allowSystemAccounts: false,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v == _fromAccountId) {
                  return 'Pick a different account';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.s12),
            AmountField(
              label: 'Amount',
              controller: _amountController,
              currencyCode: _currency,
              focusNode: _amountFocus,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) => _noteFocus.requestFocus(),
            ),
            const SizedBox(height: Spacing.s12),
            CurrencyPicker(
              value: _currency,
              onChanged: (v) {
                if (v != null) setState(() => _currency = v);
              },
            ),
            if (_currencyMismatch(fromAccount, toAccount, _currency))
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s4),
                child: Text(
                  'Cross-currency transfers are not supported yet — '
                  'pick two accounts that share the same currency.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: Spacing.s12),
            DateField(
              label: 'Date',
              initialValue: _date,
              required: true,
              onChanged: (d) {
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: Spacing.s12),
            NoteField(
              controller: _noteController,
              focusNode: _noteFocus,
            ),
            const SizedBox(height: Spacing.s16),
            if (preview != null)
              PostingsPreview(
                postings: preview,
                accounts: accountsById,
                title: _noteController.text.isEmpty
                    ? 'Transfer'
                    : _noteController.text,
              ),
            const SizedBox(height: Spacing.s16),
            FilledButton(
              onPressed: canSubmit ? _save : null,
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  /// When the user picks an account whose currency differs from the
  /// active selection, snap to the picked account's currency. Saves
  /// a click in the common single-currency case while still letting
  /// the user override via the [CurrencyPicker].
  void _maybeAdoptCurrency(Map<String, Account> byId, String? id) {
    if (id == null) return;
    final picked = byId[id];
    if (picked == null) return;
    if (_currency == picked.currency) return;
    // Only auto-snap when the *other* slot is empty or already shares
    // the picked currency. Otherwise the user is explicitly mixing
    // currencies and we leave the picker on whatever they last set.
    final otherId = id == _fromAccountId ? _toAccountId : _fromAccountId;
    final other = otherId == null ? null : byId[otherId];
    if (other == null || other.currency == picked.currency) {
      _currency = picked.currency;
    }
  }

  bool _currencyMismatch(Account? from, Account? to, String currency) {
    if (from == null || to == null) return false;
    return from.currency != to.currency || from.currency != currency;
  }

  /// Live PostingsPreview source — produces a draft list mirroring
  /// what `_save()` will commit, so the user sees the exact ledger
  /// shape before pressing Transfer. Returns `null` while the form
  /// isn't yet fillable enough to render meaningful legs.
  List<Posting>? _buildPreview({
    required String? fromId,
    required String? toId,
    required Decimal? amount,
    required String currency,
  }) {
    if (fromId == null ||
        toId == null ||
        fromId == toId ||
        amount == null ||
        amount <= Decimal.zero) {
      return null;
    }
    // We only render same-currency previews here; cross-currency
    // forms ship in wave 3b alongside an explicit FX-rate input.
    final build = JournalEntryBuilders.transfer(
      date: _date,
      fromAccountId: fromId,
      toAccountId: toId,
      amount: amount,
      currency: currency,
      narration: _noteController.text.isEmpty ? null : _noteController.text,
    );
    return _materialise(build.entry, build.postings);
  }

  /// Adapt builder drafts into [Posting]s the read-only preview can
  /// consume. The repo would mint real ids + sync stamps on commit;
  /// the preview only needs the column shape for rendering, so we
  /// hand-roll a stub `SyncMeta` that never escapes this widget.
  List<Posting> _materialise(_, List<PostingDraft> drafts) {
    return [
      for (var i = 0; i < drafts.length; i++)
        Posting(
          id: 'preview-$i',
          journalEntryId: 'preview',
          position: drafts[i].position ?? i,
          accountId: drafts[i].accountId,
          units: drafts[i].units,
          unit: drafts[i].unit,
          cost: drafts[i].cost,
          price: drafts[i].price,
          sync: _previewSync,
        ),
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = readAmount(_amountController);
    if (amount == null ||
        amount <= Decimal.zero ||
        _fromAccountId == null ||
        _toAccountId == null) {
      Haptics.error();
      return;
    }
    setState(() => _busy = true);
    final repo = await ref.read(journalEntryRepositoryProvider.future);
    final note = _noteController.text.trim();
    final build = JournalEntryBuilders.transfer(
      date: _date,
      fromAccountId: _fromAccountId!,
      toAccountId: _toAccountId!,
      amount: amount,
      currency: _currency,
      narration: note.isEmpty ? null : note,
    );
    await submitOptimistic(
      pop: () => context.go('/accounts'),
      write: () => repo.create(
        entry: build.entry,
        postings: build.postings,
      ),
      failureMessage: (e) => switch (e) {
        JournalEntryUnbalancedException(:final message) =>
            'Transfer rejected: $message',
        _ => 'Transfer failed: $e',
      },
      retryLabel: 'Retry',
      tag: 'transfer-form',
    );
    if (mounted) setState(() => _busy = false);
  }
}
