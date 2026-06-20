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
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

Future<void> showNewPrincipleSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _PrincipleWriter(),
    );

Future<void> showEditPrincipleSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgePrinciple principle,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _PrincipleWriter(initial: principle),
);

Future<void> showNewAssumptionSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _AssumptionWriter(),
    );

Future<void> showEditAssumptionSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeAssumption assumption,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _AssumptionWriter(initial: assumption),
);

Future<void> showNewConceptSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ConceptWriter(),
    );

Future<void> showEditConceptSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeConcept concept,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _ConceptWriter(initial: concept),
);

Future<void> showNewExperimentSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ExperimentWriter(),
    );

Future<void> showEditExperimentSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeExperiment experiment,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _ExperimentWriter(initial: experiment),
);

Future<void> showEditNoteSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeNote note,
) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _NoteWriter(initial: note),
);

// ── Principle ────────────────────────────────────────────────────────────

class _PrincipleWriter extends ConsumerStatefulWidget {
  const _PrincipleWriter({this.initial});
  final KnowledgePrinciple? initial;
  @override
  ConsumerState<_PrincipleWriter> createState() => _PrincipleWriterState();
}

class _PrincipleWriterState extends ConsumerState<_PrincipleWriter> {
  late final _stmtCtrl = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _rationaleCtrl = TextEditingController(
    text: widget.initial?.rationaleMd ?? '',
  );
  late final _scopeCtrl = TextEditingController(
    text: widget.initial?.scope ?? '*',
  );
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final existing = widget.initial;
      await repo.upsertPrinciple(
        KnowledgePrinciple(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          rationaleMd: _rationaleCtrl.text,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
          status: existing?.status ?? PrincipleStatus.active,
          declaredAt: existing?.declaredAt ?? stamp.now,
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
      title: l10n.knowledgePrincipleWriterTitle,
      subtitle: l10n.knowledgePrincipleWriterSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _stmtCtrl.text.trim().isEmpty,
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
                control: FTextFieldControl.managed(controller: _stmtCtrl),
                label: Text(l10n.knowledgeWriterStatementLabel),
                hint: l10n.knowledgePrincipleStatementHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              MarkdownEditorWithPreview(
                controller: _rationaleCtrl,
                label: l10n.knowledgeWriterRationaleMarkdownLabel,
                hint: l10n.knowledgePrincipleRationaleHint,
                minLines: 2,
                maxLines: 4,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _scopeCtrl),
                label: Text(l10n.knowledgeWriterScopeLabel),
                hint: '"*" / "investing" / "life"',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Assumption ───────────────────────────────────────────────────────────

class _AssumptionWriter extends ConsumerStatefulWidget {
  const _AssumptionWriter({this.initial});
  final KnowledgeAssumption? initial;
  @override
  ConsumerState<_AssumptionWriter> createState() => _AssumptionWriterState();
}

class _AssumptionWriterState extends ConsumerState<_AssumptionWriter> {
  late final _stmtCtrl = TextEditingController(
    text: widget.initial?.statement ?? '',
  );
  late final _scopeCtrl = TextEditingController(
    text: widget.initial?.scope ?? '*',
  );
  late double _confidence = widget.initial?.confidence ?? 0.7;
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final existing = widget.initial;
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          confidence: _confidence,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
          evidenceIds: existing?.evidenceIds ?? const <String>[],
          status: existing?.status ?? AssumptionStatus.active,
          declaredAt: existing?.declaredAt ?? stamp.now,
          lastVerifiedAt: existing?.lastVerifiedAt,
          mergedIntoId: existing?.mergedIntoId,
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
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeAssumptionWriterTitle,
      subtitle: l10n.knowledgeAssumptionWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _stmtCtrl.text.trim().isEmpty,
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
                control: FTextFieldControl.managed(controller: _stmtCtrl),
                label: Text(l10n.knowledgeWriterStatementLabel),
                hint: l10n.knowledgeAssumptionStatementHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            children: [
              Text(
                '${l10n.knowledgeWriterConfidenceLabel}: '
                '${_confidence.toStringAsFixed(2)}',
                style: typography.sm,
              ),
              FSlider(
                control: FSliderControl.liftedContinuous(
                  value: FSliderValue(max: _confidence.clamp(0, 1).toDouble()),
                  stepPercentage: 0.01,
                  onChange: (next) =>
                      setState(() => _confidence = next.max.clamp(0, 1)),
                ),
                tooltipBuilder: (_, next) => Text(next.toStringAsFixed(2)),
                semanticValueFormatterCallback: (next) =>
                    next.toStringAsFixed(2),
              ),
              SegmentedRow<double>(
                options: const <double>[0.3, 0.5, 0.7, 0.85, 0.95],
                value: _confidencePresetValue(_confidence),
                labelOf: (v) => v.toStringAsFixed(2),
                onChanged: (v) => setState(() => _confidence = v),
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _scopeCtrl),
                label: Text(l10n.knowledgeWriterScopeLabel),
                hint: '"*" / "investing" / "fire"',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _confidencePresetValue(double confidence) {
  for (final value in const <double>[0.3, 0.5, 0.7, 0.85, 0.95]) {
    if ((confidence - value).abs() < 0.005) return value;
  }
  return double.nan;
}

// ── Concept ──────────────────────────────────────────────────────────────

class _ConceptWriter extends ConsumerStatefulWidget {
  const _ConceptWriter({this.initial});
  final KnowledgeConcept? initial;
  @override
  ConsumerState<_ConceptWriter> createState() => _ConceptWriterState();
}

class _ConceptWriterState extends ConsumerState<_ConceptWriter> {
  late final _nameCtrl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _aliasesCtrl = TextEditingController(
    text: widget.initial?.aliases.join(', ') ?? '',
  );
  late final _summaryCtrl = TextEditingController(
    text: widget.initial?.summaryMd ?? '',
  );
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final aliases = _aliasesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final existing = widget.initial;
      await repo.upsertConcept(
        KnowledgeConcept(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          name: _nameCtrl.text.trim(),
          aliases: aliases,
          summaryMd: _summaryCtrl.text,
          relatedConceptIds: existing?.relatedConceptIds ?? const <String>[],
          createdAt: existing?.createdAt ?? stamp.now,
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
      title: l10n.knowledgeConceptWriterTitle,
      subtitle: l10n.knowledgeConceptWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _nameCtrl.text.trim().isEmpty,
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
                control: FTextFieldControl.managed(controller: _nameCtrl),
                label: Text(l10n.knowledgeWriterNameLabel),
                hint: l10n.knowledgeConceptNameHint,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _aliasesCtrl),
                label: Text(l10n.knowledgeWriterAliasLabel),
                hint: l10n.knowledgeConceptAliasesHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              MarkdownEditorWithPreview(
                controller: _summaryCtrl,
                label: l10n.knowledgeWriterSummaryMarkdownLabel,
                hint: l10n.knowledgeConceptSummaryHint,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Experiment ───────────────────────────────────────────────────────────

class _ExperimentWriter extends ConsumerStatefulWidget {
  const _ExperimentWriter({this.initial});
  final KnowledgeExperiment? initial;
  @override
  ConsumerState<_ExperimentWriter> createState() => _ExperimentWriterState();
}

class _ExperimentWriterState extends ConsumerState<_ExperimentWriter> {
  late final _hypoCtrl = TextEditingController(
    text: widget.initial?.hypothesis ?? '',
  );
  late final _methodCtrl = TextEditingController(
    text: widget.initial?.methodMd ?? '',
  );
  late final _metricsCtrl = TextEditingController(
    text: widget.initial?.metrics.join(', ') ?? '',
  );
  late String? _targetAssumptionId = widget.initial?.targetAssumptionId;
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final metrics = _metricsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final existing = widget.initial;
      await repo.upsertExperiment(
        KnowledgeExperiment(
          id: existing?.id ?? kKnowledgeUuid.v4(),
          hypothesis: _hypoCtrl.text.trim(),
          methodMd: _methodCtrl.text,
          metrics: metrics,
          status: existing?.status ?? ExperimentStatus.planned,
          targetAssumptionId: _targetAssumptionId,
          startedAt: existing?.startedAt ?? stamp.now,
          endedAt: existing?.endedAt,
          resultMd: existing?.resultMd,
          conclusionMd: existing?.conclusionMd,
          mergedIntoId: existing?.mergedIntoId,
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
      title: l10n.knowledgeExperimentWriterTitle,
      subtitle: l10n.knowledgeExperimentWriterSubtitle2,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving || _hypoCtrl.text.trim().isEmpty,
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
                control: FTextFieldControl.managed(controller: _hypoCtrl),
                label: Text(l10n.knowledgeWriterHypothesisLabel),
                hint: l10n.knowledgeExperimentHypothesisHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterPlanningSectionTitle,
            children: [
              MarkdownEditorWithPreview(
                controller: _methodCtrl,
                label: l10n.knowledgeWriterMethodMarkdownLabel,
                hint: l10n.knowledgeExperimentMethodHint,
                minLines: 2,
                maxLines: 4,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _metricsCtrl),
                label: Text(l10n.knowledgeWriterMetricsLabel),
                hint: l10n.knowledgeExperimentMetricsHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterReferencesSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              _AssumptionTargetPicker(
                selectedId: _targetAssumptionId,
                onChange: (id) => setState(() => _targetAssumptionId = id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssumptionTargetPicker extends ConsumerWidget {
  const _AssumptionTargetPicker({
    required this.selectedId,
    required this.onChange,
  });
  final String? selectedId;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(
            density: KnowledgeStateDensity.section,
          ),
          error: (e, _) => KnowledgeErrorState(
            title: AppLocalizations.of(context).knowledgeLoadFailed('$e'),
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
            density: KnowledgeStateDensity.section,
          ),
          data: (repo) => StreamBuilder<List<KnowledgeAssumption>>(
            stream: repo.watchAssumptions(ownerUserId: owner),
            builder: (context, snap) {
              if (snap.hasError) {
                return KnowledgeErrorState(
                  title: AppLocalizations.of(
                    context,
                  ).knowledgeLoadFailed('${snap.error}'),
                  density: KnowledgeStateDensity.section,
                );
              }
              final all = (snap.data ?? const <KnowledgeAssumption>[])
                  .where((a) => a.status == AssumptionStatus.active)
                  .toList(growable: false);
              if (all.isEmpty) {
                return KnowledgeEmptyState(
                  icon: FLucideIcons.badgeCheck,
                  title: AppLocalizations.of(
                    context,
                  ).knowledgeExperimentNoActiveAssumptions,
                  density: KnowledgeStateDensity.section,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(
                      context,
                    ).knowledgeExperimentTargetAssumptionLabel,
                    style: context.labelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  for (final a in all)
                    KnowledgeSelectableRow(
                      label: a.statement,
                      selected: selectedId == a.id,
                      mode: KnowledgeSelectionMode.radio,
                      onPress: () => onChange(selectedId == a.id ? null : a.id),
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

// ── Note ─────────────────────────────────────────────────────────────────

class _NoteWriter extends ConsumerStatefulWidget {
  const _NoteWriter({required this.initial});
  final KnowledgeNote initial;
  @override
  ConsumerState<_NoteWriter> createState() => _NoteWriterState();
}

class _NoteWriterState extends ConsumerState<_NoteWriter> {
  late final _titleCtrl = TextEditingController(text: widget.initial.title);
  late final _bodyCtrl = TextEditingController(text: widget.initial.bodyMd);
  late final _sourceUrlCtrl = TextEditingController(
    text: widget.initial.sourceUrl ?? '',
  );
  late final _tagsCtrl = TextEditingController(
    text: widget.initial.tags.join(', '),
  );
  late final _projectTagCtrl = TextEditingController(
    text: widget.initial.projectTag ?? '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _sourceUrlCtrl.dispose();
    _tagsCtrl.dispose();
    _projectTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final tags = _tagsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      await repo.upsertNote(
        KnowledgeNote(
          id: widget.initial.id,
          title: _titleCtrl.text.trim(),
          bodyMd: _bodyCtrl.text,
          sourceUrl: _sourceUrlCtrl.text.trim().isEmpty
              ? null
              : _sourceUrlCtrl.text.trim(),
          tags: tags,
          projectTag: _projectTagCtrl.text.trim().isEmpty
              ? null
              : _projectTagCtrl.text.trim(),
          createdAt: widget.initial.createdAt,
          mergedIntoId: widget.initial.mergedIntoId,
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
      title: l10n.knowledgeNoteEditTitle,
      subtitle: l10n.knowledgeNoteEditSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterCoreSectionTitle,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _titleCtrl),
                label: Text(l10n.knowledgeCaptureTitleField),
                hint: l10n.knowledgeCaptureTitleHint,
              ),
              MarkdownEditorWithPreview(
                controller: _bodyCtrl,
                label: l10n.knowledgeCaptureBodyField,
                hint: l10n.knowledgeCaptureBodyHint,
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeWriterEvidenceSectionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              FTextField(
                control: FTextFieldControl.managed(controller: _sourceUrlCtrl),
                label: Text(l10n.knowledgeNoteSourceUrlLabel),
                hint: 'https://...',
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _tagsCtrl),
                label: Text(l10n.knowledgeWriterAliasLabel),
                hint: l10n.knowledgeNoteTagsHint,
              ),
              FTextField(
                control: FTextFieldControl.managed(controller: _projectTagCtrl),
                label: Text(l10n.knowledgeDetailProjectLabel),
                hint: l10n.knowledgeNoteProjectHint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
