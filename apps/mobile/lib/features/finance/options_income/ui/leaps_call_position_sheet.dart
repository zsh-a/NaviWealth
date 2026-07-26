import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/leaps_call_position.dart';

Future<void> showLeapsCallPositionSheet(
  BuildContext context, {
  String? existingId,
  String? symbol,
}) => showAppFormSheet<void>(
  context: context,
  builder: (_) =>
      _LeapsCallPositionForm(existingId: existingId, initialSymbol: symbol),
);

class _LeapsCallPositionForm extends ConsumerStatefulWidget {
  const _LeapsCallPositionForm({this.existingId, this.initialSymbol});

  final String? existingId;
  final String? initialSymbol;

  @override
  ConsumerState<_LeapsCallPositionForm> createState() =>
      _LeapsCallPositionFormState();
}

class _LeapsCallPositionFormState
    extends ConsumerState<_LeapsCallPositionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _symbol;
  late final TextEditingController _optionSymbol;
  late final TextEditingController _strike;
  late final TextEditingController _entryDebit;
  late final TextEditingController _exitCredit;
  late final TextEditingController _fees;
  late final TextEditingController _quantity;
  late final TextEditingController _multiplier;
  late final TextEditingController _mark;
  late final TextEditingController _delta;
  late final TextEditingController _notes;
  LeapsCallPosition? _loaded;
  LeapsCallStatus _status = LeapsCallStatus.open;
  DateTime _openedAt = DateTime.now().toUtc();
  DateTime _expirationAt = DateTime.now().toUtc().add(
    const Duration(days: 730),
  );
  DateTime? _closedAt;
  DateTime? _markedAt;
  String _currency = 'USD';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _symbol = TextEditingController(text: widget.initialSymbol ?? '');
    _optionSymbol = TextEditingController();
    _strike = TextEditingController();
    _entryDebit = TextEditingController();
    _exitCredit = TextEditingController();
    _fees = TextEditingController(text: '0');
    _quantity = TextEditingController(text: '1');
    _multiplier = TextEditingController(text: '100');
    _mark = TextEditingController();
    _delta = TextEditingController();
    _notes = TextEditingController();
    if (widget.existingId != null) unawaited(_load());
  }

  Future<void> _load() async {
    final repo = await ref.read(leapsCallPositionRepositoryProvider.future);
    final value = await repo.get(widget.existingId!);
    if (!mounted || value == null) return;
    setState(() {
      _loaded = value;
      _symbol.text = value.symbol;
      _optionSymbol.text = value.optionSymbol;
      _strike.text = value.strikePrice.toString();
      _entryDebit.text = value.entryDebit.toString();
      _exitCredit.text = value.exitCredit?.toString() ?? '';
      _fees.text = value.fees.toString();
      _quantity.text = value.contractQuantity.toString();
      _multiplier.text = value.contractSize.toString();
      _mark.text = value.currentMark?.toString() ?? '';
      _delta.text = value.currentDelta?.toString() ?? '';
      _notes.text = value.notes ?? '';
      _status = value.status;
      _openedAt = value.openedAt;
      _expirationAt = value.expirationAt;
      _closedAt = value.closedAt;
      _markedAt = value.markedAt;
      _currency = value.currency;
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _symbol,
      _optionSymbol,
      _strike,
      _entryDebit,
      _exitCredit,
      _fees,
      _quantity,
      _multiplier,
      _mark,
      _delta,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Decimal? _optionalDecimal(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : Decimal.parse(value);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_expirationAt.isAfter(_openedAt)) {
      AppMessenger.show(context, ToastKind.error, l10n.leapsOverlayDateInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(leapsCallPositionRepositoryProvider.future);
      final closedAt = _status == LeapsCallStatus.open
          ? null
          : (_closedAt ?? DateTime.now().toUtc());
      final mark = _optionalDecimal(_mark);
      final delta = _optionalDecimal(_delta);
      final notes = _notes.text.trim();
      if (_loaded == null) {
        await repo.create(
          symbol: _symbol.text,
          optionSymbol: _optionSymbol.text,
          openedAt: _openedAt,
          expirationAt: _expirationAt,
          closedAt: closedAt,
          strikePrice: Decimal.parse(_strike.text.trim()),
          entryDebit: Decimal.parse(_entryDebit.text.trim()),
          exitCredit: _optionalDecimal(_exitCredit),
          fees: Decimal.parse(_fees.text.trim()),
          currency: _currency,
          contractSize: int.parse(_multiplier.text.trim()),
          contractQuantity: int.parse(_quantity.text.trim()),
          status: _status,
          currentMark: mark,
          currentDelta: delta,
          markedAt: mark == null ? null : (_markedAt ?? DateTime.now().toUtc()),
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await repo.update(
          _loaded!.copyWith(
            symbol: _symbol.text.trim().toUpperCase(),
            optionSymbol: _optionSymbol.text.trim(),
            openedAt: _openedAt,
            expirationAt: _expirationAt,
            closedAt: closedAt,
            strikePrice: Decimal.parse(_strike.text.trim()),
            entryDebit: Decimal.parse(_entryDebit.text.trim()),
            exitCredit: _optionalDecimal(_exitCredit),
            fees: Decimal.parse(_fees.text.trim()),
            currency: _currency,
            contractSize: int.parse(_multiplier.text.trim()),
            contractQuantity: int.parse(_quantity.text.trim()),
            status: _status,
            currentMark: mark,
            currentDelta: delta,
            markedAt: mark == null
                ? null
                : (_markedAt ?? DateTime.now().toUtc()),
            notes: notes.isEmpty ? null : notes,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final value = _loaded;
    if (value == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.leapsOverlayDeleteTitle),
      body: Text(l10n.leapsOverlayDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(leapsCallPositionRepositoryProvider.future);
      await repo.remove(value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: _loaded == null ? l10n.leapsOverlayAdd : l10n.leapsOverlayEdit,
      subtitle: l10n.leapsOverlaySubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: l10n.incomePlannerSymbolLabel,
              controller: _symbol,
              validator: _required,
            ),
            _gap,
            _Field(
              label: l10n.leapsOverlayOptionSymbol,
              controller: _optionSymbol,
              validator: _required,
            ),
            _gap,
            DateField(
              label: l10n.leapsOverlayOpenedAt,
              initialValue: _openedAt,
              required: true,
              onChanged: (value) {
                if (value != null) setState(() => _openedAt = value.toUtc());
              },
            ),
            _gap,
            DateField(
              label: l10n.leapsOverlayExpiration,
              initialValue: _expirationAt,
              required: true,
              firstDate: _openedAt,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _expirationAt = value.toUtc());
                }
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(l10n.leapsOverlayDurationHint, style: context.captionStyle),
            _gap,
            CurrencyPicker(
              value: _currency,
              label: l10n.formCurrencyPickerLabelDefault,
              onChanged: (value) {
                if (value != null) setState(() => _currency = value);
              },
            ),
            _gap,
            _Field(
              label: l10n.leapsOverlayStrike,
              controller: _strike,
              numeric: true,
              validator: _positiveDecimal,
            ),
            _gap,
            _Field(
              label: l10n.leapsOverlayEntryDebit,
              controller: _entryDebit,
              numeric: true,
              validator: _positiveDecimal,
            ),
            _gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: l10n.incomePlannerJournalContractQuantityLabel,
                    controller: _quantity,
                    numeric: true,
                    validator: _positiveInt,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _Field(
                    label: l10n.incomePlannerJournalContractSizeLabel,
                    controller: _multiplier,
                    numeric: true,
                    validator: _positiveInt,
                  ),
                ),
              ],
            ),
            _gap,
            _Field(
              label: l10n.incomePlannerJournalFeesLabel,
              controller: _fees,
              numeric: true,
              validator: _nonNegativeDecimal,
            ),
            _gap,
            Text(l10n.leapsOverlayStatus, style: context.captionLabelStyle),
            const SizedBox(height: AppSpacing.s4),
            SegmentedRow<LeapsCallStatus>(
              options: LeapsCallStatus.values,
              value: _status,
              labelOf: (value) => _statusLabel(l10n, value),
              onChanged: (value) => setState(() {
                _status = value;
                _closedAt = value == LeapsCallStatus.open
                    ? null
                    : (_closedAt ?? DateTime.now().toUtc());
              }),
            ),
            AnimatedSizeFade(
              visible: _status != LeapsCallStatus.open,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s12),
                child: _Field(
                  label: l10n.leapsOverlayExitCredit,
                  controller: _exitCredit,
                  numeric: true,
                  validator: _status == LeapsCallStatus.closed
                      ? _nonNegativeDecimal
                      : null,
                ),
              ),
            ),
            _gap,
            _Field(
              label: l10n.leapsOverlayCurrentMark,
              controller: _mark,
              numeric: true,
              validator: _optionalNonNegativeDecimal,
            ),
            _gap,
            _Field(
              label: l10n.leapsOverlayCurrentDelta,
              controller: _delta,
              numeric: true,
              validator: _optionalDelta,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(l10n.leapsOverlayDeltaHint, style: context.captionStyle),
            _gap,
            _Field(
              label: l10n.incomePlannerJournalNotesLabel,
              controller: _notes,
              maxLines: 3,
            ),
            if (_loaded != null) ...[
              _gap,
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _busy ? null : _delete,
                child: Text(l10n.commonDelete),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: AppSpacing.s12);

  String? _required(String? value) => (value ?? '').trim().isEmpty
      ? AppLocalizations.of(context).commonRequiredField
      : null;

  String? _positiveDecimal(String? value) {
    final parsed = Decimal.tryParse((value ?? '').trim());
    return parsed == null || parsed <= Decimal.zero
        ? AppLocalizations.of(context).incomePlannerPositiveNumberValidation
        : null;
  }

  String? _nonNegativeDecimal(String? value) {
    final parsed = Decimal.tryParse((value ?? '').trim());
    return parsed == null || parsed < Decimal.zero
        ? AppLocalizations.of(context).formAmountFieldInvalid
        : null;
  }

  String? _optionalNonNegativeDecimal(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return _nonNegativeDecimal(value);
  }

  String? _optionalDelta(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = Decimal.tryParse(value!.trim());
    return parsed == null || parsed < Decimal.zero || parsed > Decimal.one
        ? AppLocalizations.of(context).leapsOverlayDeltaInvalid
        : null;
  }

  String? _positiveInt(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    return parsed == null || parsed <= 0
        ? AppLocalizations.of(context).incomePlannerPositiveNumberValidation
        : null;
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.maxLines = 1,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool numeric;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.captionLabelStyle),
      const SizedBox(height: AppSpacing.s4),
      FTextFormField(
        control: FTextFieldControl.managed(controller: controller),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        maxLines: maxLines,
        validator: validator,
      ),
    ],
  );
}

String _statusLabel(AppLocalizations l10n, LeapsCallStatus status) =>
    switch (status) {
      LeapsCallStatus.open => l10n.leapsOverlayStatusOpen,
      LeapsCallStatus.closed => l10n.leapsOverlayStatusClosed,
      LeapsCallStatus.exercised => l10n.leapsOverlayStatusExercised,
      LeapsCallStatus.expired => l10n.leapsOverlayStatusExpired,
    };
