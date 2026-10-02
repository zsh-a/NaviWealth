import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_delete_confirm.dart';
import 'execution_relation_picker.dart';
import 'execution_sheet_footer.dart';
import 'execution_widgets.dart';

Future<bool?> showExecutionActionSheet({
  required BuildContext context,
  ExecutionAction? action,
  String? initialPlanId,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionActionForm(
      action: action,
      initialPlanId: initialPlanId,
      dirty: dirty,
    ),
  ).whenComplete(dirty.dispose);
}

class _ExecutionActionForm extends ConsumerStatefulWidget {
  const _ExecutionActionForm({
    required this.action,
    required this.initialPlanId,
    required this.dirty,
  });

  final ExecutionAction? action;
  final String? initialPlanId;
  final FormDirtyController dirty;

  @override
  ConsumerState<_ExecutionActionForm> createState() =>
      _ExecutionActionFormState();
}

class _ExecutionActionFormState extends ConsumerState<_ExecutionActionForm>
    with FormSubmission<_ExecutionActionForm>, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _scheduleErrorKey = GlobalKey();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late ExecutionPriority _priority;
  DateTime? _dueAt;
  DateTime? _scheduledFor;
  String? _planId;
  late bool _showDetails;
  bool _saving = false;
  LocalFormDraftSession? _draftSession;

  @override
  void initState() {
    super.initState();
    final action = widget.action;
    _title.text = action?.title ?? '';
    _note.text = action?.note ?? '';
    _priority = action?.priority ?? ExecutionPriority.normal;
    _dueAt = action?.dueAt;
    _scheduledFor = action?.scheduledFor;
    _planId = action == null ? widget.initialPlanId : action.planId;
    _showDetails = action != null || _planId != null;
    widget.dirty.bindTextControllers([_title, _note]);
    _title.addListener(_onTitleChanged);
    WidgetsBinding.instance.addObserver(this);
    if (action == null) {
      final store = ref.read(localFormDraftStoreProvider);
      if (store != null) {
        _draftSession = LocalFormDraftSession(
          store,
          'execution.action.new:${widget.initialPlanId ?? ''}',
        );
      }
      _note.addListener(_captureDraft);
      widget.dirty.addListener(_captureDraft);
      widget.dirty.onDiscard = () => _draftSession?.complete();
    }
  }

  void _onTitleChanged() {
    _captureDraft();
    if (mounted && !_saving) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftSession?.dispose();
    widget.dirty.removeListener(_captureDraft);
    widget.dirty.onDiscard = null;
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _draftSession?.pending == null &&
      _title.text.trim().isNotEmpty;

  void _captureDraft() {
    if (!widget.dirty.isDirty || _saving) return;
    _draftSession?.capture({
      'title': _title.text,
      'note': _note.text,
      'priority': _priority.name,
      'due': _dueAt?.toIso8601String(),
      'scheduled': _scheduledFor?.toIso8601String(),
      'plan': _planId,
      'details': _showDetails,
    });
  }

  void _restoreDraft() {
    final session = _draftSession;
    final payload = session?.pending;
    if (session == null || payload == null) return;
    session.accept();
    setState(() {
      _title.text = payload['title'] is String
          ? payload['title']! as String
          : '';
      _note.text = payload['note'] is String ? payload['note']! as String : '';
      _priority =
          ExecutionPriority.values
              .where((value) => value.name == payload['priority'])
              .firstOrNull ??
          ExecutionPriority.normal;
      _dueAt = DateTime.tryParse(
        payload['due'] is String ? payload['due']! as String : '',
      );
      _scheduledFor = DateTime.tryParse(
        payload['scheduled'] is String ? payload['scheduled']! as String : '',
      );
      _planId = payload['plan'] is String ? payload['plan']! as String : null;
      _showDetails = payload['details'] == true;
    });
    widget.dirty.markDirty();
    _captureDraft();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _draftSession?.flush();
  }

  bool get _invalidSchedule =>
      _scheduledFor != null &&
      _dueAt != null &&
      _scheduledFor!.isAfter(_dueAt!);

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    if (_invalidSchedule) {
      setState(() => _showDetails = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final errorContext = _scheduleErrorKey.currentContext;
      if (errorContext != null && errorContext.mounted) {
        await Scrollable.ensureVisible(errorContext);
      }
      return;
    }
    final title = _title.text.trim();
    final note = _note.text.trim();
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-action',
      onCommitted: (_) => _draftSession?.complete(),
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.upsertAction(_buildAction(sync, title, note));
      },
    );
  }

  Future<void> _delete() async {
    final action = widget.action;
    if (_saving || action == null) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: action.title,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-action-delete',
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.softDeleteAction(action: action, sync: sync);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  ExecutionAction _buildAction(SyncMeta sync, String title, String note) {
    final existing = widget.action;
    return ExecutionAction(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      note: note,
      status: existing?.status ?? ExecutionActionStatus.todo,
      priority: _priority,
      dueAt: _dueAt,
      scheduledFor: _scheduledFor,
      planId: _planId,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: existing?.completedAt,
      sync: sync,
    );
  }

  void _markDirty() => widget.dirty.markDirty();

  @override
  Widget build(BuildContext context) {
    _captureDraft();
    final l10n = AppLocalizations.of(context);
    final plans =
        ref.watch(executionPlansProvider).value ?? const <ExecutionPlan>[];
    final isEditing = widget.action != null;

    return AppSheet(
      title: isEditing
          ? l10n.executionEditActionTitle
          : l10n.executionCreateActionTitle,
      footer: ExecutionSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        enabled: _canSave,
        busy: _saving,
        onSubmit: _save,
      ),
      child: _draftSession?.pending != null
          ? AppDraftRestoreBanner(
              onRestore: _restoreDraft,
              onDiscard: () => setState(() => _draftSession!.discardPending()),
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (submissionFailureMessage != null) ...[
                    AppStatusBanner(
                      kind: AppStatusKind.error,
                      message: submissionFailureMessage!,
                      compact: true,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                  ],
                  FTextFormField(
                    control: FTextFieldControl.managed(controller: _title),
                    enabled: !_saving,
                    label: Text(l10n.executionActionField),
                    hint: l10n.executionActionTitleHint,
                    maxLines: 1,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? l10n.executionTitleRequired
                        : null,
                  ),
                  if (!isEditing) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      l10n.executionQuickWhenField,
                      style: context.captionLabelStyle,
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    SegmentedRow<_ExecutionQuickWhen>(
                      options: _ExecutionQuickWhen.values,
                      value: _quickWhen,
                      labelOf: (value) => switch (value) {
                        _ExecutionQuickWhen.inbox =>
                          l10n.executionQuickWhenInbox,
                        _ExecutionQuickWhen.today =>
                          l10n.executionQuickWhenToday,
                        _ExecutionQuickWhen.tomorrow =>
                          l10n.executionQuickWhenTomorrow,
                      },
                      iconOf: (value) => switch (value) {
                        _ExecutionQuickWhen.inbox => FLucideIcons.inbox,
                        _ExecutionQuickWhen.today => FLucideIcons.sun,
                        _ExecutionQuickWhen.tomorrow => FLucideIcons.sunrise,
                      },
                      onChanged: _saving ? null : _setQuickWhen,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    SizedBox(
                      width: double.infinity,
                      child: AppQuietButton(
                        label: _showDetails
                            ? l10n.executionHideDetails
                            : l10n.executionShowDetails,
                        prefix: Icon(
                          _showDetails
                              ? FLucideIcons.chevronUp
                              : FLucideIcons.slidersHorizontal,
                        ),
                        onPress: _saving
                            ? null
                            : () =>
                                  setState(() => _showDetails = !_showDetails),
                      ),
                    ),
                  ],
                  if (_showDetails) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      l10n.executionPriorityField,
                      style: context.captionLabelStyle,
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    SegmentedRow<ExecutionPriority>(
                      options: ExecutionPriority.values,
                      value: _priority,
                      labelOf: (priority) =>
                          executionPriorityLabel(l10n, priority),
                      iconOf: _priorityIcon,
                      onChanged: _saving
                          ? null
                          : (priority) {
                              setState(() => _priority = priority);
                              _markDirty();
                            },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scheduled = DateField(
                          label: l10n.executionScheduledForField,
                          initialValue: _scheduledFor,
                          enabled: !_saving,
                          onChanged: (value) {
                            setState(() => _scheduledFor = value);
                            _markDirty();
                          },
                        );
                        final due = DateField(
                          label: l10n.executionDueAtField,
                          initialValue: _dueAt,
                          enabled: !_saving,
                          onChanged: (value) {
                            setState(() => _dueAt = value);
                            _markDirty();
                          },
                        );
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        if (constraints.maxWidth < 420 || largeText) {
                          return Column(
                            children: [
                              scheduled,
                              const SizedBox(height: AppSpacing.s12),
                              due,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: scheduled),
                            const SizedBox(width: AppSpacing.s12),
                            Expanded(child: due),
                          ],
                        );
                      },
                    ),
                    if (_invalidSchedule) ...[
                      const SizedBox(height: AppSpacing.s6),
                      Semantics(
                        key: _scheduleErrorKey,
                        liveRegion: true,
                        child: Text(
                          l10n.executionScheduleAfterDue,
                          style: context.captionStyle.copyWith(
                            color: context.appTheme.status.danger.fg,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s12),
                    FormPickerRow(
                      label: l10n.executionRelationField,
                      value: executionPlanPickerLabel(l10n, plans, _planId),
                      leading: const Icon(FLucideIcons.layers),
                      enabled: !_saving,
                      onPress: () async {
                        final picked = await showExecutionPlanPicker(
                          context: context,
                          plans: plans,
                          selectedId: _planId,
                        );
                        if (picked == null) return;
                        setState(
                          () => _planId = picked == kExecutionPickerNone
                              ? null
                              : picked,
                        );
                        _markDirty();
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: _note),
                      enabled: !_saving,
                      label: Text(l10n.commonNote),
                      hint: l10n.executionActionNoteHint,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                    ),
                  ],
                  if (isEditing) ...[
                    const SizedBox(height: AppSpacing.s16),
                    const AppDivider(),
                    const SizedBox(height: AppSpacing.s12),
                    FButton(
                      variant: FButtonVariant.destructive,
                      onPress: _saving ? null : _delete,
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  _ExecutionQuickWhen get _quickWhen {
    final scheduled = _scheduledFor?.toLocal();
    if (scheduled == null) return _ExecutionQuickWhen.inbox;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(scheduled.year, scheduled.month, scheduled.day);
    if (day == today) return _ExecutionQuickWhen.today;
    if (day == today.add(const Duration(days: 1))) {
      return _ExecutionQuickWhen.tomorrow;
    }
    return _ExecutionQuickWhen.inbox;
  }

  void _setQuickWhen(_ExecutionQuickWhen value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _scheduledFor = switch (value) {
        _ExecutionQuickWhen.inbox => null,
        _ExecutionQuickWhen.today => today,
        _ExecutionQuickWhen.tomorrow => today.add(const Duration(days: 1)),
      };
    });
    _markDirty();
  }
}

enum _ExecutionQuickWhen { inbox, today, tomorrow }

IconData _priorityIcon(ExecutionPriority priority) {
  return switch (priority) {
    ExecutionPriority.low => FLucideIcons.arrowDown,
    ExecutionPriority.normal => FLucideIcons.minus,
    ExecutionPriority.high => FLucideIcons.flag,
  };
}

class ExecutionActionStatusUndo {
  const ExecutionActionStatusUndo({
    required this.repository,
    required this.before,
    required this.appliedSync,
    required this.stamp,
    required this.progressId,
  });

  final ExecutionRepository repository;
  final ExecutionAction before;
  final SyncMeta appliedSync;
  final Future<SyncMeta> Function() stamp;
  final String? progressId;

  Future<void> restore() async {
    final current = await repository.findAction(
      ownerUserId: before.sync.ownerUserId,
      id: before.id,
    );
    if (current == null || current.sync.hlc != appliedSync.hlc) {
      throw StateError('Action changed after the status update.');
    }
    final sync = await stamp();
    await repository.upsertAction(before.copyWith(sync: sync));
    final id = progressId;
    if (id == null) return;
    final progress = await repository.findProgress(
      ownerUserId: before.sync.ownerUserId,
      id: id,
    );
    if (progress != null) {
      await repository.softDeleteProgress(progress: progress, sync: sync);
    }
  }
}

Future<ExecutionActionStatusUndo> updateExecutionActionStatus({
  required WidgetRef ref,
  required ExecutionAction action,
  required ExecutionActionStatus status,
  String? progressNote,
}) async {
  final repo = await ref.read(executionRepositoryProvider.future);
  final sync = await stampExecutionSync(ref);
  final stamper = await ref.read(mutationStamperProvider.future);
  final progressId = progressNote == null ? null : kExecutionUuid.v4();
  await repo.updateActionStatus(
    action: action,
    status: status,
    sync: sync,
    progressId: progressId,
    progressNote: progressNote,
  );
  return ExecutionActionStatusUndo(
    repository: repo,
    before: action,
    appliedSync: sync,
    stamp: () async {
      final next = await stamper.stamp();
      return SyncMeta(
        ownerUserId: next.ownerUserId,
        updatedAt: next.now,
        updatedByDevice: next.deviceId,
        hlc: next.hlc,
      );
    },
    progressId: progressId,
  );
}
