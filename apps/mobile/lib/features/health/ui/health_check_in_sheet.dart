import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/format/providers.dart';
import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_check_in_providers.dart';
import '../data/health_series.dart';
import '../domain/health_check_in.dart';
import 'health_check_in_presentation.dart';

Future<bool?> showHealthCheckInSheet({
  required BuildContext context,
  required DateTime day,
  HealthCheckIn? entry,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => HealthCheckInSheet(day: day, entry: entry, dirty: dirty),
  ).whenComplete(dirty.dispose);
}

/// Choose the date before loading its existing entry, so backfilling cannot
/// silently overwrite a previous check-in with a blank form.
Future<void> showHealthCheckInDateSheet({
  required BuildContext context,
  required DateTime today,
}) async {
  final l = AppLocalizations.of(context);
  var date = healthDay(today);
  final selected = await showAppFormSheet<DateTime>(
    context: context,
    builder: (sheetContext) => AppSheet(
      title: l.healthCheckInRecordDay,
      footer: AppSheetFooter(
        submitLabel: l.commonConfirm,
        cancelLabel: l.commonCancel,
        onSubmit: () => Navigator.of(sheetContext).pop(date),
      ),
      child: FDateField.calendar(
        label: Text(l.commonDate),
        clearable: false,
        selectionControl: FDateSelectionControl.managedSingle(
          initial: date,
          onChange: (value) {
            if (value != null) date = healthDay(value);
          },
        ),
        calendar: FDateFieldGridCalendarProperties(
          control: FGridCalendarControl(
            start: DateTime.utc(1970),
            end: healthDay(today).add(const Duration(days: 1)),
            today: healthDay(today),
          ),
        ),
      ),
    ),
  );
  if (context.mounted && selected != null) {
    await showHealthCheckInSheet(context: context, day: selected);
  }
}

class HealthCheckInSheet extends ConsumerStatefulWidget {
  const HealthCheckInSheet({
    super.key,
    required this.day,
    required this.dirty,
    this.entry,
  });
  final DateTime day;
  final FormDirtyController dirty;
  final HealthCheckIn? entry;
  @override
  ConsumerState<HealthCheckInSheet> createState() => _HealthCheckInSheetState();
}

class _HealthCheckInSheetState extends ConsumerState<HealthCheckInSheet>
    with FormSubmission<HealthCheckInSheet> {
  final _note = TextEditingController();
  final _tags = <String>{};
  int? _energy;
  int? _sleepQuality;
  int? _stress;
  HealthCheckIn? _entry;
  String? _owner;
  bool _loading = true;
  bool _saving = false;
  Object? _loadError;
  bool _bound = false;
  bool _showNote = false;
  String? _validation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final owner = await ref.read(currentUserIdProvider)();
      final repo = await ref.read(healthCheckInRepositoryProvider.future);
      final entry =
          widget.entry ??
          await repo.findDay(ownerUserId: owner, day: widget.day);
      if (!mounted) return;
      if (entry != null && entry.sync.ownerUserId != owner) {
        throw StateError('Check-in belongs to another user.');
      }
      _owner = owner;
      _entry = entry;
      _energy = entry?.energy;
      _sleepQuality = entry?.sleepQuality;
      _stress = entry?.stress;
      _tags
        ..clear()
        ..addAll(entry?.tags ?? const []);
      _note.text = entry?.note ?? '';
      _showNote = _note.text.isNotEmpty;
      if (!_bound) {
        widget.dirty.bindTextControllers([_note]);
        _bound = true;
      }
      setState(() => _loading = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppSheet(
      title: l.healthCheckInTitle,
      subtitle: context.formatters(ref).date(healthDay(widget.day)),
      footer: AppSheetFooter(
        submitLabel: l.commonSave,
        cancelLabel: l.commonCancel,
        onSubmit: _submit,
        busy: _saving,
        enabled: !_loading && _loadError == null,
      ),
      child: _loading
          ? const Center(child: FCircularProgress())
          : _loadError != null
          ? AppEmptyState.error(
              title: l.commonLoadFailed,
              message: l.healthCheckInLoadFailed,
              retryLabel: l.commonRetry,
              onRetry: _load,
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.healthCheckInHelp, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s16),
                _rating(
                  l.healthCheckInEnergy,
                  l.healthCheckInEnergyScale,
                  _energy,
                  (value) => _energy = value,
                ),
                const SizedBox(height: AppSpacing.s12),
                _rating(
                  l.healthCheckInSleepQuality,
                  l.healthCheckInSleepScale,
                  _sleepQuality,
                  (value) => _sleepQuality = value,
                ),
                const SizedBox(height: AppSpacing.s12),
                _rating(
                  l.healthCheckInStress,
                  l.healthCheckInStressScale,
                  _stress,
                  (value) => _stress = value,
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(l.healthCheckInEvents, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s8),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final tag in {
                      ...HealthEventTag.values.map((tag) => tag.wire),
                      ..._tags,
                    })
                      AppFilterChip(
                        label: healthEventTagLabel(l, tag),
                        active: _tags.contains(tag),
                        onPress: _saving
                            ? null
                            : () {
                                setState(() {
                                  if (!_tags.remove(tag)) _tags.add(tag);
                                  _validation = null;
                                });
                                widget.dirty.markDirty();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                if (!_showNote)
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: _saving
                        ? null
                        : () => setState(() => _showNote = true),
                    child: Text(l.healthMeasurementNoteOptional),
                  ),
                if (_showNote)
                  FTextFormField(
                    control: FTextFieldControl.managed(controller: _note),
                    enabled: !_saving,
                    label: Text(l.commonNote),
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 1000,
                  ),
                if (_validation != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppStatusBanner(
                    message: _validation!,
                    kind: AppStatusKind.error,
                  ),
                ],
                if (submissionFailureMessage case final message?) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppStatusBanner(message: message, kind: AppStatusKind.error),
                ],
                if (_entry != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: _saving ? null : _delete,
                    child: Text(l.healthCheckInDelete),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _rating(
    String label,
    String helper,
    int? value,
    ValueChanged<int?> update,
  ) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s4),
        Text(helper, style: context.microCaptionStyle),
        const SizedBox(height: AppSpacing.s8),
        SegmentedRow<int?>(
          options: const [1, 2, 3, 4, 5],
          value: value,
          minSegmentWidth: 44,
          labelOf: (n) => '$n',
          semanticLabelOf: (n) => l.healthCheckInValue(label, n!),
          onChanged: _saving
              ? null
              : (n) {
                  setState(() {
                    update(value == n ? null : n);
                    _validation = null;
                  });
                  widget.dirty.markDirty();
                },
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_saving || _loading || _loadError != null) return;
    final l = AppLocalizations.of(context);
    if (_energy == null &&
        _sleepQuality == null &&
        _stress == null &&
        _tags.isEmpty &&
        _note.text.trim().isEmpty) {
      setState(() => _validation = l.healthCheckInEmptyError);
      return;
    }
    final energy = _energy, sleep = _sleepQuality, stress = _stress;
    final tags = _tags.toList(), note = _note.text;
    await submitForm<HealthCheckIn>(
      dirty: widget.dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () async =>
          (await ref.read(healthCheckInRepositoryProvider.future)).save(
            day: widget.day,
            energy: energy,
            sleepQuality: sleep,
            stress: stress,
            tags: tags,
            note: note,
            expectedOwnerUserId: _owner,
          ),
      leave: () => Navigator.of(context).pop(true),
      failureMessage: (error) => userSafeErrorMessage(
        context,
        error,
        operation: 'save health check-in',
      ),
      successMessage: l.commonSaved,
      tag: 'health-check-in',
    );
  }

  Future<void> _delete() async {
    final entry = _entry;
    if (entry == null || _saving) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l.healthCheckInDelete),
      body: Text(l.healthCheckInDeleteConfirm),
      confirmLabel: l.commonDelete,
      cancelLabel: l.commonCancel,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () async =>
          (await ref.read(healthCheckInRepositoryProvider.future))
              .delete(entry),
      leave: () => Navigator.of(context).pop(true),
      failureMessage: (error) => userSafeErrorMessage(
        context,
        error,
        operation: 'delete health check-in',
      ),
      successMessage: l.commonDeleted,
      tag: 'health-check-in-delete',
    );
  }
}
