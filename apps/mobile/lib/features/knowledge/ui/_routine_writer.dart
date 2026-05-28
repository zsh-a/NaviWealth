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
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

Future<void> showNewRoutineSheet(BuildContext context, WidgetRef ref) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => _RoutineWriter(ref: ref),
    );

class _RoutineWriter extends StatefulWidget {
  const _RoutineWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_RoutineWriter> createState() => _RoutineWriterState();
}

/// Preset cadences. 180 days = ~6 months covers the prototypical "港卡
/// 需要定期活跃" case; 30 / 90 / 365 round out monthly / quarterly /
/// annual.
const List<({int days, String label})> _kIntervalPresets = [
  (days: 30, label: '每月'),
  (days: 90, label: '每季'),
  (days: 180, label: '每 6 个月'),
  (days: 365, label: '每年'),
];

class _RoutineWriterState extends State<_RoutineWriter> {
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
      final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper = await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final nextDue = stamp.now.add(Duration(days: _intervalDays));
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: kKnowledgeUuid.v4(),
          statement: _statementCtrl.text.trim(),
          intervalDays: _intervalDays,
          nextDueAt: nextDue,
          scope: _scopeCtrl.text.trim().isEmpty
              ? '*'
              : _scopeCtrl.text.trim(),
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
    final typography = context.theme.typography;
    return AppSheet(
      title: '新建 Routine',
      subtitle: '定期提醒 — AI 会在临近 next_due_at 时主动提示',
      footer: AppSheetFooter(
        submitLabel: _saving ? '保存中…' : '保存',
        busy: _saving || _statementCtrl.text.trim().isEmpty,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _statementCtrl),
            label: const Text('要做什么'),
            hint: '"港卡做一次活跃交易" / "每月对账"',
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            '频率',
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final preset in _kIntervalPresets)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                  child: FButton(
                    variant: _intervalDays == preset.days
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    onPress: () =>
                        setState(() => _intervalDays = preset.days),
                    child: Text(preset.label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _scopeCtrl),
            label: const Text('范围标签（可选）'),
            hint: '"*" / "finance/cards/hk" / "investing"',
          ),
        ],
      ),
    );
  }
}
