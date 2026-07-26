import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/recurring_transaction_providers.dart';
import '../data/recurring_transaction_repository.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';

enum _RecurringKind { income, expense }

/// Create or edit a recurring income / expense rule.
///
/// The rule's amount, accounts and narration are synthesized into a
/// balanced two-leg [JournalEntryBuild] and stored as the opaque
/// `templateJournalBuildJson`; the recurrence is built into an RRULE
/// string (the user never sees raw RFC 5545).
Future<void> showRecurringTransactionForm(
  BuildContext context,
  WidgetRef ref, {
  RecurringTransaction? existing,
}) {
  return showGuardedFormSheet<void>(
    context: context,
    builder: (_, dirty) =>
        _RecurringTransactionSheet(existing: existing, dirty: dirty),
  );
}

class _RecurringTransactionSheet extends ConsumerStatefulWidget {
  const _RecurringTransactionSheet({required this.dirty, this.existing});

  final FormDirtyController dirty;
  final RecurringTransaction? existing;

  @override
  ConsumerState<_RecurringTransactionSheet> createState() =>
      _RecurringTransactionSheetState();
}

class _RecurringTransactionSheetState
    extends ConsumerState<_RecurringTransactionSheet>
    with FormSubmission<_RecurringTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '1');
  final _byMonthDayCtrl = TextEditingController();
  final _detailsFocus = FocusNode(debugLabel: 'recurring-details');

  _RecurringKind _kind = _RecurringKind.income;
  String? _currency;
  String? _cashAccountId;
  String? _counterAccountId;
  late DateTime _start;
  RecurrenceFrequency _freq = RecurrenceFrequency.monthly;
  DateTime? _until;
  bool _detailsExpanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _start = DateTime.utc(now.year, now.month, now.day);
    final existing = widget.existing;
    if (existing == null) {
      _currency = ref.read(baseCurrencyProvider);
      widget.dirty.bindTextControllers([
        _amountCtrl,
        _noteCtrl,
        _intervalCtrl,
        _byMonthDayCtrl,
      ]);
      return;
    }
    try {
      final template = JournalBuildTemplateCodec.decode(
        existing.templateJournalBuildJson,
      );
      final cash = template.postings.isNotEmpty
          ? template.postings.first
          : null;
      final counter = template.postings.length > 1
          ? template.postings[1]
          : null;
      if (cash != null) {
        _kind = cash.units > Decimal.zero
            ? _RecurringKind.income
            : _RecurringKind.expense;
        _amountCtrl.text = cash.units.abs().toString();
        _currency = cash.unit;
        _cashAccountId = cash.accountId;
      }
      _counterAccountId = counter?.accountId;
      _noteCtrl.text = template.entry.narration;
      final rule = const RecurrenceEngine().parse(existing.rrule);
      _freq = rule.frequency;
      _intervalCtrl.text = rule.interval.toString();
      if (rule.byMonthDay != null) {
        _byMonthDayCtrl.text = rule.byMonthDay.toString();
      }
      _until = rule.until;
    } catch (_) {
      // Corrupt template/rrule — fall back to a blank form so the user
      // can re-enter and overwrite it.
      _currency = ref.read(baseCurrencyProvider);
    }
    _start = existing.nextDueAt;
    // Bind after the hydrate so loading an existing recurrence is not a
    // user edit.
    widget.dirty.bindTextControllers([
      _amountCtrl,
      _noteCtrl,
      _intervalCtrl,
      _byMonthDayCtrl,
    ]);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _intervalCtrl.dispose();
    _byMonthDayCtrl.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final currency = _currency?.toUpperCase();
    final cashAccounts = accounts
        .where(
          (account) =>
              !account.archived &&
              account.category == AccountSide.asset &&
              (currency == null || account.currency.toUpperCase() == currency),
        )
        .toList(growable: false);
    final counterSide = _kind == _RecurringKind.income
        ? AccountSide.income
        : AccountSide.expense;
    final counterAccounts = accounts
        .where(
          (account) =>
              !account.archived &&
              account.category == counterSide &&
              (currency == null || account.currency.toUpperCase() == currency),
        )
        .toList(growable: false);
    final isMonthly =
        _freq == RecurrenceFrequency.monthly ||
        _freq == RecurrenceFrequency.yearly;
    return AppSheet(
      title: widget.existing == null
          ? l10n.recurringFormNewTitle
          : l10n.recurringFormEditTitle,
      subtitle: l10n.recurringFormSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.recurringFormSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
        busy: _saving,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (submissionFailureMessage != null) ...[
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: submissionFailureMessage!,
                compact: true,
              ),
              const SizedBox(height: AppSpacing.s12),
            ],
            _Segmented<_RecurringKind>(
              label: l10n.recurringFieldKind,
              value: _kind,
              options: {
                _RecurringKind.income: l10n.recurringKindIncome,
                _RecurringKind.expense: l10n.recurringKindExpense,
              },
              onChanged: (v) => setState(() {
                _kind = v;
                _counterAccountId = null;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _amountCtrl),
              label: RequiredLabel(l10n.recurringFieldAmount),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return l10n.recurringValidationRequired;
                final parsed = Decimal.tryParse(text);
                if (parsed == null || parsed <= Decimal.zero) {
                  return l10n.recurringValidationPositive;
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            CurrencyPicker(
              value: _currency,
              onChanged: (v) => setState(() {
                _currency = v;
                _cashAccountId = null;
                _counterAccountId = null;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            AccountPicker(
              accounts: cashAccounts,
              value: _cashAccountId,
              label: l10n.recurringFieldCashAccount,
              onChanged: (v) => setState(() {
                _cashAccountId = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            AccountPicker(
              accounts: counterAccounts,
              value: _counterAccountId,
              label: l10n.recurringFieldCategoryAccount,
              onChanged: (v) => setState(() {
                _counterAccountId = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              label: l10n.recurringFieldStart,
              initialValue: _start,
              required: true,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _start = v.toUtc();
                    widget.dirty.markDirty();
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            _Segmented<RecurrenceFrequency>(
              label: l10n.recurringFieldFrequency,
              value: _freq,
              options: {
                RecurrenceFrequency.daily: l10n.recurringFreqDaily,
                RecurrenceFrequency.weekly: l10n.recurringFreqWeekly,
                RecurrenceFrequency.monthly: l10n.recurringFreqMonthly,
                RecurrenceFrequency.yearly: l10n.recurringFreqYearly,
              },
              onChanged: (v) => setState(() {
                _freq = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            _buildDetailsDisclosure(l10n, isMonthly: isMonthly),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsDisclosure(
    AppLocalizations l10n, {
    required bool isMonthly,
  }) {
    final configured =
        _noteCtrl.text.trim().isNotEmpty ||
        _intervalCtrl.text.trim() != '1' ||
        _byMonthDayCtrl.text.trim().isNotEmpty ||
        _until != null;
    return FAccordion(
      control: FAccordionControl.lifted(
        expanded: (_) => _detailsExpanded,
        onChange: (_, expanded) => setState(() => _detailsExpanded = expanded),
      ),
      children: [
        FAccordionItem(
          key: const Key('recurring-details-disclosure'),
          focusNode: _detailsFocus,
          title: Semantics(
            key: const Key('recurring-details-toggle-label'),
            expanded: _detailsExpanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.recurringFormDetailsTitle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  configured
                      ? l10n.recurringFormDetailsConfigured
                      : l10n.recurringFormDetailsSummary,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          child: Offstage(
            key: const Key('recurring-details-fields'),
            offstage: !_detailsExpanded,
            child: ExcludeFocus(
              excluding: !_detailsExpanded,
              child: ExcludeSemantics(
                excluding: !_detailsExpanded,
                child: Column(
                  children: [
                    FTextFormField(
                      key: const Key('recurring-interval-field'),
                      control: FTextFieldControl.managed(
                        controller: _intervalCtrl,
                      ),
                      label: RequiredLabel(l10n.recurringFieldInterval),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        final n = int.tryParse((value ?? '').trim());
                        if (n == null || n <= 0) {
                          return l10n.recurringValidationInterval;
                        }
                        return null;
                      },
                    ),
                    if (isMonthly) ...[
                      const SizedBox(height: AppSpacing.s12),
                      FTextFormField(
                        control: FTextFieldControl.managed(
                          controller: _byMonthDayCtrl,
                        ),
                        label: Text(l10n.recurringFieldByMonthDay),
                        description: Text(l10n.recurringFieldByMonthDayHelper),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          final d = int.tryParse(text);
                          if (d == null || d < 1 || d > 31) {
                            return l10n.recurringValidationByMonthDay;
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s12),
                    DateField(
                      label: l10n.recurringFieldUntil,
                      initialValue: _until,
                      helperText: l10n.recurringFieldUntilHelper,
                      onChanged: (v) => setState(() {
                        _until = v?.toUtc();
                        widget.dirty.markDirty();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    NoteField(
                      controller: _noteCtrl,
                      label: l10n.recurringFieldNote,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildRrule() {
    final freq = switch (_freq) {
      RecurrenceFrequency.daily => 'DAILY',
      RecurrenceFrequency.weekly => 'WEEKLY',
      RecurrenceFrequency.monthly => 'MONTHLY',
      RecurrenceFrequency.yearly => 'YEARLY',
    };
    final buffer = StringBuffer('FREQ=$freq');
    final interval = int.tryParse(_intervalCtrl.text.trim()) ?? 1;
    buffer.write(';INTERVAL=$interval');
    final byMonthDay = int.tryParse(_byMonthDayCtrl.text.trim());
    final wantsByMonthDay =
        _freq == RecurrenceFrequency.monthly ||
        _freq == RecurrenceFrequency.yearly;
    if (wantsByMonthDay && byMonthDay != null) {
      buffer.write(';BYMONTHDAY=$byMonthDay');
    }
    final until = _until;
    if (until != null) {
      final y = until.year.toString().padLeft(4, '0');
      final m = until.month.toString().padLeft(2, '0');
      final d = until.day.toString().padLeft(2, '0');
      buffer.write(';UNTIL=$y$m$d');
    }
    return buffer.toString();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      if (!_detailsAreValid && !_detailsExpanded) {
        setState(() => _detailsExpanded = true);
      }
      return;
    }
    if (_cashAccountId == null || _counterAccountId == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationAccounts,
      );
      return;
    }
    if (_cashAccountId == _counterAccountId) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationSameAccount,
      );
      return;
    }
    final currency = _currency;
    if (currency == null || currency.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationCurrency,
      );
      return;
    }
    final amount = Decimal.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= Decimal.zero) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationPositive,
      );
      return;
    }
    final cashAccountId = _cashAccountId!;
    final counterAccountId = _counterAccountId!;
    final accounts =
        ref.read(accountsStreamProvider).value ?? const <Account>[];
    final byId = {for (final account in accounts) account.id: account};
    final cashAccount = byId[cashAccountId];
    final counterAccount = byId[counterAccountId];
    final expectedCounterSide = _kind == _RecurringKind.income
        ? AccountSide.income
        : AccountSide.expense;
    if (cashAccount == null ||
        cashAccount.category != AccountSide.asset ||
        cashAccount.currency.toUpperCase() != currency.toUpperCase() ||
        counterAccount == null ||
        counterAccount.category != expectedCounterSide ||
        counterAccount.currency.toUpperCase() != currency.toUpperCase()) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationAccounts,
      );
      return;
    }
    final cashUnits = _kind == _RecurringKind.income ? amount : -amount;
    final note = _noteCtrl.text.trim();
    final narration = note.isEmpty ? l10n.recurringDefaultNarration : note;
    final start = _start;
    final existing = widget.existing;
    final build = JournalEntryBuild(
      entry: JournalEntryDraft(date: start, narration: narration),
      postings: [
        PostingDraft(
          position: 0,
          accountId: cashAccountId,
          units: cashUnits,
          unit: currency,
        ),
        PostingDraft(
          position: 1,
          accountId: counterAccountId,
          units: -cashUnits,
          unit: currency,
        ),
      ],
    );
    final json = JournalBuildTemplateCodec.encode(build);
    final rrule = _buildRrule();
    final rule = const RecurrenceEngine().parse(rrule);
    final nextDueAt = const RecurrenceEngine().firstOnOrAfter(rule, start);
    if (rule.until case final until? when nextDueAt.isAfter(until)) {
      if (!_detailsExpanded) setState(() => _detailsExpanded = true);
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.recurringValidationUntilBeforeStart,
      );
      return;
    }
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      failureMessage: (_) => l10n.recurringSaveFailed,
      successMessage: l10n.commonSaved,
      leave: () => Navigator.of(context).pop(),
      tag: 'recurring-transaction',
      commit: () async {
        final repo = await ref.read(
          recurringTransactionRepositoryProvider.future,
        );
        if (existing == null) {
          await repo.create(
            templateJournalBuildJson: json,
            rrule: rrule,
            nextDueAt: nextDueAt,
          );
        } else {
          await repo.update(
            existing.id,
            templateJournalBuildJson: json,
            rrule: rrule,
            nextDueAt: nextDueAt,
          );
        }
        final now = DateTime.now().toUtc();
        final today = DateTime.utc(now.year, now.month, now.day);
        ref.invalidate(recurringMaterialiseDueProvider(today));
        await ref.read(recurringMaterialiseDueProvider(today).future);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  bool get _detailsAreValid {
    final interval = int.tryParse(_intervalCtrl.text.trim());
    if (interval == null || interval <= 0) return false;
    final text = _byMonthDayCtrl.text.trim();
    if (text.isEmpty ||
        (_freq != RecurrenceFrequency.monthly &&
            _freq != RecurrenceFrequency.yearly)) {
      return true;
    }
    final day = int.tryParse(text);
    return day != null && day >= 1 && day <= 31;
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.mutedLabelStyle),
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final entry in options.entries)
              FButton(
                variant: entry.key == value
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                onPress: () => onChanged(entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      ],
    );
  }
}
