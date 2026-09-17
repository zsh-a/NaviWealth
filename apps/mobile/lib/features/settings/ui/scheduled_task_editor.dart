import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/agents/scheduled_agent_store.dart';
import '../../../core/ai/agents/scheduled_agent_task.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

Future<bool?> showScheduledTaskEditor(
  BuildContext context, {
  ScheduledAgentTask? initial,
}) async {
  final owner = await ProviderScope.containerOf(context)
      .read(currentUserIdProvider)();
  if (!context.mounted) return null;
  final dirty = FormDirtyController();
  try {
    return await showAppFormSheet<bool>(
      context: context,
      dirtyGuard: dirty,
      builder: (_) => _Editor(initial: initial, dirty: dirty, owner: owner),
    );
  } finally {
    dirty.dispose();
  }
}

String scheduledWeekdayLabel(String locale, int weekday) =>
    DateFormat.EEEE(locale).format(DateTime(2026, 9, 14 + weekday - 1));

class _Editor extends ConsumerStatefulWidget {
  const _Editor({this.initial, required this.dirty, required this.owner});
  final String owner;
  final ScheduledAgentTask? initial;
  final FormDirtyController dirty;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final title = TextEditingController(text: widget.initial?.title);
  late final instructions = TextEditingController(
    text: widget.initial?.instructions,
  );
  late DomainScope domain = widget.initial?.domain ?? DomainScope.finance;
  late int weekday = widget.initial?.schedule.weekdayLocal ?? 7;
  late int hour = widget.initial?.schedule.preferredHourLocal ?? 20;
  late int minute = widget.initial?.schedule.minuteLocal ?? 0;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([title, instructions]);
  }

  @override
  void dispose() {
    title.dispose();
    instructions.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    widget.dirty.busy = true;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (!(await ref.read(auth.domainOptInsProvider.future))
          .contains(domain)) {
        throw StateError('inactive domain');
      }
      final store = await ref.read(scheduledAgentStoreProvider.future);
      if (store.ownerUserId != widget.owner) {
        throw StateError('task owner changed');
      }
      final expected = widget.initial?.revision ?? 0;
      final task = ScheduledAgentTask.fromJson({
        'id': widget.initial?.id ?? 'user_task:${const Uuid().v4()}',
        'title': title.text,
        'instructions': instructions.text,
        'domain': domain.wire,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'created_at': (widget.initial?.createdAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'revision': expected + 1,
      });
      await store.save(task, expectedRevision: expected);
      ref.invalidate(scheduledAgentTasksProvider);
      widget.dirty.markPristine();
      widget.dirty.busy = false;
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(
          () => error = AppLocalizations.of(context).scheduledTaskSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> archive() async {
    final initial = widget.initial;
    if (initial == null || !initial.id.startsWith('user_task:') || saving) {
      return;
    }
    final l = AppLocalizations.of(context);
    if (await showConfirmDialog(
              context: context,
              title: Text(l.scheduledTaskDelete),
              body: Text(l.scheduledTaskDeleteBody),
              confirmLabel: l.commonDelete,
              cancelLabel: l.commonCancel,
              destructive: true,
            ) !=
            true ||
        !mounted) {
      return;
    }
    setState(() => saving = true);
    widget.dirty.busy = true;
    try {
      final store = await ref.read(scheduledAgentStoreProvider.future);
      if (store.ownerUserId != widget.owner) {
        throw StateError('task owner changed');
      }
      await store.save(
        ScheduledAgentTask.fromJson({
          ...initial.toJson(),
          'archived': true,
          'revision': initial.revision + 1,
        }),
        expectedRevision: initial.revision,
      );
      ref.invalidate(scheduledAgentTasksProvider);
      widget.dirty.markPristine();
      widget.dirty.busy = false;
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) setState(() => error = l.scheduledTaskSaveFailed);
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final domains = ref.watch(auth.domainOptInsProvider).value;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null
                  ? l.scheduledTaskCreate
                  : l.scheduledTaskEdit,
              style: context.labelStyle,
            ),
            const SizedBox(height: AppSpacing.s16),
            FTextField(
              label: Text(l.scheduledTaskName),
              control: FTextFieldControl.managed(controller: title),
              enabled: !saving,
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              label: Text(l.scheduledTaskGoal),
              control: FTextFieldControl.managed(controller: instructions),
              maxLines: 5,
              enabled: !saving,
            ),
            const SizedBox(height: AppSpacing.s12),
            FSelect<DomainScope>(
              label: Text(l.scheduledTaskScope),
              enabled: !saving && widget.initial == null,
              items: {
                for (final scope in DomainScope.values)
                  if (scope == domain || domains?.contains(scope) == true)
                    switch (scope) {
                      DomainScope.finance => 'FinanceOS',
                      DomainScope.health => 'HealthOS',
                      DomainScope.knowledge => 'KnowledgeOS',
                      DomainScope.execution => 'ExecutionOS',
                    }: scope,
              },
              control: FSelectControl.managed(
                initial: domain,
                onChange: (value) {
                  if (value != null) {
                    setState(() => domain = value);
                    widget.dirty.markDirty();
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            FSelect<int>(
              label: Text(l.scheduledTaskWeekday),
              enabled: !saving,
              items: {
                for (var day = 1; day <= 7; day++)
                  scheduledWeekdayLabel(l.localeName, day): day,
              },
              control: FSelectControl.managed(
                initial: weekday,
                onChange: (value) {
                  if (value != null) {
                    setState(() => weekday = value);
                    widget.dirty.markDirty();
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: FSelect<int>(
                    label: Text(l.scheduledTaskHour),
                    enabled: !saving,
                    items: {
                      for (var i = 0; i < 24; i++)
                        i.toString().padLeft(2, '0'): i,
                    },
                    control: FSelectControl.managed(
                      initial: hour,
                      onChange: (value) {
                        if (value != null) {
                          setState(() => hour = value);
                          widget.dirty.markDirty();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: FSelect<int>(
                    label: Text(l.scheduledTaskMinute),
                    enabled: !saving,
                    items: {
                      for (var i = 0; i < 60; i++)
                        i.toString().padLeft(2, '0'): i,
                    },
                    control: FSelectControl.managed(
                      initial: minute,
                      onChange: (value) {
                        if (value != null) {
                          setState(() => minute = value);
                          widget.dirty.markDirty();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(l.scheduledTaskDisclosure, style: context.captionStyle),
            if (error != null)
              AppStatusBanner(message: error!, kind: AppStatusKind.error),
            const SizedBox(height: AppSpacing.s16),
            AppBusyButton(
              label: l.commonSave,
              busy: saving,
              onPress: saving ? null : save,
            ),
            if (widget.initial?.id.startsWith('user_task:') == true)
              AppQuietButton(
                label: l.scheduledTaskDelete,
                onPress: saving ? null : archive,
              ),
          ],
        ),
      ),
    );
  }
}
