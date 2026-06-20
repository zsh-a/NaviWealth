import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../settings/data/base_currency_preference.dart';
import '../../shared/forms/forms.dart';
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
    extends ConsumerState<_RecurringTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '1');
  final _byMonthDayCtrl = TextEditingController();

  _RecurringKind _kind = _RecurringKind.income;
  String? _currency;
  String? _cashAccountId;
  String? _counterAccountId;
  late DateTime _start;
  RecurrenceFrequency _freq = RecurrenceFrequency.monthly;
  DateTime? _until;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
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
            _Segmented<_RecurringKind>(
              label: l10n.recurringFieldKind,
              value: _kind,
              options: {
                _RecurringKind.income: l10n.recurringKindIncome,
                _RecurringKind.expense: l10n.recurringKindExpense,
              },
              onChanged: (v) => setState(() {
                _kind = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _amountCtrl),
              label: Text(l10n.recurringFieldAmount),
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
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            AccountPicker(
              accounts: accounts,
              value: _cashAccountId,
              label: l10n.recurringFieldCashAccount,
              onChanged: (v) => setState(() {
                _cashAccountId = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            AccountPicker(
              accounts: accounts,
              value: _counterAccountId,
              label: l10n.recurringFieldCategoryAccount,
              onChanged: (v) => setState(() {
                _counterAccountId = v;
                widget.dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s12),
            NoteField(controller: _noteCtrl, label: l10n.recurringFieldNote),
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
            FTextFormField(
              control: FTextFieldControl.managed(controller: _intervalCtrl),
              label: Text(l10n.recurringFieldInterval),
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
                control: FTextFieldControl.managed(controller: _byMonthDayCtrl),
                label: Text(l10n.recurringFieldByMonthDay),
                description: Text(l10n.recurringFieldByMonthDayHelper),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
          ],
        ),
      ),
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
    if (!_formKey.currentState!.validate()) return;
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
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final amount = Decimal.parse(_amountCtrl.text.trim());
      final cashUnits = _kind == _RecurringKind.income ? amount : -amount;
      final narration = _noteCtrl.text.trim().isEmpty
          ? l10n.recurringDefaultNarration
          : _noteCtrl.text.trim();
      final build = JournalEntryBuild(
        entry: JournalEntryDraft(date: _start, narration: narration),
        postings: [
          PostingDraft(
            position: 0,
            accountId: _cashAccountId!,
            units: cashUnits,
            unit: currency,
          ),
          PostingDraft(
            position: 1,
            accountId: _counterAccountId!,
            units: -cashUnits,
            unit: currency,
          ),
        ],
      );
      final json = JournalBuildTemplateCodec.encode(build);
      final rrule = _buildRrule();
      final repo = await ref.read(
        recurringTransactionRepositoryProvider.future,
      );
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          templateJournalBuildJson: json,
          rrule: rrule,
          nextDueAt: _start,
        );
      } else {
        await repo.update(
          existing.id,
          templateJournalBuildJson: json,
          rrule: rrule,
          nextDueAt: _start,
        );
      }
      if (!mounted) return;
      widget.dirty.markPristine();
      Haptics.success();
      Navigator.of(context).pop();
    } on RecurrenceParseException catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.recurringSaveFailed);
      }
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.recurringSaveFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
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
