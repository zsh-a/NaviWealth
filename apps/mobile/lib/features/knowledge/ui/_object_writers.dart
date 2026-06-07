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

Future<void> showNewAssumptionSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _AssumptionWriter(),
    );

Future<void> showNewConceptSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ConceptWriter(),
    );

Future<void> showNewExperimentSheet(BuildContext context, WidgetRef _) =>
    showAppFormSheet<void>(
      context: context,
      builder: (_) => const _ExperimentWriter(),
    );

// ── Principle ────────────────────────────────────────────────────────────

class _PrincipleWriter extends ConsumerStatefulWidget {
  const _PrincipleWriter();
  @override
  ConsumerState<_PrincipleWriter> createState() => _PrincipleWriterState();
}

class _PrincipleWriterState extends ConsumerState<_PrincipleWriter> {
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      await repo.upsertPrinciple(
        KnowledgePrinciple(
          id: kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          rationaleMd: _rationaleCtrl.text,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
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
  const _AssumptionWriter();
  @override
  ConsumerState<_AssumptionWriter> createState() => _AssumptionWriterState();
}

class _AssumptionWriterState extends ConsumerState<_AssumptionWriter> {
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: kKnowledgeUuid.v4(),
          statement: _stmtCtrl.text.trim(),
          confidence: _confidence,
          scope: _scopeCtrl.text.trim().isEmpty ? '*' : _scopeCtrl.text.trim(),
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
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final v in const <double>[0.3, 0.5, 0.7, 0.85, 0.95])
                    FButton(
                      variant: (_confidence - v).abs() < 0.005
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      onPress: () => setState(() => _confidence = v),
                      child: Text(v.toStringAsFixed(2)),
                    ),
                ],
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

// ── Concept ──────────────────────────────────────────────────────────────

class _ConceptWriter extends ConsumerStatefulWidget {
  const _ConceptWriter();
  @override
  ConsumerState<_ConceptWriter> createState() => _ConceptWriterState();
}

class _ConceptWriterState extends ConsumerState<_ConceptWriter> {
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
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
  const _ExperimentWriter();
  @override
  ConsumerState<_ExperimentWriter> createState() => _ExperimentWriterState();
}

class _ExperimentWriterState extends ConsumerState<_ExperimentWriter> {
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
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
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
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
