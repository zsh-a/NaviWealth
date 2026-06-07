/// KnowledgeOS read-only detail page for the non-Decision typed objects
/// (`docs/knowledgeos-domain.md` §3 — Note / Concept / Experiment /
/// Principle / Assumption / Routine).
///
/// Decision has its own editable page; these objects share one read view
/// keyed by `:kind` so every Library tile is tappable (the interaction
/// asymmetry called out in the 2026-05-29 audit). Loading is by id via
/// the repository `findX` accessors, so a referenced-but-archived row
/// still resolves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/visual/ai_markdown.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// The kinds this page can render. Mirrors the `:kind` path segment.
enum KnowledgeObjectKind {
  note,
  concept,
  experiment,
  principle,
  assumption,
  routine;

  static KnowledgeObjectKind? parse(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

class KnowledgeObjectDetailPage extends ConsumerStatefulWidget {
  const KnowledgeObjectDetailPage({
    super.key,
    required this.kind,
    required this.id,
  });
  final String kind;
  final String id;

  @override
  ConsumerState<KnowledgeObjectDetailPage> createState() =>
      _KnowledgeObjectDetailPageState();
}

class _KnowledgeObjectDetailPageState
    extends ConsumerState<KnowledgeObjectDetailPage> {
  Object? _object;
  Object? _error;
  List<KnowledgeConcept> _relatedConcepts = const <KnowledgeConcept>[];
  KnowledgeAssumption? _targetAssumption;
  List<KnowledgeNote> _evidenceNotes = const <KnowledgeNote>[];
  List<KnowledgeDecision> _referencingDecisions = const <KnowledgeDecision>[];
  List<KnowledgeExperiment> _targetingExperiments =
      const <KnowledgeExperiment>[];
  bool _loading = true;

  KnowledgeObjectKind? get _kind => KnowledgeObjectKind.parse(widget.kind);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final kind = _kind;
    if (kind == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final obj = await _fetch(repo, kind, widget.id);
      final related = await _fetchRelated(repo, obj);
      if (mounted) {
        setState(() {
          _object = obj;
          _relatedConcepts = related.relatedConcepts;
          _targetAssumption = related.targetAssumption;
          _evidenceNotes = related.evidenceNotes;
          _referencingDecisions = related.referencingDecisions;
          _targetingExperiments = related.targetingExperiments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<Object?> _fetch(
    KnowledgeRepository repo,
    KnowledgeObjectKind kind,
    String id,
  ) {
    return switch (kind) {
      KnowledgeObjectKind.note => repo.findNote(id),
      KnowledgeObjectKind.concept => repo.findConcept(id),
      KnowledgeObjectKind.experiment => repo.findExperiment(id),
      KnowledgeObjectKind.principle => repo.findPrinciple(id),
      KnowledgeObjectKind.assumption => repo.findAssumption(id),
      KnowledgeObjectKind.routine => repo.findRoutine(id),
    };
  }

  Future<_ObjectRelatedData> _fetchRelated(
    KnowledgeRepository repo,
    Object? obj,
  ) async {
    if (obj == null) return const _ObjectRelatedData();
    switch (obj) {
      case final KnowledgeConcept c:
        final related = <KnowledgeConcept>[];
        for (final id in c.relatedConceptIds) {
          final concept = await repo.findConcept(id);
          if (concept != null) related.add(concept);
        }
        return _ObjectRelatedData(relatedConcepts: related);
      case final KnowledgeExperiment e:
        final targetId = e.targetAssumptionId;
        if (targetId == null || targetId.isEmpty) {
          return const _ObjectRelatedData();
        }
        return _ObjectRelatedData(
          targetAssumption: await repo.findAssumption(targetId),
        );
      case final KnowledgePrinciple p:
        final decisions = await repo.listDecisions(
          ownerUserId: p.sync.ownerUserId,
          limit: 1000,
        );
        return _ObjectRelatedData(
          referencingDecisions: decisions
              .where((d) => d.principleIds.contains(p.id))
              .toList(growable: false),
        );
      case final KnowledgeAssumption a:
        final notes = <KnowledgeNote>[];
        for (final id in a.evidenceIds) {
          final note = await repo.findNote(id);
          if (note != null) notes.add(note);
        }
        final decisions = await repo.listDecisions(
          ownerUserId: a.sync.ownerUserId,
          limit: 1000,
        );
        final experiments = await repo.listExperiments(
          ownerUserId: a.sync.ownerUserId,
          limit: 1000,
        );
        return _ObjectRelatedData(
          evidenceNotes: notes,
          referencingDecisions: decisions
              .where((d) => d.assumptionIds.contains(a.id))
              .toList(growable: false),
          targetingExperiments: experiments
              .where((e) => e.targetAssumptionId == a.id)
              .toList(growable: false),
        );
    }
    return const _ObjectRelatedData();
  }

  @override
  Widget build(BuildContext context) {
    return ObjectDetailScaffold(title: _title(context), child: _buildBody());
  }

  String _title(BuildContext context) => switch (_kind) {
    KnowledgeObjectKind.note => AppLocalizations.of(
      context,
    ).knowledgeNoteDetailTitle,
    KnowledgeObjectKind.concept => AppLocalizations.of(
      context,
    ).knowledgeConceptDetailTitle,
    KnowledgeObjectKind.experiment => AppLocalizations.of(
      context,
    ).knowledgeExperimentDetailTitle,
    KnowledgeObjectKind.principle => AppLocalizations.of(
      context,
    ).knowledgePrincipleDetailTitle,
    KnowledgeObjectKind.assumption => AppLocalizations.of(
      context,
    ).knowledgeAssumptionDetailTitle,
    KnowledgeObjectKind.routine => AppLocalizations.of(
      context,
    ).knowledgeRoutineDetailTitle,
    null => AppLocalizations.of(context).knowledgeObjectDetailTitle,
  };

  Widget _buildBody() {
    if (_loading) return const KnowledgeLoadingState();
    final error = _error;
    if (error != null) {
      return KnowledgeErrorState(
        title: AppLocalizations.of(context).knowledgeLoadFailed('$error'),
        onRetry: _load,
      );
    }
    final obj = _object;
    if (obj == null) {
      return KnowledgeEmptyState(
        icon: FLucideIcons.fileQuestion,
        title: AppLocalizations.of(context).knowledgeObjectNotFound,
      );
    }
    final children = switch (obj) {
      final KnowledgeNote n => _noteSections(context, n),
      final KnowledgeConcept c => _conceptSections(
        context,
        c,
        relatedConcepts: _relatedConcepts,
      ),
      final KnowledgeExperiment e => _experimentSections(
        context,
        e,
        targetAssumption: _targetAssumption,
      ),
      final KnowledgePrinciple p => _principleSections(
        context,
        p,
        referencingDecisions: _referencingDecisions,
      ),
      final KnowledgeAssumption a => _assumptionSections(
        context,
        a,
        evidenceNotes: _evidenceNotes,
        referencingDecisions: _referencingDecisions,
        targetingExperiments: _targetingExperiments,
      ),
      final KnowledgeRoutine r => _routineSections(context, r),
      _ => const <Widget>[],
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: children,
    );
  }
}

class _ObjectRelatedData {
  const _ObjectRelatedData({
    this.relatedConcepts = const <KnowledgeConcept>[],
    this.targetAssumption,
    this.evidenceNotes = const <KnowledgeNote>[],
    this.referencingDecisions = const <KnowledgeDecision>[],
    this.targetingExperiments = const <KnowledgeExperiment>[],
  });

  final List<KnowledgeConcept> relatedConcepts;
  final KnowledgeAssumption? targetAssumption;
  final List<KnowledgeNote> evidenceNotes;
  final List<KnowledgeDecision> referencingDecisions;
  final List<KnowledgeExperiment> targetingExperiments;
}

// ── Per-type section builders ──────────────────────────────────────────────

Widget _heading(BuildContext context, String text, {String? badge}) {
  final typography = context.theme.typography;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(text, style: typography.lg)),
      if (badge != null) ...[
        const SizedBox(width: AppSpacing.s8),
        KnowledgeStatusLabel(label: badge),
      ],
    ],
  );
}

List<Widget> _noteSections(BuildContext context, KnowledgeNote n) {
  final l10n = AppLocalizations.of(context);
  final title = n.title.trim().isEmpty ? l10n.knowledgeUntitled : n.title;
  return [
    _heading(context, title),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: l10n.knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, n.createdAt, long: true),
        ),
        _MetaPill(
          label: l10n.knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, n.sync.updatedAt, long: true),
        ),
        if (n.projectTag != null && n.projectTag!.isNotEmpty)
          _MetaPill(
            label: l10n.knowledgeDetailProjectLabel,
            value: n.projectTag!,
          ),
        if (n.tags.isNotEmpty)
          _MetaPill(
            label: l10n.knowledgeDetailTagsLabel,
            value: n.tags.join(' · '),
          ),
      ],
    ),
    if (n.bodyMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: l10n.knowledgeDetailBodyTitle,
        children: [AiMarkdown(text: n.bodyMd)],
      ),
    ],
    if (n.sourceUrl != null && n.sourceUrl!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: l10n.knowledgeDetailSourceTitle,
        children: [
          Text(
            n.sourceUrl!,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    ],
  ];
}

List<Widget> _conceptSections(
  BuildContext context,
  KnowledgeConcept c, {
  required List<KnowledgeConcept> relatedConcepts,
}) {
  return [
    _heading(context, c.name),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, c.createdAt, long: true),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, c.sync.updatedAt, long: true),
        ),
        if (c.aliases.isNotEmpty)
          _MetaPill(
            label: AppLocalizations.of(context).knowledgeDetailAliasesLabel,
            value: c.aliases.join(' · '),
          ),
      ],
    ),
    if (c.summaryMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailSummaryTitle,
        children: [AiMarkdown(text: c.summaryMd)],
      ),
    ],
    if (relatedConcepts.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailRelatedConceptsTitle,
        children: [
          for (final concept in relatedConcepts)
            _RelatedObjectLink(
              label: concept.name,
              meta: concept.aliases.isEmpty
                  ? AppLocalizations.of(context).knowledgeConceptDetailTitle
                  : concept.aliases.join(' · '),
              onPress: () => context.pushNamed(
                AppRouteNames.knowledgeObjectDetail,
                pathParameters: {'kind': 'concept', 'id': concept.id},
              ),
            ),
        ],
      ),
    ],
  ];
}

List<Widget> _experimentSections(
  BuildContext context,
  KnowledgeExperiment e, {
  required KnowledgeAssumption? targetAssumption,
}) {
  final typography = context.theme.typography;
  return [
    _heading(context, e.hypothesis, badge: e.status.wire),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      trailing: KnowledgeStatusLabel(label: e.status.wire),
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailStartedLabel,
          value: knowledgeDate(context, e.startedAt, long: true),
        ),
        if (e.endedAt != null)
          _MetaPill(
            label: AppLocalizations.of(context).knowledgeDetailEndedLabel,
            value: knowledgeDate(context, e.endedAt!, long: true),
          ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, e.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (targetAssumption != null) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(
          context,
        ).knowledgeDetailTargetAssumptionTitle,
        children: [
          _RelatedObjectLink(
            label: targetAssumption.statement,
            meta:
                '${targetAssumption.status.wire} · ${targetAssumption.confidence.toStringAsFixed(2)}',
            onPress: () => context.pushNamed(
              AppRouteNames.knowledgeObjectDetail,
              pathParameters: {'kind': 'assumption', 'id': targetAssumption.id},
            ),
          ),
        ],
      ),
    ],
    if (e.methodMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailMethodTitle,
        children: [AiMarkdown(text: e.methodMd)],
      ),
    ],
    if (e.metrics.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailMetricsTitle,
        children: [Text(e.metrics.join(' · '), style: typography.sm)],
      ),
    ],
    if (e.resultMd != null && e.resultMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailResultTitle,
        children: [AiMarkdown(text: e.resultMd!)],
      ),
    ],
    if (e.conclusionMd != null && e.conclusionMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailConclusionTitle,
        children: [AiMarkdown(text: e.conclusionMd!)],
      ),
    ],
  ];
}

List<Widget> _principleSections(
  BuildContext context,
  KnowledgePrinciple p, {
  required List<KnowledgeDecision> referencingDecisions,
}) {
  return [
    _heading(context, p.statement, badge: p.status.wire),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      trailing: KnowledgeStatusLabel(label: p.status.wire),
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailScopeLabel,
          value: p.scope,
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailDeclaredLabel,
          value: knowledgeDate(context, p.declaredAt, long: true),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, p.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (p.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailRationaleTitle,
        children: [AiMarkdown(text: p.rationaleMd)],
      ),
    ],
    if (referencingDecisions.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      _DecisionLinksSection(decisions: referencingDecisions),
    ],
  ];
}

List<Widget> _assumptionSections(
  BuildContext context,
  KnowledgeAssumption a, {
  required List<KnowledgeNote> evidenceNotes,
  required List<KnowledgeDecision> referencingDecisions,
  required List<KnowledgeExperiment> targetingExperiments,
}) {
  return [
    _heading(context, a.statement, badge: a.status.wire),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      trailing: KnowledgeStatusLabel(label: a.status.wire),
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailConfidenceLabel,
          value: a.confidence.toStringAsFixed(2),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailScopeLabel,
          value: a.scope,
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailDeclaredLabel,
          value: knowledgeDate(context, a.declaredAt, long: true),
        ),
        if (a.lastVerifiedAt != null)
          _MetaPill(
            label: AppLocalizations.of(
              context,
            ).knowledgeDetailLastVerifiedLabel,
            value: knowledgeDate(context, a.lastVerifiedAt!, long: true),
          ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, a.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (evidenceNotes.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailEvidenceTitle,
        children: [
          for (final note in evidenceNotes)
            _RelatedObjectLink(
              label: note.title.isEmpty
                  ? AppLocalizations.of(context).knowledgeUntitled
                  : note.title,
              meta: knowledgeExcerpt(note.bodyMd),
            ),
        ],
      ),
    ],
    if (referencingDecisions.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      _DecisionLinksSection(decisions: referencingDecisions),
    ],
    if (targetingExperiments.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailExperimentsTitle,
        children: [
          for (final experiment in targetingExperiments)
            _RelatedObjectLink(
              label: experiment.hypothesis,
              meta: experiment.status.wire,
              onPress: () => context.pushNamed(
                AppRouteNames.knowledgeObjectDetail,
                pathParameters: {'kind': 'experiment', 'id': experiment.id},
              ),
            ),
        ],
      ),
    ],
  ];
}

List<Widget> _routineSections(BuildContext context, KnowledgeRoutine r) {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final days = r.daysUntilDue(now);
  final dueLabel = days < 0
      ? l10n.knowledgeRoutineOverdueDays(-days)
      : days == 0
      ? l10n.knowledgeRoutineDueToday
      : l10n.knowledgeRoutineDueInDays(days);
  return [
    _heading(context, r.statement, badge: r.status.wire),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      trailing: KnowledgeStatusLabel(label: r.status.wire),
      children: [
        _MetaPill(
          label: l10n.knowledgeDetailNextDueLabel,
          value:
              '${knowledgeDate(context, r.nextDueAt, long: true)} · $dueLabel',
        ),
        if (r.lastDoneAt != null)
          _MetaPill(
            label: l10n.knowledgeDetailLastDoneLabel,
            value: knowledgeDate(context, r.lastDoneAt!, long: true),
          ),
        _MetaPill(
          label: l10n.knowledgeDetailIntervalLabel,
          value: l10n.knowledgeProposalIntervalDays(r.intervalDays),
        ),
        _MetaPill(label: l10n.knowledgeDetailScopeLabel, value: r.scope),
        _MetaPill(
          label: l10n.knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, r.createdAt, long: true),
        ),
        _MetaPill(
          label: l10n.knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, r.sync.updatedAt, long: true),
        ),
      ],
    ),
  ];
}

const int _kMetadataCollapseThreshold = 4;

class _MetadataSection extends StatefulWidget {
  const _MetadataSection({required this.children, this.trailing});

  final List<Widget> children;
  final Widget? trailing;

  @override
  State<_MetadataSection> createState() => _MetadataSectionState();
}

class _MetadataSectionState extends State<_MetadataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final needsCollapse =
        widget.children.length > _kMetadataCollapseThreshold;
    final visibleChildren = needsCollapse && !_expanded
        ? widget.children.take(_kMetadataCollapseThreshold).toList()
        : widget.children;
    return KnowledgeSection.group(
      title: l10n.knowledgeDetailMetadataTitle,
      trailing: widget.trailing,
      children: [
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: visibleChildren,
        ),
        if (needsCollapse) ...[
          const SizedBox(height: AppSpacing.s4),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Icon(
                  _expanded
                      ? FLucideIcons.chevronUp
                      : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: typography.xs.copyWith(color: colors.mutedForeground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            value,
            style: typography.sm.copyWith(fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DecisionLinksSection extends StatelessWidget {
  const _DecisionLinksSection({required this.decisions});

  final List<KnowledgeDecision> decisions;

  @override
  Widget build(BuildContext context) {
    return KnowledgeSection.group(
      title: AppLocalizations.of(context).knowledgeDetailDecisionsTitle,
      children: [
        for (final decision in decisions)
          _RelatedObjectLink(
            label: decision.question,
            meta: decision.status.wire,
            onPress: () => context.pushNamed(
              AppRouteNames.knowledgeDecisionDetail,
              pathParameters: {'id': decision.id},
            ),
          ),
      ],
    );
  }
}

class _RelatedObjectLink extends StatelessWidget {
  const _RelatedObjectLink({
    required this.label,
    required this.meta,
    this.onPress,
  });

  final String label;
  final String meta;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: typography.sm,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    meta,
                    style: typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onPress != null) ...[
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
          ],
        ],
      ),
    );
    final press = onPress;
    return press == null ? row : FTappable(onPress: press, child: row);
  }
}
