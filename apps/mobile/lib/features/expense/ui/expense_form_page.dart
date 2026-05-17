import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/intent/intent.dart';
import '../../../core/ai/write/write.dart';
import '../../../core/haptics/haptics.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/journal_entry_builders.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ai_object_capsule.dart';
import '../../shared/forms/forms.dart';
import 'category_grid_picker.dart';

/// Quick-entry page for a single expense. Shared between create and
/// edit flows — when [expenseId] is non-null we hydrate the form from
/// the journal entry the id refers to and call `replacePostings` on
/// save; otherwise we call `JournalEntryRepository.create`.
class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({super.key, this.expenseId});

  final String? expenseId;

  bool get isEdit => expenseId != null;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage>
    with OptimisticFormSubmit<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();

  /// The expense account id (from the `accounts` table where category=expense).
  String? _expenseAccountId;
  String? _fromAccountId;
  String? _currency = 'CNY';
  DateTime _date = DateTime.now();
  bool _busy = false;
  JournalEntryWithPostings? _initial;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _loadInitial();
    } else {
      final defaults = ref.read(formDefaultsProvider);
      _fromAccountId = defaults.expenseAccountId;
      _expenseAccountId = defaults.expenseCategoryId;
      if (defaults.expenseCurrency != null &&
          defaults.expenseCurrency!.isNotEmpty) {
        _currency = defaults.expenseCurrency;
      }
    }
  }

  Future<void> _loadInitial() async {
    final journalRepo = await ref.read(journalEntryRepositoryProvider.future);
    final existing = await journalRepo.getById(widget.expenseId!);
    if (existing == null) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      AppMessenger.show(context, ToastKind.error, l10n.expenseFormLoadError);
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    if (!mounted) return;
    String? expenseAccountId;
    String? fromAccountId;
    Decimal amount = Decimal.zero;
    String currency = 'CNY';
    for (final p in existing.postings) {
      if (p.units > Decimal.zero) {
        expenseAccountId = p.accountId;
        amount = p.units;
        currency = p.unit;
      } else {
        fromAccountId = p.accountId;
      }
    }
    setState(() {
      _initial = existing;
      _amountController.text = amount.toString();
      _noteController.text = existing.entry.narration;
      _expenseAccountId = expenseAccountId;
      _fromAccountId = fromAccountId;
      _currency = currency;
      _date = existing.entry.date;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormAmountInvalid,
      );
      return;
    }
    if (_expenseAccountId == null ||
        _fromAccountId == null ||
        _currency == null) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormCategoryAccountRequired,
      );
      return;
    }
    setState(() => _busy = true);
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final fromAccountId = _fromAccountId!;
    final expenseAccountId = _expenseAccountId!;
    final currency = _currency!;
    final date = _date;
    final initial = _initial;
    if (!mounted) return;
    unawaited(
      ref
          .read(formDefaultsProvider.notifier)
          .rememberExpense(
            accountId: fromAccountId,
            categoryId: expenseAccountId,
            currency: currency,
          ),
    );
    await submitOptimistic(
      pop: () {
        Haptics.success();
        context.go(AppRoutes.activityExpenses);
      },
      tag: 'expense',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () async {
        final journalRepo = await ref.read(
          journalEntryRepositoryProvider.future,
        );
        final build = JournalEntryBuilders.expense(
          date: date,
          expenseAccountId: expenseAccountId,
          fromAccountId: fromAccountId,
          amount: amount,
          currency: currency,
          narration: note,
        );
        if (initial == null) {
          await journalRepo.create(
            entry: build.entry,
            postings: build.postings,
          );
        } else {
          await journalRepo.replacePostings(
            id: initial.entry.id,
            entry: build.entry,
            postings: build.postings,
          );
        }
      },
    );
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context: context,
      title: Text(l10n.expenseFormDeleteDialogTitle),
      body: Text(l10n.expenseFormDeleteDialogBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final journalRepo = await ref.read(journalEntryRepositoryProvider.future);
      await journalRepo.softDelete(_initial!.entry.id);
      if (!mounted) return;
      context.go(AppRoutes.activityExpenses);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Build the human label for the AI capsule (Wave 33 proof point).
  /// Prefer the user's note → category name → generic fallback. The
  /// label feeds both the prompt template and the sheet header so it
  /// should read as a noun phrase.
  String _objectLabelForCapsule(AppLocalizations l10n) {
    final note = _noteController.text.trim();
    if (note.isNotEmpty) return note;
    return l10n.expenseFormEditTitle;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadingExisting = widget.isEdit && _initial == null;
    final allAccountsAsync = ref.watch(allAccountsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(
          widget.isEdit
              ? l10n.expenseFormEditTitle
              : l10n.expenseFormCreateTitle,
        ),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(Icons.delete_outline),
              onPress: _busy ? null : _delete,
            ),
        ],
      ),
      childPad: false,
      child: loadingExisting
          ? const Center(child: FCircularProgress())
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (widget.isEdit && widget.expenseId != null) ...[
                    Row(
                      children: [
                        AiObjectCapsule(
                          source: 'expense_detail',
                          intent: 'explain_change',
                          object: AiObjectRef(
                            type: 'expense',
                            id: widget.expenseId!,
                          ),
                          objectLabel: _objectLabelForCapsule(l10n),
                          context: <String, Object?>{
                            'timeframe':
                                l10n.expenseFormAiTimeframeRecent90Days,
                          },
                        ),
                        const SizedBox(width: 8),
                        // Wave 39 / 40 — AiTouchMark when this
                        // expense was last touched by an AI proposal
                        // apply. The widget is self-gating: nothing
                        // renders when there's no recent touch.
                        AiTouchMark(
                          entityType: 'journal_entries',
                          entityId: widget.expenseId!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  AmountField(
                    label: l10n.expenseFormAmountLabel,
                    controller: _amountController,
                    currencyCode: _currency,
                    focusNode: _amountFocus,
                    onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),
                  CurrencyPicker(
                    value: _currency,
                    onChanged: (v) => setState(() => _currency = v),
                  ),
                  const SizedBox(height: 8),
                  allAccountsAsync.when(
                    data: (allAccounts) {
                      final expenseAccounts = allAccounts
                          .where((a) => a.category == AccountSide.expense)
                          .toList(growable: false);
                      if (expenseAccounts.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(l10n.expenseFormCategoriesLoading),
                        );
                      }
                      // Resolve default: explicit pick > first account
                      if (_expenseAccountId == null ||
                          !expenseAccounts.any(
                            (a) => a.id == _expenseAccountId,
                          )) {
                        _expenseAccountId = expenseAccounts.first.id;
                      }
                      return CategoryGridPicker(
                        accounts: expenseAccounts,
                        selectedId: _expenseAccountId,
                        onSelect: (id) =>
                            setState(() => _expenseAccountId = id),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: FProgress(),
                    ),
                    error: (e, _) =>
                        Text(l10n.expenseFormCategoriesLoadError('$e')),
                  ),
                  const SizedBox(height: 12),
                  accountsAsync.when(
                    data: (accounts) {
                      final fromAccounts = accounts
                          .where(
                            (a) =>
                                a.category == AccountSide.asset &&
                                a.type != AccountCategory.asset,
                          )
                          .toList(growable: false);
                      if (fromAccounts.isEmpty) {
                        return _NoAccountsHint();
                      }
                      final hasCurrent =
                          _fromAccountId != null &&
                          fromAccounts.any((a) => a.id == _fromAccountId);
                      if (!hasCurrent) {
                        _fromAccountId = fromAccounts.first.id;
                      }
                      return AccountPicker(
                        accounts: fromAccounts,
                        value: _fromAccountId,
                        onChanged: (v) => setState(() => _fromAccountId = v),
                        label: l10n.expenseFormAccountLabel,
                      );
                    },
                    loading: () => const FProgress(),
                    error: (e, _) =>
                        Text(l10n.expenseFormAccountsLoadError('$e')),
                  ),
                  const SizedBox(height: 12),
                  DateField(
                    label: l10n.expenseFormDateLabel,
                    initialValue: _date,
                    required: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _date = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  NoteField(controller: _noteController, focusNode: _noteFocus),
                  const SizedBox(height: 24),
                  FButton(
                    variant: FButtonVariant.primary,
                    onPress: _busy ? null : _save,
                    child: Text(_busy ? l10n.commonSaving : l10n.commonSave),
                  ),
                ],
              ),
            ),
    );
  }
}

class _NoAccountsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: semantic.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: semantic.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.expenseFormNoAccountsTitle,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.expenseFormNoAccountsBody,
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () =>
                      GoRouter.of(context).go(AppRoutes.accountListNew),
                  child: Text(l10n.expenseFormNoAccountsCta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
