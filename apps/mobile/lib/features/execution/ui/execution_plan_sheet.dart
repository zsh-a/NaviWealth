import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/execution_repository.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_delete_confirm.dart';
import 'execution_sheet_footer.dart';

Future<bool?> showExecutionPlanSheet({
  required BuildContext context,
  ExecutionPlan? plan,
}) {
  final dirty = FormDirtyController();
  return showAppFormSheet<bool>(
    context: context,
    dirtyGuard: dirty,
    builder: (_) => _ExecutionPlanForm(plan: plan, dirty: dirty),
  ).whenComplete(dirty.dispose);
}

class _ExecutionPlanForm extends ConsumerStatefulWidget {
  const _ExecutionPlanForm({required this.plan, required this.dirty});

  final ExecutionPlan? plan;
  final FormDirtyController dirty;

  @override
  ConsumerState<_ExecutionPlanForm> createState() => _ExecutionPlanFormState();
}

class _ExecutionPlanFormState extends ConsumerState<_ExecutionPlanForm>
    with FormSubmission<_ExecutionPlanForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late ExecutionHorizon _horizon;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _title.text = plan?.title ?? '';
    _description.text = plan?.description ?? '';
    _horizon = plan?.horizon ?? ExecutionHorizon.open;
    _targetDate = plan?.targetDate;
    widget.dirty.bindTextControllers([_title, _description]);
    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (mounted && !_saving) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-plan',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(executionRepositoryProvider.future);
        final sync = await stampExecutionSync(ref);
        await repo.upsertPlan(_buildPlan(sync, title));
      },
    );
  }

  Future<void> _delete() async {
    final plan = widget.plan;
    if (_saving || plan == null) return;
    final l10n = AppLocalizations.of(context);
    final ExecutionRepository repo;
    final int openActionCount;
    try {
      repo = await ref.read(executionRepositoryProvider.future);
      final relatedActions = await repo
          .watchActionsForPlan(
            ownerUserId: plan.sync.ownerUserId,
            planId: plan.id,
          )
          .first;
      openActionCount = relatedActions.where((action) => action.isOpen).length;
    } on Object catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await confirmExecutionDelete(
      context: context,
      item: plan.title,
      body: openActionCount == 0
          ? null
          : l10n.executionDeleteWithOpenActionsBody(openActionCount),
    );
    if (!confirmed || !mounted) return;
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: _setSaving,
      leave: () => Navigator.of(context).pop(true),
      tag: 'execution-plan-delete',
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      commit: () async {
        final sync = await stampExecutionSync(ref);
        await repo.softDeletePlan(plan: plan, sync: sync);
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  ExecutionPlan _buildPlan(SyncMeta sync, String title) {
    final existing = widget.plan;
    return ExecutionPlan(
      id: existing?.id ?? kExecutionUuid.v4(),
      title: title,
      description: _description.text.trim(),
      status: existing?.status ?? ExecutionPlanStatus.active,
      horizon: _horizon,
      targetDate: _targetDate,
      source: existing?.source ?? const ExecutionSourceRef(),
      createdAt: existing?.createdAt ?? sync.updatedAt,
      completedAt: existing?.completedAt,
      sync: sync,
    );
  }

  void _markDirty() => widget.dirty.markDirty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.plan != null;
    return AppSheet(
      title: isEditing
          ? l10n.executionEditPlanTitle
          : l10n.executionCreatePlanTitle,
      footer: ExecutionSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        enabled: _canSave,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Form(
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
              label: Text(l10n.executionPlanField),
              hint: l10n.executionPlanTitleHint,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.executionTitleRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              label: l10n.executionTargetDateField,
              initialValue: _targetDate,
              enabled: !_saving,
              onChanged: (value) {
                setState(() => _targetDate = value);
                _markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _description),
              label: Text(l10n.executionDescriptionField),
              hint: l10n.executionPlanDescriptionHint,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
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
}
