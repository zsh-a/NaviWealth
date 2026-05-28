/// KnowledgeOS Library writers — Principle / Assumption / Concept /
/// Experiment (`docs/knowledgeos-domain.md` §3 + §9).
///
/// Decision has its own sheet in `_decision_writer.dart` because it
/// owns options / picker UI. The four types here share a single
/// pattern: 1–2 short fields + an optional markdown body. Bundled in
/// one file to keep the surface honest about how small each form is.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

Future<void> showNewPrincipleSheet(BuildContext context, WidgetRef ref) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => _PrincipleWriter(ref: ref),
    );

Future<void> showNewAssumptionSheet(BuildContext context, WidgetRef ref) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => _AssumptionWriter(ref: ref),
    );

Future<void> showNewConceptSheet(BuildContext context, WidgetRef ref) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => _ConceptWriter(ref: ref),
    );

Future<void> showNewExperimentSheet(BuildContext context, WidgetRef ref) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => _ExperimentWriter(ref: ref),
    );

// ── Principle ────────────────────────────────────────────────────────────

class _PrincipleWriter extends StatefulWidget {
  const _PrincipleWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_PrincipleWriter> createState() => _PrincipleWriterState();
}

class _PrincipleWriterState extends State<_PrincipleWriter> {
  final _stmtCtrl = TextEditingController();
  final _rationaleCtrl = TextEditingController();
  final _scopeCtrl = TextEditingController(text: '*');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stmtCtrl.dispose();
    _rationaleCtrl.dispose();
    _scopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _stmtCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      await repo.upsertPrinciple(
        KnowledgePrinciple(
          id: kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          rationaleMd: _rationaleCtrl.text,
          scope: _scopeCtrl.text.trim().isEmpty
              ? '*'
              : _scopeCtrl.text.trim(),
          status: PrincipleStatus.active,
          declaredAt: stamp.now,
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
  Widget build(BuildContext context) => AppSheet(
    title: 'New principle',
    subtitle: 'Long-term worldview primitive — not falsifiable',
    footer: AppSheetFooter(
      submitLabel: _saving ? 'Saving…' : 'Save',
      busy: _saving || _stmtCtrl.text.trim().isEmpty,
      onSubmit: () {
        _save();
      },
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _stmtCtrl),
          label: const Text('Statement'),
          hint: '"默认 edge-first" / "避免高维护成本系统"',
            ),
        const SizedBox(height: AppSpacing.s12),
        MarkdownEditorWithPreview(
          controller: _rationaleCtrl,
          label: 'Rationale (Markdown)',
          hint: '为什么把这个 worldview 定为 principle',
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _scopeCtrl),
          label: const Text('Scope'),
          hint: '"*" / "investing" / "life"',
        ),
      ],
    ),
  );
}

// ── Assumption ───────────────────────────────────────────────────────────

class _AssumptionWriter extends StatefulWidget {
  const _AssumptionWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_AssumptionWriter> createState() => _AssumptionWriterState();
}

class _AssumptionWriterState extends State<_AssumptionWriter> {
  final _stmtCtrl = TextEditingController();
  final _scopeCtrl = TextEditingController(text: '*');
  double _confidence = 0.7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stmtCtrl.dispose();
    _scopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _stmtCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          confidence: _confidence,
          scope: _scopeCtrl.text.trim().isEmpty
              ? '*'
              : _scopeCtrl.text.trim(),
          evidenceIds: const <String>[],
          status: AssumptionStatus.active,
          declaredAt: stamp.now,
          lastVerifiedAt: stamp.now,
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
      title: 'New assumption',
      subtitle: 'Falsifiable — confidence preset, will be reviewed',
      footer: AppSheetFooter(
        submitLabel: _saving ? 'Saving…' : 'Save',
        busy: _saving || _stmtCtrl.text.trim().isEmpty,
        onSubmit: () {
          _save();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _stmtCtrl),
            label: const Text('Statement'),
            hint: '"长期指数增长高于通胀"',
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Confidence: ${_confidence.toStringAsFixed(2)}',
            style: typography.sm,
          ),
          const SizedBox(height: AppSpacing.s4),
          // Five preset confidence levels. Forui's slider needs its
          // own controller dance; preset buttons are cheaper and good
          // enough for a 0..1 dial that authors rarely tune past
          // tenths.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final v in const <double>[0.3, 0.5, 0.7, 0.85, 0.95])
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                  child: FButton(
                    variant: _confidence == v
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    onPress: () => setState(() => _confidence = v),
                    child: Text(v.toStringAsFixed(2)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _scopeCtrl),
            label: const Text('Scope'),
            hint: '"*" / "investing" / "fire"',
          ),
        ],
      ),
    );
  }
}

// ── Concept ──────────────────────────────────────────────────────────────

class _ConceptWriter extends StatefulWidget {
  const _ConceptWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_ConceptWriter> createState() => _ConceptWriterState();
}

class _ConceptWriterState extends State<_ConceptWriter> {
  final _nameCtrl = TextEditingController();
  final _aliasesCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aliasesCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final aliases = _aliasesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      await repo.upsertConcept(
        KnowledgeConcept(
          id: kKnowledgeUuid.v4(),
          name: _nameCtrl.text.trim(),
          aliases: aliases,
          summaryMd: _summaryCtrl.text,
          relatedConceptIds: const <String>[],
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
  Widget build(BuildContext context) => AppSheet(
    title: 'New concept',
    subtitle: 'Anchor for [[soft links]] and AI-proposed cross-refs',
    footer: AppSheetFooter(
      submitLabel: _saving ? 'Saving…' : 'Save',
      busy: _saving || _nameCtrl.text.trim().isEmpty,
      onSubmit: () {
        _save();
      },
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _nameCtrl),
          label: const Text('Name'),
          hint: 'Concept name (e.g. "edge-first")',
            ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _aliasesCtrl),
          label: const Text('Aliases'),
          hint: 'Comma-separated synonyms',
        ),
        const SizedBox(height: AppSpacing.s12),
        MarkdownEditorWithPreview(
          controller: _summaryCtrl,
          label: 'Summary (Markdown)',
          hint: '1–2 sentence definition for the [[soft link]] tooltip',
          minLines: 2,
          maxLines: 4,
        ),
      ],
    ),
  );
}

// ── Experiment ───────────────────────────────────────────────────────────

class _ExperimentWriter extends StatefulWidget {
  const _ExperimentWriter({required this.ref});
  final WidgetRef ref;
  @override
  State<_ExperimentWriter> createState() => _ExperimentWriterState();
}

class _ExperimentWriterState extends State<_ExperimentWriter> {
  final _hypoCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();
  final _metricsCtrl = TextEditingController();
  String? _targetAssumptionId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hypoCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _hypoCtrl.dispose();
    _methodCtrl.dispose();
    _metricsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _hypoCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo =
          await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper =
          await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final metrics = _metricsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      await repo.upsertExperiment(
        KnowledgeExperiment(
          id: kKnowledgeUuid.v4(),
          hypothesis: _hypoCtrl.text.trim(),
          methodMd: _methodCtrl.text,
          metrics: metrics,
          status: ExperimentStatus.planned,
          targetAssumptionId: _targetAssumptionId,
          startedAt: stamp.now,
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
  Widget build(BuildContext context) => AppSheet(
    title: 'New experiment',
    subtitle: 'Test a hypothesis — typically targets an assumption',
    footer: AppSheetFooter(
      submitLabel: _saving ? 'Saving…' : 'Save',
      busy: _saving || _hypoCtrl.text.trim().isEmpty,
      onSubmit: () {
        _save();
      },
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _hypoCtrl),
          label: const Text('Hypothesis'),
          hint: '"covered call 60 DTE on QQQ 优于 30 DTE"',
            ),
        const SizedBox(height: AppSpacing.s12),
        MarkdownEditorWithPreview(
          controller: _methodCtrl,
          label: 'Method (Markdown)',
          hint: '怎么做、跑多久、用什么数据',
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _metricsCtrl),
          label: const Text('Metrics'),
          hint: 'Comma-separated (e.g. "yield, drawdown, sharpe")',
        ),
        const SizedBox(height: AppSpacing.s12),
        _AssumptionTargetPicker(
          ref: widget.ref,
          selectedId: _targetAssumptionId,
          onChange: (id) => setState(() => _targetAssumptionId = id),
        ),
      ],
    ),
  );
}

class _AssumptionTargetPicker extends ConsumerWidget {
  const _AssumptionTargetPicker({
    required this.ref,
    required this.selectedId,
    required this.onChange,
  });
  final WidgetRef ref;
  final String? selectedId;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (repo) => StreamBuilder<List<KnowledgeAssumption>>(
            stream: repo.watchAssumptions(ownerUserId: owner),
            builder: (context, snap) {
              final all = (snap.data ?? const <KnowledgeAssumption>[])
                  .where((a) => a.status == AssumptionStatus.active)
                  .toList(growable: false);
              if (all.isEmpty) {
                return Text(
                  '没有 active assumption 可挂(留空也可以)',
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                );
              }
              final typography = context.theme.typography;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Target assumption (optional)',
                    style: typography.sm
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  for (final a in all)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          onChange(selectedId == a.id ? null : a.id),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              selectedId == a.id
                                  ? FLucideIcons.checkSquare2
                                  : FLucideIcons.square,
                              size: 14,
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            Expanded(
                              child: Text(
                                a.statement,
                                style: typography.sm,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
