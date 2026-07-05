import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/core/ai/visual/ai_hover_overlay.dart';
import 'package:naviwealth/core/ai/visual/ai_object_capsule.dart';
import 'package:naviwealth/core/ai/write/write.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
    with
        OptimisticFormSubmit<ExpenseFormPage>,
        FormDirtyGuard<ExpenseFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.activityExpenses;

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
    dirty.bindTextControllers([_amountController, _noteController]);
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
      popOrGo(context, fallback: FinanceRoutes.activityExpenses);
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
    // Hydrating an existing record is not a user edit.
    dirty.snapshotBaseline();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final amount = readAmount(_amountController);
    if (amount == null || amount <= Decimal.zero) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.expenseFormAmountInvalid,
      );
      return;
    }
    final fromAccountId = _fromAccountId;
    final expenseAccountId = _expenseAccountId;
    final currency = _currency;
    if (expenseAccountId == null || fromAccountId == null || currency == null) {
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
    // The record is being persisted — the post-save pop must not prompt.
    dirty.markPristine();
    await submitOptimisticAndLeave(
      leaveFallback: FinanceRoutes.activityExpenses,
      onBeforeLeave: Haptics.success,
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
      dirty.markPristine();
      popOrGo(context, fallback: FinanceRoutes.activityExpenses);
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

  /// Build the human label for the AI capsule.
  /// Prefer the user's note → category name → generic fallback. The
  /// label feeds both the prompt template and the sheet header so it
  /// should read as a noun phrase.
  String _objectLabelForCapsule(AppLocalizations l10n) {
    final note = _noteController.text.trim();
    if (note.isNotEmpty) return note;
    return l10n.expenseFormEditTitle;
  }

  String _pageTitle(AppLocalizations l10n, List<Account>? allAccounts) {
    if (!widget.isEdit) return l10n.expenseFormCreateTitle;
    if (_initial == null) return l10n.expenseFormEditTitle;
    // Show "Edit · Category  ¥120" after the existing record is loaded.
    final parts = <String>[l10n.expenseFormEditTitle];
    if (allAccounts != null && _expenseAccountId != null) {
      final cat = allAccounts
          .where((a) => a.id == _expenseAccountId)
          .firstOrNull;
      if (cat != null) parts.add(cat.name);
    }
    final amountText = _amountController.text.trim();
    if (amountText.isNotEmpty) {
      parts.add(amountText);
    }
    return parts.join(' · ');
  }

  List<Account> _leafAccounts(List<Account> accounts) {
    final parentIds = {
      for (final account in accounts)
        if (account.parentId != null) account.parentId!,
    };
    return accounts
        .where((account) => !parentIds.contains(account.id))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadingExisting = widget.isEdit && _initial == null;
    final allAccountsAsync = ref.watch(allAccountsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(_pageTitle(l10n, allAccountsAsync.value)),
        confirmLeave: handleBackIntent,
        actions: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(FLucideIcons.trash2),
              onPress: _busy ? null : _delete,
            ),
        ],
        child: loadingExisting
            ? const Center(child: FCircularProgress())
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: AiHoverOverlay(
                  capsule: widget.isEdit && widget.expenseId != null
                      ? AiObjectCapsule(
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
                        )
                      : const SizedBox.shrink(),
                  topOffset: 8,
                  endOffset: 16,
                  child: AppFormScaffoldBody(
                    action: SizedBox(
                      width: double.infinity,
                      child: FButton(
                        variant: FButtonVariant.primary,
                        onPress: _busy ? null : _save,
                        child: Text(
                          _busy ? l10n.commonSaving : l10n.commonSave,
                        ),
                      ),
                    ),
                    children: [
                      if (widget.isEdit && widget.expenseId != null) ...[
                        // AiTouchMark: shows when this expense was last
                        // touched by an AI proposal. Self-gating: hidden
                        // when there's no recent touch.
                        AiTouchMark(
                          entityType: 'journal_entries',
                          entityId: widget.expenseId!,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                      ],
                      AmountField(
                        label: l10n.expenseFormAmountLabel,
                        controller: _amountController,
                        currencyCode: _currency,
                        focusNode: _amountFocus,
                        onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      CurrencyPicker(
                        value: _currency,
                        onChanged: (v) => setState(() {
                          _currency = v;
                          dirty.markDirty();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      allAccountsAsync.when(
                        data: (allAccounts) {
                          final expenseAccounts = allAccounts
                              .where((a) => a.category == AccountSide.expense)
                              .toList(growable: false);
                          final selectableExpenseAccounts = _leafAccounts(
                            expenseAccounts,
                          );
                          if (selectableExpenseAccounts.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s12,
                              ),
                              child: Text(l10n.expenseFormCategoriesLoading),
                            );
                          }
                          // Resolve default: explicit pick > first leaf category.
                          if (_expenseAccountId == null ||
                              !selectableExpenseAccounts.any(
                                (a) => a.id == _expenseAccountId,
                              )) {
                            _expenseAccountId =
                                selectableExpenseAccounts.first.id;
                          }
                          return AccountTreePicker(
                            accounts: expenseAccounts,
                            value: _expenseAccountId,
                            onChanged: (id) {
                              if (id == null) return;
                              setState(() {
                                _expenseAccountId = id;
                                dirty.markDirty();
                              });
                            },
                            category: AccountSide.expense,
                            label: l10n.expenseCategoryPickerLabelDefault,
                            leafOnly: true,
                            validator: (id) => id == null || id.isEmpty
                                ? l10n.expenseCategoryPickerRequired
                                : null,
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.s12,
                          ),
                          child: FProgress(),
                        ),
                        error: (e, _) =>
                            Text(l10n.expenseFormCategoriesLoadError('$e')),
                      ),
                      const SizedBox(height: AppSpacing.s12),
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
                            onChanged: (v) => setState(() {
                              _fromAccountId = v;
                              dirty.markDirty();
                            }),
                            label: l10n.expenseFormAccountLabel,
                          );
                        },
                        loading: () => const FProgress(),
                        error: (e, _) =>
                            Text(l10n.expenseFormAccountsLoadError('$e')),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      DateField(
                        label: l10n.expenseFormDateLabel,
                        initialValue: _date,
                        required: true,
                        includeTime: true,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _date = v;
                              dirty.markDirty();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      NoteField(
                        controller: _noteController,
                        focusNode: _noteFocus,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _NoAccountsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s14,
        AppSpacing.s14,
        AppSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: semantic.warning.withValues(alpha: AppOpacity.medium),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              FLucideIcons.wallet,
              size: AppIconSizes.h18,
              color: semantic.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.expenseFormNoAccountsTitle,
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.expenseFormNoAccountsBody,
                  style: context.captionStyle.copyWith(height: 1.4),
                ),
                const SizedBox(height: AppSpacing.s10),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => context.push(FinanceRoutes.wealthAccountNew),
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
