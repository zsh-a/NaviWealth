/// KnowledgeOS Routine creation sheet
/// (`docs/knowledgeos-domain.md` §3 + §9).
///
/// Form intentionally minimal — Routine carries less editorial weight
/// than Decision / Assumption, so 3 fields beat 6:
///
/// - statement (required) — "港卡做一次活跃交易"
/// - intervalDays — preset 30 / 90 / 180 / 365 buttons (covers 95% of
///   recurring reminders); custom path lands in slice B's Capture UX
/// - scope (optional free tag, defaults to "*")
///
/// `nextDueAt` defaults to `now + intervalDays`. Editing nextDueAt to
/// "the actual next anniversary" is a slice-B follow-up; current value
/// covers the typical "I'm setting this up today, remind me in N days"
/// case the user actually has.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

Future<void> showNewRoutineSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _RoutineWriter(),
    );

class _RoutineWriter extends ConsumerStatefulWidget {
  const _RoutineWriter();
  @override
  ConsumerState<_RoutineWriter> createState() => _RoutineWriterState();
}

/// Preset cadences. 180 days = ~6 months covers the prototypical "港卡
/// 需要定期活跃" case; 30 / 90 / 365 round out monthly / quarterly /
/// annual.
const List<int> _kIntervalPresets = [30, 90, 180, 365];

String _intervalPresetLabel(AppLocalizations l10n, int days) => switch (days) {
  30 => l10n.knowledgeRoutineMonthly,
  90 => l10n.knowledgeRoutineQuarterly,
  180 => l10n.knowledgeRoutineSemiannual,
  365 => l10n.knowledgeRoutineYearly,
  _ => '$days d',
};

class _RoutineWriterState extends ConsumerState<_RoutineWriter> {
  final _statementCtrl = TextEditingController();
  final _scopeCtrl = TextEditingController(text: '*');
  int _intervalDays = 180;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _statementCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statementCtrl.dispose();
    _scopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _statementCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final nextDue = stamp.now.add(Duration(days: _intervalDays));
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: kKnowledgeUuid.v4(),
          statement: _statementCtrl.text.trim(),
          intervalDays: _intervalDays,
          nextDueAt: nextDue,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
          status: RoutineStatus.active,
          createdAt: stamp.now,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeRoutineWriterTitle,
      subtitle: l10n.knowledgeRoutineWriterSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _statementCtrl.text.trim().isEmpty,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _statementCtrl),
                label: Text(l10n.knowledgeRoutineStatementLabel),
                hint: l10n.knowledgeRoutineStatementHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCadenceSectionTitle,
            children: [
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final preset in _kIntervalPresets)
                    FButton(
                      variant: _intervalDays == preset
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      onPress: () => setState(() => _intervalDays = preset),
                      child: Text(_intervalPresetLabel(l10n, preset)),
                    ),
                ],
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _scopeCtrl),
                label: Text(l10n.knowledgeWriterScopeOptionalLabel),
                hint: '"*" / "finance/cards/hk" / "investing"',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
